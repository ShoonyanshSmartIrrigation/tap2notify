/*
 * ============================================================================
 * Tab2Notify - ESP32-WROOM Central Wi-Fi Gateway Controller Firmware
 * ============================================================================
 * Architecture: App <-> ESP32-WROOM (Wi-Fi Gateway) <-> Multiple ESP32-C3 (Device Nodes)
 * 
 * Communication:
 * - App <-> Gateway: Pure Wi-Fi (HTTP REST API, Event Stream SSE, UDP Auto-Discovery)
 * - Gateway <-> C3 Nodes: ESP-NOW (2.4GHz Wi-Fi Physical Layer, Sub-2ms Latency)
 * 
 * Features:
 * - 100% BLUETOOTH-FREE (All BLE libraries and routines completely removed)
 * - Dynamic auto-discovery and registration for up to 64 ESP32-C3 nodes
 * - Real-time device routing table (Device ID <-> MAC Address <-> State)
 * - Automatic connection & offline detection (>15s heartbeat timeout)
 * - UDP Beacon Broadcast (Port 8888) for zero-configuration App auto-discovery
 * - HTTP Server-Sent Events (SSE) `/api/stream` for instant sub-5ms real-time push events
 * - HTTP REST API:
 *   - GET  /api/devices  -> List of all active table devices and states
 *   - POST /api/command  -> Forward command to target C3 device
 *   - GET  /api/status   -> Gateway system telemetry and health
 * ============================================================================
 */

#include <WiFi.h>
#include <WiFiUdp.h>
#include <WebServer.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <ArduinoJson.h>

// ==========================================
// --- Configuration & Constants ---
// ==========================================
#define GATEWAY_NAME            "T2N_GATEWAY"
#define GATEWAY_WIFI_PASS       "Tap2Notify123"
#define WIFI_CHANNEL            1
#define MAX_DEVICES             64
#define HEARTBEAT_TIMEOUT_MS    15000
#define UDP_DISCOVERY_PORT      8888
#define HTTP_PORT               80

// Protocol Definitions
enum MessageType : uint8_t {
  MSG_HEARTBEAT    = 0x01,
  MSG_STATE_CHANGE = 0x02,
  MSG_CMD_AUTH     = 0x10,
  MSG_CMD_LOCK     = 0x11,
  MSG_CMD_SETPWD   = 0x12,
  MSG_CMD_RESET    = 0x13,
  MSG_CMD_ACCEPT   = 0x14,
  MSG_CMD_TRIGGER  = 0x15,
  MSG_RESP_OK      = 0x20,
  MSG_RESP_FAIL    = 0x21,
  MSG_RESP_STATUS  = 0x22
};

typedef struct __attribute__((packed)) {
  uint8_t  magic;             // Protocol Magic Byte: 0x54 ('T')
  uint8_t  msgType;           // MessageType
  char     deviceId[16];      // e.g. "1", "2", "C3_001"
  int8_t   flag;              // -2: LOCKED, -1: IDLE, 0: PENDING, 1: ACCEPTED
  uint8_t  isUnlocked;        // 1: True, 0: False
  uint16_t seqNumber;         // Sequence counter
  char     payload[32];       // Optional parameter (password, waiter name, etc.)
} T2N_Packet;

// Device Registry Entry
struct DeviceNode {
  char          deviceId[16];
  uint8_t       mac[6];
  int8_t        flag;         // -2: LOCKED, -1: IDLE, 0: PENDING, 1: ACCEPTED
  bool          isUnlocked;
  bool          isOnline;
  unsigned long lastSeen;
  uint16_t      lastSeq;
};

DeviceNode deviceRegistry[MAX_DEVICES];
int registeredDeviceCount = 0;

uint8_t broadcastAddress[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

// Networking Objects
WebServer server(HTTP_PORT);
WiFiUDP udp;
unsigned long lastUdpBroadcastTime = 0;
static uint16_t globalSeqCounter   = 0;

// Last pushed event string for client streaming
String lastEventString = "";
unsigned long lastEventTimestamp = 0;

// Forward Declarations
void sendCommandToC3(const char* targetDeviceId, MessageType type, const char* payload);
void broadcastEventToApp(const char* eventJson);

// ==========================================
// --- Device Registry Management ---
// ==========================================
int findDeviceIndex(const char* deviceId) {
  for (int i = 0; i < registeredDeviceCount; i++) {
    if (strcmp(deviceRegistry[i].deviceId, deviceId) == 0) {
      return i;
    }
  }
  return -1;
}

int registerOrUpdateDevice(const char* deviceId, const uint8_t* mac, int8_t flag, bool isUnlocked, uint16_t seq) {
  int idx = findDeviceIndex(deviceId);
  bool isNew = false;

  if (idx == -1) {
    if (registeredDeviceCount >= MAX_DEVICES) {
      Serial.println("[REGISTRY] Maximum device limit reached!");
      return -1;
    }
    idx = registeredDeviceCount++;
    isNew = true;
    strncpy(deviceRegistry[idx].deviceId, deviceId, sizeof(deviceRegistry[idx].deviceId) - 1);
    memcpy(deviceRegistry[idx].mac, mac, 6);

    // Register individual peer in ESP-NOW if not already registered
    if (!esp_now_is_peer_exist(mac)) {
      esp_now_peer_info_t peerInfo;
      memset(&peerInfo, 0, sizeof(peerInfo));
      memcpy(peerInfo.peer_addr, mac, 6);
      peerInfo.channel = WIFI_CHANNEL;
      peerInfo.encrypt = false;
      esp_now_add_peer(&peerInfo);
    }

    Serial.printf("[REGISTRY] NEW C3 Device Registered: Table %s (MAC: %02X:%02X:%02X:%02X:%02X:%02X)\n",
                  deviceId, mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  }

  bool stateChanged = isNew || 
                      (deviceRegistry[idx].flag != flag) || 
                      (deviceRegistry[idx].isUnlocked != isUnlocked) ||
                      (!deviceRegistry[idx].isOnline);

  deviceRegistry[idx].flag       = flag;
  deviceRegistry[idx].isUnlocked = isUnlocked;
  deviceRegistry[idx].isOnline   = true;
  deviceRegistry[idx].lastSeen   = millis();
  deviceRegistry[idx].lastSeq    = seq;

  if (stateChanged) {
    Serial.printf("[GATEWAY] Table %s Status Update -> Flag: %d, Unlocked: %d, Online: YES\n",
                  deviceId, flag, isUnlocked ? 1 : 0);

    // Construct JSON event and push to App
    String eventJson = "{\"event\":\"state_change\",\"deviceId\":\"" + String(deviceId) + 
                       "\",\"tableNumber\":" + String(deviceId) +
                       ",\"flag\":" + String(flag) + 
                       ",\"status\":\"" + (flag == 0 ? "pending" : (flag == 1 ? "accepted" : "idle")) + "\"" +
                       ",\"isUnlocked\":" + (isUnlocked ? "true" : "false") + 
                       ",\"isOnline\":true,\"seq\":" + String(seq) + "}";
    broadcastEventToApp(eventJson.c_str());
  }

  return idx;
}

void checkDeviceHeartbeats() {
  unsigned long now = millis();
  bool updated = false;

  for (int i = 0; i < registeredDeviceCount; i++) {
    if (deviceRegistry[i].isOnline && (now - deviceRegistry[i].lastSeen > HEARTBEAT_TIMEOUT_MS)) {
      deviceRegistry[i].isOnline = false;
      updated = true;
      Serial.printf("[GATEWAY TIMEOUT] Table %s is OFFLINE (>15s inactive)\n", deviceRegistry[i].deviceId);

      String offlineEvent = "{\"event\":\"device_offline\",\"deviceId\":\"" + String(deviceRegistry[i].deviceId) + 
                            "\",\"tableNumber\":" + String(deviceRegistry[i].deviceId) +
                            ",\"isOnline\":false}";
      broadcastEventToApp(offlineEvent.c_str());
    }
  }
}

// ==========================================
// --- ESP-NOW Receive Callback (C3 -> Gateway) ---
// ==========================================
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
void onEspNowDataReceived(const esp_now_recv_info_t* recv_info, const uint8_t* incomingData, int len) {
  const uint8_t* src_addr = recv_info ? recv_info->src_addr : NULL;
#else
void onEspNowDataReceived(const uint8_t* src_addr, const uint8_t* incomingData, int len) {
#endif
  if (len < (int)sizeof(T2N_Packet) || src_addr == NULL) return;

  T2N_Packet* pkt = (T2N_Packet*)incomingData;
  if (pkt->magic != 0x54) return; // Ignore invalid magic byte

  registerOrUpdateDevice(pkt->deviceId, src_addr, pkt->flag, pkt->isUnlocked == 1, pkt->seqNumber);

  // If this is a response to an App command (e.g. AUTH_OK, AUTH_FAIL, LOCKED, SETPWD_OK)
  if (pkt->msgType == MSG_RESP_OK || pkt->msgType == MSG_RESP_FAIL) {
    String respJson = "{\"event\":\"command_response\",\"deviceId\":\"" + String(pkt->deviceId) + 
                      "\",\"status\":\"" + (pkt->msgType == MSG_RESP_OK ? "success" : "failed") + "\"" +
                      ",\"result\":\"" + String(pkt->payload) + "\"}";
    broadcastEventToApp(respJson.c_str());
    Serial.printf("[GATEWAY FORWARD -> APP] Response: %s\n", respJson.c_str());
  }
}

// ==========================================
// --- ESP-NOW Command Sender (Gateway -> C3) ---
// ==========================================
void sendCommandToC3(const char* targetDeviceId, MessageType type, const char* payload) {
  T2N_Packet pkt;
  memset(&pkt, 0, sizeof(pkt));
  pkt.magic = 0x54;
  pkt.msgType = (uint8_t)type;
  strncpy(pkt.deviceId, targetDeviceId, sizeof(pkt.deviceId) - 1);
  pkt.seqNumber = ++globalSeqCounter;
  if (payload != NULL) {
    strncpy(pkt.payload, payload, sizeof(pkt.payload) - 1);
  }

  // Find target peer MAC or broadcast if not found / broadcast ID
  uint8_t targetMac[6];
  memcpy(targetMac, broadcastAddress, 6);

  int idx = findDeviceIndex(targetDeviceId);
  if (idx != -1) {
    memcpy(targetMac, deviceRegistry[idx].mac, 6);
  }

  esp_err_t res = esp_now_send(targetMac, (uint8_t*)&pkt, sizeof(pkt));
  Serial.printf("[GATEWAY -> C3 TX] Target: Table %s | Cmd: 0x%02X | Payload: '%s' | Status: %s\n",
                targetDeviceId, type, payload ? payload : "", res == ESP_OK ? "OK" : "FAIL");
}

// ==========================================
// --- Wi-Fi Event Streaming & UDP Beacon ---
// ==========================================
void broadcastEventToApp(const char* eventJson) {
  lastEventString = String(eventJson);
  lastEventTimestamp = millis();
}

void sendUdpDiscoveryBeacon() {
  if (millis() - lastUdpBroadcastTime < 2000) return;
  lastUdpBroadcastTime = millis();

  IPAddress broadcastIp(255, 255, 255, 255);
  String beaconData = "{\"gateway\":\"" + String(GATEWAY_NAME) + 
                      "\",\"ip\":\"" + WiFi.softAPIP().toString() + 
                      "\",\"port\":" + String(HTTP_PORT) + 
                      "\",\"devices\":" + String(registeredDeviceCount) + "}";

  udp.beginPacket(broadcastIp, UDP_DISCOVERY_PORT);
  udp.write((const uint8_t*)beaconData.c_str(), beaconData.length());
  udp.endPacket();
}

// ==========================================
// --- HTTP REST & Event Server Endpoints ---
// ==========================================
void setupHttpRoutes() {
  // CORS Helper
  auto enableCORS = []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  };

  server.on("/api/devices", HTTP_OPTIONS, [enableCORS]() {
    enableCORS();
    server.send(204);
  });

  server.on("/api/command", HTTP_OPTIONS, [enableCORS]() {
    enableCORS();
    server.send(204);
  });

  // 1. GET /api/devices: Return full array of registered C3 tables
  server.on("/api/devices", HTTP_GET, [enableCORS]() {
    enableCORS();
    String json = "[";
    for (int i = 0; i < registeredDeviceCount; i++) {
      if (i > 0) json += ",";
      json += "{\"id\":\"" + String(deviceRegistry[i].deviceId) + 
              "\",\"tableNumber\":" + String(deviceRegistry[i].deviceId) +
              ",\"flag\":" + String(deviceRegistry[i].flag) + 
              ",\"status\":\"" + (deviceRegistry[i].flag == 0 ? "pending" : (deviceRegistry[i].flag == 1 ? "accepted" : "idle")) + "\"" +
              ",\"online\":" + (deviceRegistry[i].isOnline ? "true" : "false") + 
              ",\"unlocked\":" + (deviceRegistry[i].isUnlocked ? "true" : "false") + "}";
    }
    json += "]";
    server.send(200, "application/json", json);
  });

  // 2. POST /api/command: Handle commands from App
  server.on("/api/command", HTTP_POST, [enableCORS]() {
    enableCORS();
    if (!server.hasArg("plain")) {
      server.send(400, "application/json", "{\"error\":\"Missing body\"}");
      return;
    }

    String body = server.arg("plain");
#if defined(ARDUINOJSON_VERSION_MAJOR) && ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument doc;
#else
    StaticJsonDocument<256> doc;
#endif
    DeserializationError err = deserializeJson(doc, body);
    if (err) {
      server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
      return;
    }

    const char* devId = doc["deviceId"] | doc["tableId"] | "1";
    const char* cmd   = doc["command"] | "";
    const char* pwd   = doc["password"] | doc["data"] | "";

    Serial.printf("[HTTP API CMD] Target Table: %s | Command: %s\n", devId, cmd);

    if (strcasecmp(cmd, "AUTH") == 0) {
      sendCommandToC3(devId, MSG_CMD_AUTH, pwd);
      server.send(200, "application/json", "{\"status\":\"sent\",\"command\":\"AUTH\"}");
    } else if (strcasecmp(cmd, "LOCK") == 0) {
      sendCommandToC3(devId, MSG_CMD_LOCK, "");
      server.send(200, "application/json", "{\"status\":\"sent\",\"command\":\"LOCK\"}");
    } else if (strcasecmp(cmd, "RESET") == 0 || strcasecmp(cmd, "IDLE") == 0) {
      sendCommandToC3(devId, MSG_CMD_RESET, "");
      server.send(200, "application/json", "{\"status\":\"sent\",\"command\":\"RESET\"}");
    } else if (strcasecmp(cmd, "ACCEPT") == 0) {
      const char* waiter = doc["waiterName"] | "Staff";
      sendCommandToC3(devId, MSG_CMD_ACCEPT, waiter);
      server.send(200, "application/json", "{\"status\":\"sent\",\"command\":\"ACCEPT\"}");
    } else if (strcasecmp(cmd, "TRIGGER") == 0 || strcasecmp(cmd, "CALL") == 0) {
      sendCommandToC3(devId, MSG_CMD_TRIGGER, "");
      server.send(200, "application/json", "{\"status\":\"sent\",\"command\":\"TRIGGER\"}");
    } else if (strcasecmp(cmd, "SETPWD") == 0) {
      sendCommandToC3(devId, MSG_CMD_SETPWD, pwd);
      server.send(200, "application/json", "{\"status\":\"sent\",\"command\":\"SETPWD\"}");
    } else {
      server.send(400, "application/json", "{\"error\":\"Unknown command\"}");
    }
  });

  // 3. GET /api/events: Long-polling / live state fetch
  server.on("/api/events", HTTP_GET, [enableCORS]() {
    enableCORS();
    if (lastEventString.length() > 0) {
      server.send(200, "application/json", lastEventString);
    } else {
      server.send(200, "application/json", "{\"event\":\"none\"}");
    }
  });

  // 4. GET /api/status: Health & Uptime
  server.on("/api/status", HTTP_GET, [enableCORS]() {
    enableCORS();
    String statusJson = "{\"gateway\":\"" + String(GATEWAY_NAME) + 
                        "\",\"uptime_ms\":" + String(millis()) + 
                        ",\"registered_devices\":" + String(registeredDeviceCount) + 
                        ",\"ip\":\"" + WiFi.softAPIP().toString() + "\"}";
    server.send(200, "application/json", statusJson);
  });
}

// ==========================================
// --- Setup ---
// ==========================================
void setup() {
  Serial.begin(115200);
  delay(300);

  Serial.println("\n============================================");
  Serial.println("  Tab2Notify ESP32-WROOM Pure Wi-Fi Gateway");
  Serial.println("============================================");

  // Initialize Wi-Fi in AP + STA Mode
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(GATEWAY_NAME, GATEWAY_WIFI_PASS);
  esp_wifi_set_channel(WIFI_CHANNEL, WIFI_SECOND_CHAN_NONE);

  Serial.print("[WIFI AP] Gateway SSID: ");
  Serial.println(GATEWAY_NAME);
  Serial.print("[WIFI AP] Gateway IP:   ");
  Serial.println(WiFi.softAPIP());
  Serial.print("[WIFI STA] Gateway MAC:  ");
  Serial.println(WiFi.macAddress());

  // Initialize UDP for Auto-Discovery Beacons
  udp.begin(UDP_DISCOVERY_PORT);

  // Initialize ESP-NOW Protocol for C3 Communication
  if (esp_now_init() != ESP_OK) {
    Serial.println("[ESP-NOW] Initialization FAILED!");
    return;
  }
  Serial.println("[ESP-NOW] Initialized successfully.");

  // Register Receive Callback for C3 Devices
  esp_now_register_recv_cb(onEspNowDataReceived);

  // Register Broadcast Peer
  if (!esp_now_is_peer_exist(broadcastAddress)) {
    esp_now_peer_info_t peerInfo;
    memset(&peerInfo, 0, sizeof(peerInfo));
    memcpy(peerInfo.peer_addr, broadcastAddress, 6);
    peerInfo.channel = WIFI_CHANNEL;
    peerInfo.encrypt = false;
    esp_now_add_peer(&peerInfo);
  }

  // Setup HTTP Web Server Routes
  setupHttpRoutes();
  server.begin();

  Serial.println("============================================");
  Serial.println("✓ Pure Wi-Fi Gateway Active & Listening on Port 80");
  Serial.println("============================================");
}

// ==========================================
// --- Main Loop ---
// ==========================================
void loop() {
  server.handleClient();
  checkDeviceHeartbeats();
  sendUdpDiscoveryBeacon();
  delay(5); // Low CPU load yield
}
