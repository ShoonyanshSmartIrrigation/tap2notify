/*
 * ============================================================================
 * Tab2Notify - ESP32-WROOM Central Wi-Fi Gateway Controller Firmware
 * ============================================================================
 * Architecture: Mobile Phone -> Wi-Fi Router -> ESP32-WROOM (STA Mode) -> ESP32-C3 Devices
 * 
 * Communication:
 * - App <-> Gateway: Pure Wi-Fi over local Wi-Fi Router (HTTP REST API, SSE, UDP Beacon, mDNS)
 * - Gateway <-> C3 Nodes: ESP-NOW (2.4GHz Wi-Fi Physical Layer, Sub-2ms Latency)
 * 
 * Features:
 * - 100% BLUETOOTH-FREE (Zero BLE libraries, zero BLE overhead)
 * - ZERO HARDCODED ROUTER CREDENTIALS (100% dynamically configured via Mobile App & NVS)
 * - Pure Wi-Fi Station (STA) Mode for normal operation (No persistent hotspot when configured)
 * - Automatic Fallback Provisioning Hotspot (T2N_GATEWAY) on unconfigured initial boot
 * - Comprehensive Wi-Fi Event Logging (Exact connect/disconnect reasons decoded)
 * - Background Continuous Connection & Auto-Reconnect Engine
 * - Zero-Configuration Local Discovery:
 *   - UDP Discovery Beacon on Port 8888 (Broadcasts Router STA IP, router SSID, status)
 *   - mDNS Responder ("tap2notify.local" / "http://tap2notify.local")
 * - Wi-Fi Provisioning REST API:
 *   - GET  /api/wifi/scan       -> Scan and list available 2.4GHz Wi-Fi SSIDs
 *   - POST /api/wifi/configure  -> Save router SSID & password to NVS and connect in STA mode
 *   - GET  /api/wifi/status     -> Live router connection state, IP, RSSI
 *   - POST /api/wifi/reset      -> Clear saved router credentials and return to setup mode
 * - Device Management REST API:
 *   - GET  /api/devices         -> List of all active table devices and states
 *   - POST /api/command         -> Forward commands to target C3 device
 *   - GET  /api/events          -> Live status polling / event streaming
 *   - GET  /api/status          -> Gateway system telemetry and health
 * ============================================================================
 */

#include <WiFi.h>
#include <WiFiUdp.h>
#include <WebServer.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <ArduinoJson.h>

// ==========================================
// --- Configuration & Constants ---
// ==========================================
#define GATEWAY_SETUP_AP_SSID   "T2N_GATEWAY"
#define GATEWAY_SETUP_AP_PASS   "Tap2Notify123"

#define DEFAULT_WIFI_CHANNEL    1
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

// Networking & Storage Objects
WebServer server(HTTP_PORT);
WiFiUDP udp;
Preferences wifiPrefs;

// Wi-Fi State Variables (Loaded dynamically from NVS)
bool routerConfigured = false;
String routerSSID = "";
String routerPass = "";
String lastDisconnectReason = "None";
bool isSoftApActive = false;

unsigned long lastWifiCheckTime = 0;
unsigned long lastWifiConnectAttempt = 0;
unsigned long lastUdpBroadcastTime = 0;
static uint16_t globalSeqCounter = 0;

// Last pushed event string for client streaming
String lastEventString = "";
unsigned long lastEventTimestamp = 0;

// Forward Declarations
void sendCommandToC3(const char* targetDeviceId, MessageType type, const char* payload);
void broadcastEventToApp(const char* eventJson);
void connectToRouter();
void startFallbackSoftAP();
void initEspNow();

// ==========================================
// --- Wi-Fi Event Callbacks & Debugging ---
// ==========================================
const char* getDisconnectReasonName(uint8_t reason) {
  switch (reason) {
    case 1:  return "UNSPECIFIED";
    case 2:  return "AUTH_EXPIRE";
    case 3:  return "AUTH_LEAVE";
    case 4:  return "ASSOC_EXPIRE";
    case 5:  return "ASSOC_TOOMANY";
    case 6:  return "NOT_AUTHED";
    case 7:  return "NOT_ASSOCED";
    case 8:  return "ASSOC_LEAVE";
    case 9:  return "ASSOC_NOT_AUTHED";
    case 10: return "DISASSOC_PWRCAP_BAD";
    case 11: return "DISASSOC_SUPCHAN_BAD";
    case 13: return "IE_INVALID";
    case 14: return "MIC_FAILURE";
    case 15: return "4WAY_HANDSHAKE_TIMEOUT / WRONG PASSWORD";
    case 16: return "GROUP_KEY_UPDATE_TIMEOUT";
    case 17: return "IE_IN_4WAY_DIFFERS";
    case 18: return "GROUP_CIPHER_INVALID";
    case 19: return "PAIRWISE_CIPHER_INVALID";
    case 20: return "AKMP_INVALID";
    case 21: return "UNSUPP_RSN_IE_VERSION";
    case 22: return "INVALID_RSN_IE_CAP";
    case 23: return "802_1X_AUTH_FAILED";
    case 24: return "CIPHER_SUITE_REJECTED";
    case 201: return "NO_AP_FOUND (SSID NOT FOUND / OUT OF RANGE)";
    case 202: return "AUTH_FAIL (WRONG PASSWORD)";
    case 203: return "ASSOC_FAIL";
    case 204: return "HANDSHAKE_TIMEOUT";
    case 205: return "CONNECTION_FAIL";
    default: return "UNKNOWN_DISCONNECT_REASON";
  }
}

void onWiFiEvent(WiFiEvent_t event, WiFiEventInfo_t info) {
  switch (event) {
    case ARDUINO_EVENT_WIFI_STA_START:
      Serial.println("[WIFI EVENT] Wi-Fi Station Mode Started.");
      break;

    case ARDUINO_EVENT_WIFI_STA_CONNECTED:
      Serial.printf("[WIFI EVENT] Connected to AP SSID: '%s' (Channel: %d)\n", 
                    WiFi.SSID().c_str(), WiFi.channel());
      break;

    case ARDUINO_EVENT_WIFI_STA_GOT_IP:
      Serial.println("\n============================================");
      Serial.println("✓ [WIFI SUCCESS] Gateway Connected to Router!");
      Serial.printf("  Router SSID:  %s\n", WiFi.SSID().c_str());
      Serial.printf("  Assigned IP:  %s\n", WiFi.localIP().toString().c_str());
      Serial.printf("  Gateway IP:   %s\n", WiFi.gatewayIP().toString().c_str());
      Serial.printf("  Subnet Mask:  %s\n", WiFi.subnetMask().toString().c_str());
      Serial.printf("  DNS IP:       %s\n", WiFi.dnsIP().toString().c_str());
      Serial.printf("  Signal (RSSI):%d dBm\n", WiFi.RSSI());
      Serial.printf("  Wi-Fi Channel:%d\n", WiFi.channel());
      Serial.printf("  mDNS URL:     http://tap2notify.local\n");
      Serial.println("============================================");

      // Disable SoftAP once successfully connected to router
      if (isSoftApActive) {
        WiFi.softAPdisconnect(true);
        isSoftApActive = false;
        Serial.println("[WIFI AP] Provisioning hotspot disabled. Operating in pure STA mode.");
      }

      // Start / update mDNS responder
      MDNS.end();
      if (MDNS.begin("tap2notify")) {
        MDNS.addService("http", "tcp", HTTP_PORT);
        Serial.println("[mDNS] Responder active at 'tap2notify.local'");
      }

      // Ensure ESP-NOW peer & callbacks remain active on new Wi-Fi channel
      initEspNow();

      lastDisconnectReason = "Connected";
      break;

    case ARDUINO_EVENT_WIFI_AP_START:
      Serial.println("[WIFI EVENT] SoftAP Started for Provisioning.");
      initEspNow();
      break;

    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED: {
      uint8_t reason = info.wifi_sta_disconnected.reason;
      lastDisconnectReason = String(getDisconnectReasonName(reason)) + " (code " + String(reason) + ")";
      Serial.printf("[WIFI WARNING] Disconnected from Router! Reason: %s\n", lastDisconnectReason.c_str());
      if (routerConfigured && routerSSID.length() > 0) {
        WiFi.reconnect();
      }
      break;
    }

    default:
      break;
  }
}

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
      peerInfo.channel = 0; // Follow interface channel
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

  for (int i = 0; i < registeredDeviceCount; i++) {
    if (deviceRegistry[i].isOnline && (now - deviceRegistry[i].lastSeen > HEARTBEAT_TIMEOUT_MS)) {
      deviceRegistry[i].isOnline = false;
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

void initEspNow() {
  esp_err_t err = esp_now_init();
  if (err != ESP_OK && err != ESP_ERR_ESPNOW_EXIST) {
    Serial.printf("[ESP-NOW] Initialization error: 0x%X\n", err);
    return;
  }
  Serial.println("[ESP-NOW] Active and ready.");

  esp_now_register_recv_cb(onEspNowDataReceived);

  if (!esp_now_is_peer_exist(broadcastAddress)) {
    esp_now_peer_info_t peerInfo;
    memset(&peerInfo, 0, sizeof(peerInfo));
    memcpy(peerInfo.peer_addr, broadcastAddress, 6);
    peerInfo.channel = 0; // Dynamic interface channel
    peerInfo.encrypt = false;
    esp_now_add_peer(&peerInfo);
  }
}

// ==========================================
// --- Wi-Fi Event Streaming & UDP Beacon ---
// ==========================================
void broadcastEventToApp(const char* eventJson) {
  lastEventString = String(eventJson);
  lastEventTimestamp = millis();
}

String getActiveGatewayIp() {
  if (WiFi.status() == WL_CONNECTED) {
    return WiFi.localIP().toString();
  }
  if (isSoftApActive) {
    return WiFi.softAPIP().toString();
  }
  return "0.0.0.0";
}

void sendUdpDiscoveryBeacon() {
  if (millis() - lastUdpBroadcastTime < 2000) return;
  lastUdpBroadcastTime = millis();

  bool isStaConnected = (WiFi.status() == WL_CONNECTED);
  String activeIp = getActiveGatewayIp();

  IPAddress broadcastIp(255, 255, 255, 255);
  String beaconData = "{\"gateway\":\"T2N_GATEWAY"
                      "\",\"ip\":\"" + activeIp + 
                      "\",\"sta_ip\":\"" + (isStaConnected ? WiFi.localIP().toString() : "") + 
                      "\",\"ap_ip\":\"" + (isSoftApActive ? WiFi.softAPIP().toString() : "") + 
                      "\",\"port\":" + String(HTTP_PORT) + 
                      "\",\"ssid\":\"" + (isStaConnected ? WiFi.SSID() : routerSSID) + 
                      "\",\"sta_status\":\"" + (isStaConnected ? "connected" : (routerConfigured ? "connecting" : "unconfigured")) + 
                      "\",\"channel\":" + String(WiFi.channel()) + 
                      "\",\"devices\":" + String(registeredDeviceCount) + "}";

  udp.beginPacket(broadcastIp, UDP_DISCOVERY_PORT);
  udp.write((const uint8_t*)beaconData.c_str(), beaconData.length());
  udp.endPacket();
}

// ==========================================
// --- Wi-Fi Router Connection & Auto-Reconnect ---
// ==========================================
void startFallbackSoftAP() {
  if (isSoftApActive) return;
  Serial.println("\n============================================");
  Serial.println("[PROVISIONING MODE] No router configured / unreachable.");
  Serial.println("Starting Setup Hotspot 'T2N_GATEWAY' (192.168.4.1)...");
  Serial.println("Connect your phone's Wi-Fi to 'T2N_GATEWAY' to configure your router SSID.");
  Serial.println("============================================");

  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(GATEWAY_SETUP_AP_SSID, GATEWAY_SETUP_AP_PASS);
  isSoftApActive = true;
  Serial.print("[WIFI AP] Setup Hotspot Active. IP: ");
  Serial.println(WiFi.softAPIP());
}

void connectToRouter() {
  if (!routerConfigured || routerSSID.length() == 0) {
    startFallbackSoftAP();
    return;
  }

  Serial.printf("\n[WIFI STA] Connecting to configured Router SSID: '%s'...\n", routerSSID.c_str());
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.setSleep(false); // Disable modem power saving to prevent router AUTH_EXPIRE
  esp_wifi_set_ps(WIFI_PS_NONE);
  WiFi.disconnect();
  delay(100);

  WiFi.begin(routerSSID.c_str(), routerPass.c_str());
  lastWifiConnectAttempt = millis();

  // Wait synchronously up to 15 seconds for initial connection on boot / config
  int timeoutHalfSecs = 30;
  while (WiFi.status() != WL_CONNECTED && timeoutHalfSecs > 0) {
    delay(500);
    Serial.print(".");
    timeoutHalfSecs--;
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    WiFi.setSleep(false);
    esp_wifi_set_ps(WIFI_PS_NONE);
    Serial.printf("[WIFI STA] Connected! Router IP: %s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.printf("[WIFI STA ERROR] Could not connect to '%s' (Status code: %d, Reason: %s)\n", 
                  routerSSID.c_str(), WiFi.status(), lastDisconnectReason.c_str());
    startFallbackSoftAP();
  }
}

void maintainWifiConnection() {
  if (!routerConfigured || routerSSID.length() == 0) return;

  unsigned long now = millis();
  if (now - lastWifiCheckTime < 4000) return;
  lastWifiCheckTime = now;

  if (WiFi.status() != WL_CONNECTED) {
    if (now - lastWifiConnectAttempt > 5000) {
      Serial.printf("[WIFI STA] Auto-Reconnect: Re-attempting connection to '%s'...\n", routerSSID.c_str());
      WiFi.reconnect();
      lastWifiConnectAttempt = now;
    }
  } else {
    WiFi.setSleep(false);
    esp_wifi_set_ps(WIFI_PS_NONE);
  }
}

// ==========================================
// --- HTTP REST & Event Server Endpoints ---
// ==========================================
void setupHttpRoutes() {
  auto enableCORS = []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  };

  server.on("/api/devices", HTTP_OPTIONS, [enableCORS]() { enableCORS(); server.send(204); });
  server.on("/api/command", HTTP_OPTIONS, [enableCORS]() { enableCORS(); server.send(204); });
  server.on("/api/wifi/scan", HTTP_OPTIONS, [enableCORS]() { enableCORS(); server.send(204); });
  server.on("/api/wifi/configure", HTTP_OPTIONS, [enableCORS]() { enableCORS(); server.send(204); });
  server.on("/api/wifi/status", HTTP_OPTIONS, [enableCORS]() { enableCORS(); server.send(204); });
  server.on("/api/wifi/reset", HTTP_OPTIONS, [enableCORS]() { enableCORS(); server.send(204); });
  server.on("/api/status", HTTP_OPTIONS, [enableCORS]() { enableCORS(); server.send(204); });
  server.on("/api/events", HTTP_OPTIONS, [enableCORS]() { enableCORS(); server.send(204); });

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

  // 3. GET /api/wifi/scan: Scan local 2.4GHz Wi-Fi SSIDs
  server.on("/api/wifi/scan", HTTP_GET, [enableCORS]() {
    enableCORS();
    Serial.println("[WIFI PROVISION] Scanning nearby 2.4GHz Wi-Fi networks...");
    int n = WiFi.scanNetworks(false, true);
    String json = "[";
    for (int i = 0; i < n; i++) {
      if (i > 0) json += ",";
      json += "{\"ssid\":\"" + WiFi.SSID(i) + 
              "\",\"rssi\":" + String(WiFi.RSSI(i)) + 
              ",\"channel\":" + String(WiFi.channel(i)) + 
              ",\"secure\":" + (WiFi.encryptionType(i) != WIFI_AUTH_OPEN ? "true" : "false") + "}";
    }
    json += "]";
    WiFi.scanDelete();
    server.send(200, "application/json", json);
  });

  // 4. POST /api/wifi/configure: Save router SSID/Password and connect in STA mode
  server.on("/api/wifi/configure", HTTP_POST, [enableCORS]() {
    enableCORS();
    if (!server.hasArg("plain")) {
      server.send(400, "application/json", "{\"error\":\"Missing body\"}");
      return;
    }

#if defined(ARDUINOJSON_VERSION_MAJOR) && ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument doc;
#else
    StaticJsonDocument<256> doc;
#endif
    DeserializationError err = deserializeJson(doc, server.arg("plain"));
    if (err) {
      server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
      return;
    }

    String ssid = doc["ssid"] | "";
    String pass = doc["password"] | "";

    if (ssid.length() == 0) {
      server.send(400, "application/json", "{\"error\":\"SSID cannot be empty\"}");
      return;
    }

    routerSSID = ssid;
    routerPass = pass;
    routerConfigured = true;

    wifiPrefs.putString("ssid", routerSSID);
    wifiPrefs.putString("pass", routerPass);
    wifiPrefs.putBool("configured", true);

    Serial.printf("\n[WIFI PROVISION] New router credentials saved to NVS: SSID='%s'\n", routerSSID.c_str());

    // Respond to app first before re-initializing Wi-Fi
    server.send(200, "application/json", "{\"status\":\"configured\",\"ssid\":\"" + routerSSID + "\",\"message\":\"Credentials saved to NVS. Connecting in STA mode...\"}");
    delay(200);

    connectToRouter();
  });

  // 5. GET /api/wifi/status: Connection telemetry
  server.on("/api/wifi/status", HTTP_GET, [enableCORS]() {
    enableCORS();
    bool isStaConnected = (WiFi.status() == WL_CONNECTED);
    String json = "{\"configured\":" + String(routerConfigured ? "true" : "false") + 
                  ",\"ssid\":\"" + (isStaConnected ? WiFi.SSID() : routerSSID) + "\"" +
                  ",\"status\":\"" + (isStaConnected ? "connected" : (routerConfigured ? "connecting" : "unconfigured")) + "\"" +
                  ",\"mode\":\"" + (isStaConnected ? "STA" : (isSoftApActive ? "AP_STA" : "STA")) + "\"" +
                  ",\"sta_ip\":\"" + (isStaConnected ? WiFi.localIP().toString() : "") + "\"" +
                  ",\"ap_ip\":\"" + (isSoftApActive ? WiFi.softAPIP().toString() : "") + "\"" +
                  ",\"rssi\":" + String(isStaConnected ? WiFi.RSSI() : 0) + 
                  ",\"channel\":" + String(WiFi.channel()) + 
                  ",\"disconnect_reason\":\"" + lastDisconnectReason + "\"" +
                  ",\"mdns\":\"tap2notify.local\"}";
    server.send(200, "application/json", json);
  });

  // 6. POST /api/wifi/reset: Clear router credentials
  server.on("/api/wifi/reset", HTTP_POST, [enableCORS]() {
    enableCORS();
    wifiPrefs.clear();
    routerConfigured = false;
    routerSSID = "";
    routerPass = "";
    WiFi.disconnect(true);
    Serial.println("[WIFI PROVISION] Router credentials cleared from NVS.");
    startFallbackSoftAP();
    server.send(200, "application/json", "{\"status\":\"reset_complete\"}");
  });

  // 7. GET /api/events: Live event fetch
  server.on("/api/events", HTTP_GET, [enableCORS]() {
    enableCORS();
    if (lastEventString.length() > 0) {
      server.send(200, "application/json", lastEventString);
    } else {
      server.send(200, "application/json", "{\"event\":\"none\"}");
    }
  });

  // 8. GET /api/status: Health & Telemetry
  server.on("/api/status", HTTP_GET, [enableCORS]() {
    enableCORS();
    bool isStaConnected = (WiFi.status() == WL_CONNECTED);
    String statusJson = "{\"gateway\":\"T2N_GATEWAY"
                        "\",\"uptime_ms\":" + String(millis()) + 
                        ",\"registered_devices\":" + String(registeredDeviceCount) + 
                        ",\"ip\":\"" + getActiveGatewayIp() + "\"" +
                        ",\"sta_ip\":\"" + (isStaConnected ? WiFi.localIP().toString() : "") + "\"" +
                        ",\"ap_ip\":\"" + (isSoftApActive ? WiFi.softAPIP().toString() : "") + "\"" +
                        ",\"mode\":\"" + (isStaConnected ? "STA" : (isSoftApActive ? "AP_STA" : "STA")) + "\"" +
                        ",\"sta_connected\":" + (isStaConnected ? "true" : "false") + "}";
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

  // Register Wi-Fi Event Handler for detailed status & disconnect logging
  WiFi.onEvent(onWiFiEvent);

  // Initialize NVS Storage for Wi-Fi Router Settings
  wifiPrefs.begin("t2n_wifi", false);
  routerConfigured = wifiPrefs.getBool("configured", false);
  routerSSID = wifiPrefs.getString("ssid", "");
  routerPass = wifiPrefs.getString("pass", "");

  Serial.print("[WIFI STA] Gateway MAC Address: ");
  Serial.println(WiFi.macAddress());

  // If credentials exist in NVS, connect to router in pure STA mode.
  // Otherwise start setup hotspot T2N_GATEWAY for app provisioning.
  if (routerConfigured && routerSSID.length() > 0) {
    Serial.printf("[WIFI STA] Found stored router credentials in NVS (SSID: '%s'). Connecting in STA mode...\n", routerSSID.c_str());
    connectToRouter();
  } else {
    Serial.println("[PROVISIONING] No router credentials configured yet in NVS.");
    startFallbackSoftAP();
  }

  // Initialize UDP for Auto-Discovery Beacons
  udp.begin(UDP_DISCOVERY_PORT);

  // Initialize ESP-NOW Protocol for C3 Communication
  initEspNow();

  // Setup HTTP Web Server Routes
  setupHttpRoutes();
  server.begin();

  Serial.println("============================================");
  Serial.printf("✓ Wi-Fi Gateway Server Listening on Port %d\n", HTTP_PORT);
  Serial.println("============================================");
}

// ==========================================
// --- Main Loop ---
// ==========================================
void loop() {
  server.handleClient();
  checkDeviceHeartbeats();
  sendUdpDiscoveryBeacon();
  maintainWifiConnection();
  delay(5); // Low CPU load yield
}
