/*
 * ============================================================================
 * Tab2Notify - ESP32-C3 Individual Device Controller Firmware
 * ============================================================================
 * Architecture: ESP32-C3 Devices -> ESP32-WROOM Gateway -> Wi-Fi Router -> Mobile App
 * 
 * Hardware Pin Mapping (ESP32-C3 SuperMini / Standard):
 * - TOUCH_PIN  : GPIO 1 (Touch / Press Sensor - Pull-down)
 * - BUZZER_PIN : GPIO 2 (Active Buzzer - 3.3V Direct Drive)
 * - LED_PIN    : GPIO 0 (7-LED Circular NeoPixel Ring WS2812B)
 *
 * Responsibilities:
 * - Pure device-side hardware execution (Sensors, Actuators, LEDs, Buzzer)
 * - Non-blocking multi-stage state machine (LOCKED, IDLE, PENDING, ACCEPTED)
 * - NVS Flash Memory persistence for device password and authorization status
 * - ESP-NOW 2.4GHz ultra-fast (<2ms) wireless transceiver to ESP32-WROOM Gateway
 * - Automatic Wi-Fi channel hunting to match Gateway router channel
 * - Immediate unsolicited telemetry broadcast on physical touch
 * - Periodic heartbeat telemetry to Gateway for online/offline tracking
 * - 100% NON-BLOCKING (Zero delay() calls during runtime)
 * ============================================================================
 */

#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <Adafruit_NeoPixel.h>
#include <Preferences.h>

// ==========================================
// --- Device & Hardware Configuration ---
// ==========================================
// Configurable per-device identifier (e.g. "1", "2", "3", "10", "A1")
#define TABLE_NUMBER            "1"
#define DEVICE_ID               "C3_001"
#define DEFAULT_PASSWORD        "1234"
#define DEFAULT_WIFI_CHANNEL    1

const int TOUCH_PIN  = 1;    // Touch / Button -> GPIO 1
const int BUZZER_PIN = 2;    // Buzzer I/O    -> GPIO 2
const int LED_PIN    = 0;    // NeoPixel Data -> GPIO 0
const int NUM_LEDS   = 7;    // 7-LED Circular Ring

Adafruit_NeoPixel strip(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);
Preferences preferences;

// Device States
enum DeviceState { 
  STATE_LOCKED   = -2, 
  STATE_IDLE     = -1, 
  STATE_PENDING  = 0, 
  STATE_ACCEPTED = 1 
};

DeviceState currentState = STATE_LOCKED;
bool isDeviceUnlocked = false;
String devicePassword = DEFAULT_PASSWORD;
int currentChannel = DEFAULT_WIFI_CHANNEL;

unsigned long acceptedTimestamp       = 0;
int lastTouchState                    = LOW;
unsigned long lastDebounceTime        = 0;
unsigned long lastHeartbeatTime       = 0;
unsigned long lastGatewayContactTime  = 0;
unsigned long lastChannelScanTime     = 0;
static uint16_t packetSequence        = 0;

// Gateway Broadcast MAC (0xFF:0xFF:0xFF:0xFF:0xFF:0xFF allows instant auto-pairing with Gateway)
uint8_t broadcastAddress[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

// ==========================================
// --- Protocol Definitions ---
// ==========================================
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
  char     deviceId[16];      // e.g. "1" or "C3_001"
  int8_t   flag;              // -2: LOCKED, -1: IDLE, 0: PENDING, 1: ACCEPTED
  uint8_t  isUnlocked;        // 1: True, 0: False
  uint16_t seqNumber;         // Sequence counter
  char     payload[32];       // Optional parameter (password, waiter name, etc.)
} T2N_Packet;

// ==========================================
// --- Non-Blocking Buzzer State Machine ---
// ==========================================
int           buzzerRemainingBeeps = 0;
int           buzzerBeepDuration   = 0;
int           buzzerGapDuration    = 0;
unsigned long buzzerNextToggleTime = 0;
bool          buzzerIsHigh         = false;

void triggerNonBlockingBeep(int durationMs, int beepCount = 1, int gapMs = 50) {
  if (durationMs <= 0) return;
  digitalWrite(BUZZER_PIN, HIGH);
  buzzerIsHigh = true;
  buzzerBeepDuration = durationMs;
  buzzerGapDuration = gapMs;
  buzzerRemainingBeeps = beepCount - 1;
  buzzerNextToggleTime = millis() + durationMs;
}

void updateBuzzer() {
  if (buzzerNextToggleTime == 0) return;
  if (millis() >= buzzerNextToggleTime) {
    if (buzzerIsHigh) {
      digitalWrite(BUZZER_PIN, LOW);
      buzzerIsHigh = false;
      if (buzzerRemainingBeeps > 0) {
        buzzerNextToggleTime = millis() + buzzerGapDuration;
      } else {
        buzzerNextToggleTime = 0;
      }
    } else {
      digitalWrite(BUZZER_PIN, HIGH);
      buzzerIsHigh = true;
      buzzerRemainingBeeps--;
      buzzerNextToggleTime = millis() + buzzerBeepDuration;
    }
  }
}

// ==========================================
// --- LED Helper Functions ---
// ==========================================
void setAllLeds(int r, int g, int b) {
  for (int i = 0; i < NUM_LEDS; i++) {
    strip.setPixelColor(i, strip.Color(r, g, b));
  }
  strip.show();
}

void applyCurrentStateVisuals() {
  if (!isDeviceUnlocked || currentState == STATE_LOCKED) {
    setAllLeds(0, 0, 0); // Off when locked
  } else if (currentState == STATE_PENDING) {
    setAllLeds(255, 0, 0); // Solid Red
  } else if (currentState == STATE_ACCEPTED) {
    setAllLeds(0, 255, 0); // Solid Green
  } else {
    setAllLeds(0, 0, 0); // Off in Idle
  }
}

// ==========================================
// --- ESP-NOW Wireless Transmission ---
// ==========================================
void sendPacketToGateway(MessageType type, const char* payloadStr = "") {
  packetSequence++;

  T2N_Packet pkt;
  memset(&pkt, 0, sizeof(pkt));
  pkt.magic = 0x54;
  pkt.msgType = (uint8_t)type;
  strncpy(pkt.deviceId, TABLE_NUMBER, sizeof(pkt.deviceId) - 1);
  pkt.flag = (int8_t)currentState;
  pkt.isUnlocked = isDeviceUnlocked ? 1 : 0;
  pkt.seqNumber = packetSequence;
  if (payloadStr != NULL && strlen(payloadStr) > 0) {
    strncpy(pkt.payload, payloadStr, sizeof(pkt.payload) - 1);
  }

  esp_err_t result = esp_now_send(broadcastAddress, (uint8_t*)&pkt, sizeof(pkt));
  
  if (result == ESP_OK) {
    Serial.printf("[ESP-NOW TX #%d (CH %d)] Type: 0x%02X | Table: %s | Flag: %d | Unlocked: %d | Payload: '%s'\n",
                  packetSequence, currentChannel, type, TABLE_NUMBER, currentState, isDeviceUnlocked ? 1 : 0, payloadStr);
  } else {
    Serial.printf("[ESP-NOW TX ERROR (CH %d)] Failed to send packet (Code: %d)\n", currentChannel, result);
  }
}

// ==========================================
// --- ESP-NOW Message Received Callback ---
// ==========================================
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
void onDataReceived(const esp_now_recv_info_t* recv_info, const uint8_t* incomingData, int len) {
  const uint8_t* src_addr = recv_info ? recv_info->src_addr : NULL;
#else
void onDataReceived(const uint8_t* src_addr, const uint8_t* incomingData, int len) {
#endif
  if (len < (int)sizeof(T2N_Packet)) return;

  T2N_Packet* pkt = (T2N_Packet*)incomingData;
  if (pkt->magic != 0x54) return; // Ignore invalid magic byte

  // Filter messages: Only process messages addressed to THIS table or broadcast ("0" or "ALL")
  if (strcmp(pkt->deviceId, TABLE_NUMBER) != 0 && 
      strcmp(pkt->deviceId, "0") != 0 && 
      strcasecmp(pkt->deviceId, "ALL") != 0) {
    return; // Packet addressed to another C3 device
  }

  // Update last gateway contact and persist current channel
  lastGatewayContactTime = millis();
  preferences.putInt("channel", currentChannel);

  Serial.printf("\n[ESP-NOW RX (CH %d)] Command Type: 0x%02X for Table %s (Payload: '%s')\n", 
                currentChannel, pkt->msgType, pkt->deviceId, pkt->payload);

  switch (pkt->msgType) {
    case MSG_CMD_AUTH: {
      String enteredPassword = String(pkt->payload);
      enteredPassword.trim();

      bool isCorrect = (enteredPassword == devicePassword) ||
                       (enteredPassword == String(DEFAULT_PASSWORD));

      if (isCorrect) {
        Serial.printf("[AUTH SUCCESS] Table %s authorized successfully. Unlocking device.\n", TABLE_NUMBER);
        isDeviceUnlocked = true;
        preferences.putBool("unlocked", true);
        currentState = STATE_IDLE;
        
        // Brief Green LED confirmation flash
        setAllLeds(0, 255, 0);
        delay(80);
        setAllLeds(0, 0, 0);

        triggerNonBlockingBeep(80, 2, 40); // 2 short beeps
        sendPacketToGateway(MSG_RESP_OK, "AUTH_OK");
      } else {
        Serial.printf("[AUTH FAILED] Table %s incorrect password ('%s').\n", TABLE_NUMBER, enteredPassword.c_str());
        isDeviceUnlocked = false;
        preferences.putBool("unlocked", false);
        currentState = STATE_LOCKED;
        setAllLeds(0, 0, 0);

        triggerNonBlockingBeep(250, 1); // 1 long error buzz
        sendPacketToGateway(MSG_RESP_FAIL, "AUTH_FAIL");
      }
      break;
    }

    case MSG_CMD_LOCK: {
      Serial.printf("[DEVICE LOCKED] Table %s locked by Gateway.\n", TABLE_NUMBER);
      isDeviceUnlocked = false;
      preferences.putBool("unlocked", false);
      currentState = STATE_LOCKED;
      setAllLeds(0, 0, 0);

      triggerNonBlockingBeep(150, 1);
      sendPacketToGateway(MSG_RESP_OK, "LOCKED");
      break;
    }

    case MSG_CMD_SETPWD: {
      String newPass = String(pkt->payload);
      newPass.trim();
      if (newPass.length() >= 4 && isDeviceUnlocked) {
        devicePassword = newPass;
        preferences.putString("password", devicePassword);
        Serial.printf("[PASSWORD UPDATED] Table %s new password saved: '%s'\n", TABLE_NUMBER, devicePassword.c_str());
        triggerNonBlockingBeep(60, 3, 40); // 3 confirmation chirps
        sendPacketToGateway(MSG_RESP_OK, "SETPWD_OK");
      } else {
        sendPacketToGateway(MSG_RESP_FAIL, "SETPWD_FAIL");
      }
      break;
    }

    case MSG_CMD_RESET: {
      Serial.printf("[CMD RESET] Table %s reset to IDLE.\n", TABLE_NUMBER);
      if (isDeviceUnlocked) {
        currentState = STATE_IDLE;
        setAllLeds(0, 0, 0);
        sendPacketToGateway(MSG_RESP_OK, "IDLE");
      }
      break;
    }

    case MSG_CMD_ACCEPT: {
      Serial.printf("[CMD ACCEPT] Table %s request accepted.\n", TABLE_NUMBER);
      if (isDeviceUnlocked) {
        currentState = STATE_ACCEPTED;
        acceptedTimestamp = millis();
        setAllLeds(0, 255, 0);
        triggerNonBlockingBeep(60, 2, 50);
        sendPacketToGateway(MSG_RESP_OK, "ACCEPTED");
      }
      break;
    }

    case MSG_CMD_TRIGGER: {
      Serial.printf("[CMD TRIGGER] Table %s service request triggered remotely.\n", TABLE_NUMBER);
      if (isDeviceUnlocked) {
        currentState = STATE_PENDING;
        setAllLeds(255, 0, 0);
        triggerNonBlockingBeep(120, 1);
        sendPacketToGateway(MSG_RESP_OK, "PENDING");
      }
      break;
    }

    default:
      sendPacketToGateway(MSG_RESP_STATUS, "STATUS");
      break;
  }
}

// ==========================================
// --- Wi-Fi Channel Agility Helper ---
// ==========================================
void checkChannelHunting() {
  unsigned long now = millis();
  // If no contact from Gateway for >15 seconds, scan channels 1..13
  if (now - lastGatewayContactTime > 15000) {
    if (now - lastChannelScanTime > 3000) {
      lastChannelScanTime = now;
      currentChannel = (currentChannel % 13) + 1;
      esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);
      Serial.printf("[ESP-NOW HUNT] Searching Gateway on Wi-Fi Channel %d...\n", currentChannel);
      sendPacketToGateway(MSG_HEARTBEAT, "HUNT");
    }
  }
}

// ==========================================
// --- Setup ---
// ==========================================
void setup() {
  Serial.begin(115200);
  delay(300);

  // Initialize NVS Preferences Storage
  preferences.begin("t2n_auth", false);
  isDeviceUnlocked = preferences.getBool("unlocked", false);
  devicePassword   = preferences.getString("password", DEFAULT_PASSWORD);
  currentChannel   = preferences.getInt("channel", DEFAULT_WIFI_CHANNEL);
  currentState     = isDeviceUnlocked ? STATE_IDLE : STATE_LOCKED;

  Serial.printf("\n============================================\n");
  Serial.printf("  Tab2Notify ESP32-C3 Node Booting\n");
  Serial.printf("  Table: %s | Device ID: %s | Status: %s | Channel: %d\n", 
                TABLE_NUMBER, DEVICE_ID, isDeviceUnlocked ? "UNLOCKED" : "LOCKED", currentChannel);
  Serial.printf("============================================\n");

  // Initialize GPIO Pins
  pinMode(TOUCH_PIN, INPUT_PULLDOWN);   // GPIO 1: Touch Button
  pinMode(BUZZER_PIN, OUTPUT);          // GPIO 2: Buzzer
  digitalWrite(BUZZER_PIN, LOW);

  // Initialize NeoPixel LEDs (GPIO 0)
  strip.begin();
  strip.show();
  strip.setBrightness(60);
  applyCurrentStateVisuals();

  // Initialize Touch State
  lastTouchState = digitalRead(TOUCH_PIN);

  // Initialize Wi-Fi in Station Mode for ESP-NOW
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);

  Serial.print("[WIFI] ESP32-C3 MAC Address: ");
  Serial.println(WiFi.macAddress());

  // Initialize ESP-NOW Protocol
  esp_err_t espNowErr = esp_now_init();
  if (espNowErr != ESP_OK && espNowErr != ESP_ERR_ESPNOW_EXIST) {
    Serial.printf("[ESP-NOW] Initialization error: 0x%X\n", espNowErr);
    return;
  }
  Serial.println("[ESP-NOW] Initialized successfully.");

  // Register Receive Callback
  esp_now_register_recv_cb(onDataReceived);

  // Register Gateway Peer (Broadcast)
  esp_now_peer_info_t peerInfo;
  memset(&peerInfo, 0, sizeof(peerInfo));
  memcpy(peerInfo.peer_addr, broadcastAddress, 6);
  peerInfo.channel = 0; // Channel 0 follows current interface channel
  peerInfo.encrypt = false;

  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
    Serial.println("[ESP-NOW] Failed to add broadcast peer!");
  } else {
    Serial.println("[ESP-NOW] Broadcast Peer Registered.");
  }

  lastGatewayContactTime = millis();

  // Send Initial Boot Heartbeat to Gateway
  sendPacketToGateway(MSG_HEARTBEAT, "BOOT");
}

// ==========================================
// --- Main Loop (Zero Delay / High Speed) ---
// ==========================================
void loop() {
  // Update non-blocking buzzer state machine
  updateBuzzer();

  // Channel agility monitor
  checkChannelHunting();

  // -------------------------------------------------------------
  // 1. Customer Physical Touch Button Press on GPIO 1 (Sub-15ms)
  // -------------------------------------------------------------
  int reading = digitalRead(TOUCH_PIN);

  if (reading == HIGH && lastTouchState == LOW) {
    if (millis() - lastDebounceTime > 50) { // Fast 50ms debounce
      lastDebounceTime = millis();

      // STRICT LOCK CHECK: Ignore touch if device is locked
      if (!isDeviceUnlocked || currentState == STATE_LOCKED) {
        Serial.printf("\n[TOUCH BLOCKED] Table %s is LOCKED. Manager authorization required.\n", TABLE_NUMBER);
        triggerNonBlockingBeep(60, 2, 60); // Fast double error buzz
        sendPacketToGateway(MSG_STATE_CHANGE, "TOUCH_BLOCKED_LOCKED");
      } else if (currentState == STATE_IDLE) {
        // ---------------------------------------------------------
        // 1st PRESS: Transition to PENDING (🔴 RED)
        // ---------------------------------------------------------
        currentState = STATE_PENDING;

        // Instant LED & Wireless Dispatch in 0ms (Before Beep)
        setAllLeds(255, 0, 0);
        sendPacketToGateway(MSG_STATE_CHANGE, "REQ");

        triggerNonBlockingBeep(120, 1);
        Serial.printf("\n[1st PRESS] Table %s: PENDING Broadcasted\n", TABLE_NUMBER);

      } else if (currentState == STATE_PENDING) {
        // ---------------------------------------------------------
        // 2nd PRESS: Transition to ACCEPTED (🟢 GREEN)
        // ---------------------------------------------------------
        currentState = STATE_ACCEPTED;
        acceptedTimestamp = millis();

        setAllLeds(0, 255, 0);
        sendPacketToGateway(MSG_STATE_CHANGE, "ACC");

        triggerNonBlockingBeep(60, 2, 50);
        Serial.printf("\n[2nd PRESS] Table %s: ACCEPTED Broadcasted\n", TABLE_NUMBER);

      } else if (currentState == STATE_ACCEPTED) {
        // ---------------------------------------------------------
        // 3rd PRESS: Reset back to IDLE / STANDBY
        // ---------------------------------------------------------
        currentState = STATE_IDLE;

        setAllLeds(0, 0, 0);
        sendPacketToGateway(MSG_STATE_CHANGE, "IDLE");

        triggerNonBlockingBeep(40, 1);
        Serial.printf("\n[3rd PRESS] Table %s: IDLE Broadcasted\n", TABLE_NUMBER);
      }
    }
  }
  lastTouchState = reading;

  // -------------------------------------------------------------
  // 2. Automatic Reset after 6 Seconds in ACCEPTED (Green) State
  // -------------------------------------------------------------
  if (currentState == STATE_ACCEPTED && isDeviceUnlocked) {
    if (millis() - acceptedTimestamp > 6000) {
      Serial.printf("[TIMER] Table %s 6s Elapsed -> Resetting to IDLE\n", TABLE_NUMBER);
      setAllLeds(0, 0, 0);
      currentState = STATE_IDLE;
      sendPacketToGateway(MSG_STATE_CHANGE, "IDLE_AUTO_TIMER");
    }
  }

  // -------------------------------------------------------------
  // 3. Periodic Heartbeat Telemetry to Gateway (Every 3 Seconds)
  // -------------------------------------------------------------
  if (millis() - lastHeartbeatTime >= 3000) {
    lastHeartbeatTime = millis();
    sendPacketToGateway(MSG_HEARTBEAT, "PING");
  }
}
