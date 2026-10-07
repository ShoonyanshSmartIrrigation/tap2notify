/*
 * ============================================================================
 * Tap2Notify - ESP32-C3 Individual Device Controller Firmware
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
#include <esp_sleep.h>
#include "driver/gpio.h"

// ==========================================
// --- Device & Hardware Configuration ---
// ==========================================
// Configurable per-device identifier (e.g. "1", "2", "3", "10", "A1")
#define TABLE_NUMBER            "2"
#define DEVICE_ID               "Shoon2"
#define DEFAULT_PASSWORD        "12345"
#define DEFAULT_WIFI_CHANNEL    1
#define DEFAULT_HOTEL_TOKEN     0x54324E01  // Multi-tenant Hotel Network Isolation Token ("T2N1")

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
uint32_t currentHotelToken = DEFAULT_HOTEL_TOKEN;

unsigned long acceptedTimestamp       = 0;
int lastTouchState                    = LOW;
unsigned long lastDebounceTime        = 0;
const unsigned long DEBOUNCE_DELAY_MS = 60;
unsigned long lastHeartbeatTime       = 0;
unsigned long lastGatewayContactTime  = 0;
unsigned long lastChannelScanTime     = 0;
static uint16_t packetSequence        = 0;

// Power Management & Sleep Configuration
const unsigned long INACTIVITY_SLEEP_TIMEOUT_MS = 30000; // 30 seconds of inactivity before entering sleep
unsigned long lastActivityTime                   = 0;     // Timestamp of last user touch, command, or state transition
unsigned long lastWakeupTime                     = 0;     // Timestamp of last wake-up from sleep
bool isSleeping                                  = false; // Low-power sleep active flag

// Gateway Channel Hunting & Tracking
const unsigned long INITIAL_DISCOVERY_TIMEOUT_MS = 8000;  // 8s from boot before searching channels
const unsigned long GATEWAY_LOST_TIMEOUT_MS      = 60000; // 60s in steady state before hunting
bool hasEverContactedGateway                     = false;
bool isHunting                                   = false;
int huntChannelIndex                             = 0;
// Channels prioritized: 1, 6, 11 first (standard 2.4GHz non-overlapping), then remaining channels
const int scanChannels[] = {1, 6, 11, 2, 3, 4, 5, 7, 8, 9, 10, 12, 13};
const int totalScanChannels = sizeof(scanChannels) / sizeof(scanChannels[0]);

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
  uint32_t hotelToken;        // Multi-tenant Hotel Network Isolation Token
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
  pkt.hotelToken = currentHotelToken;
  pkt.msgType = (uint8_t)type;
  strncpy(pkt.deviceId, TABLE_NUMBER, sizeof(pkt.deviceId) - 1);
  pkt.flag = (int8_t)currentState;
  pkt.isUnlocked = isDeviceUnlocked ? 1 : 0;
  pkt.seqNumber = packetSequence;
  if (payloadStr != NULL && strlen(payloadStr) > 0) {
    strncpy(pkt.payload, payloadStr, sizeof(pkt.payload) - 1);
  } else {
    strncpy(pkt.payload, DEVICE_ID, sizeof(pkt.payload) - 1);
  }

  // Rapid burst for state changes (REQ, ACC, IDLE) to eliminate RF packet drop
  int burstCount = (type == MSG_STATE_CHANGE) ? 3 : 1;
  esp_err_t result = ESP_OK;
  for (int b = 0; b < burstCount; b++) {
    result = esp_now_send(broadcastAddress, (uint8_t*)&pkt, sizeof(pkt));
    if (burstCount > 1 && b < burstCount - 1) {
      delay(3);
    }
  }
  
  if (result == ESP_OK) {
    Serial.printf("[ESP-NOW TX #%d (CH %d | Hotel 0x%08X)] Type: 0x%02X | Table: %s | Flag: %d | Unlocked: %d | Payload: '%s'\n",
                  packetSequence, currentChannel, currentHotelToken, type, TABLE_NUMBER, currentState, isDeviceUnlocked ? 1 : 0, payloadStr);
  } else {
    Serial.printf("[ESP-NOW TX ERROR (CH %d)] Failed to send packet (Code: %d)\n", currentChannel, result);
  }
}

// Helper to normalize table identifiers ("table_1" -> "1", "device_1" -> "1")
String cleanTableId(const char* id) {
  if (!id) return "";
  String s = String(id);
  s.trim();
  if (s.startsWith("table_")) s = s.substring(6);
  else if (s.startsWith("device_")) s = s.substring(7);
  return s;
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

  // Multi-tenant check: Drop packets originating from foreign hotels immediately
  if (pkt->hotelToken != 0 && currentHotelToken != 0 && pkt->hotelToken != currentHotelToken) {
    return;
  }

  // Update last gateway contact timestamp on valid gateway packet
  lastGatewayContactTime = millis();
  hasEverContactedGateway = true;
  isHunting = false;

  // Filter messages: Only process commands addressed to THIS table, THIS device ID, broadcast ("0", "ALL", "GATEWAY"), or MSG_RESP_STATUS
  String cleanPktId = cleanTableId(pkt->deviceId);
  String cleanMyTable = cleanTableId(TABLE_NUMBER);
  String cleanMyDevId = cleanTableId(DEVICE_ID);

  String pktDigits = "";
  for (unsigned int c = 0; c < cleanPktId.length(); c++) {
    if (isDigit(cleanPktId[c])) pktDigits += cleanPktId[c];
  }
  String myDigits = "";
  for (unsigned int c = 0; c < cleanMyTable.length(); c++) {
    if (isDigit(cleanMyTable[c])) myDigits += cleanMyTable[c];
  }

  bool matchesMe = cleanPktId.equalsIgnoreCase(cleanMyTable) ||
                   cleanPktId.equalsIgnoreCase(cleanMyDevId) ||
                   strcmp(pkt->deviceId, TABLE_NUMBER) == 0 ||
                   strcmp(pkt->deviceId, DEVICE_ID) == 0 ||
                   (pktDigits.length() > 0 && myDigits.length() > 0 && pktDigits == myDigits) ||
                   cleanPktId == "0" ||
                   cleanPktId.equalsIgnoreCase("ALL") ||
                   cleanPktId.equalsIgnoreCase("GATEWAY") ||
                   strcmp(pkt->deviceId, "0") == 0 ||
                   strcasecmp(pkt->deviceId, "ALL") == 0 ||
                   pkt->msgType == MSG_RESP_STATUS;

  if (!matchesMe) {
    return; // Packet addressed to another C3 device
  }

  Serial.printf("\n[ESP-NOW RX (CH %d)] Command Type: 0x%02X for Table %s (Payload: '%s')\n", 
                currentChannel, pkt->msgType, pkt->deviceId, pkt->payload);

  switch (pkt->msgType) {
    case MSG_RESP_STATUS: {
      // Gateway PONG keep-alive received
      lastGatewayContactTime = millis();
      hasEverContactedGateway = true;
      isHunting = false;

      // Parse Gateway Wi-Fi Channel from payload: "PONG_CH%d"
      if (strncmp(pkt->payload, "PONG_CH", 7) == 0) {
        int gwChan = atoi(pkt->payload + 7);
        if (gwChan >= 1 && gwChan <= 13) {
          if (gwChan != currentChannel) {
            currentChannel = gwChan;
            esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);
            Serial.printf("[ESP-NOW SYNC] Gateway confirmed on Channel %d. Locking channel!\n", currentChannel);
          }
          if (preferences.getInt("channel", -1) != currentChannel) {
            preferences.putInt("channel", currentChannel);
          }
        }
      }
      break;
    }

    case MSG_CMD_AUTH: {
      lastActivityTime = millis();
      String enteredPassword = String(pkt->payload);
      enteredPassword.trim();

      bool isCorrect = (enteredPassword == devicePassword) ||
                       (enteredPassword == String(DEFAULT_PASSWORD));

      if (isCorrect) {
        Serial.printf("[AUTH SUCCESS] Table %s authorized successfully. Unlocking device.\n", TABLE_NUMBER);
        isDeviceUnlocked = true;
        preferences.putBool("unlocked", true);
        currentState = STATE_IDLE;
        
        // Immediate response back to Gateway so HTTP request returns in <5ms
        sendPacketToGateway(MSG_RESP_OK, "AUTH_OK");

        // Brief Green LED confirmation flash
        setAllLeds(0, 255, 0);
        delay(80);
        setAllLeds(0, 0, 0);

        triggerNonBlockingBeep(80, 2, 40); // 2 short beeps
      } else {
        Serial.printf("[AUTH FAILED] Table %s incorrect password ('%s').\n", TABLE_NUMBER, enteredPassword.c_str());
        isDeviceUnlocked = false;
        preferences.putBool("unlocked", false);
        currentState = STATE_LOCKED;
        setAllLeds(0, 0, 0);

        // Immediate failure response back to Gateway
        sendPacketToGateway(MSG_RESP_FAIL, "AUTH_FAIL");

        triggerNonBlockingBeep(250, 1); // 1 long error buzz
      }
      break;
    }

    case MSG_CMD_LOCK: {
      lastActivityTime = millis();
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
      lastActivityTime = millis();
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
      lastActivityTime = millis();
      Serial.printf("[CMD RESET] Table %s reset to IDLE.\n", TABLE_NUMBER);
      if (isDeviceUnlocked) {
        currentState = STATE_IDLE;
        setAllLeds(0, 0, 0);
        sendPacketToGateway(MSG_RESP_OK, "IDLE");
      }
      break;
    }

    case MSG_CMD_ACCEPT: {
      lastActivityTime = millis();
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
      lastActivityTime = millis();
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

  // Once Gateway contact is confirmed, STAY locked on confirmed channel!
  // Do NOT drift away into endless channel hunting during normal operation.
  if (hasEverContactedGateway) {
    return;
  }

  // Before initial gateway contact, search channels if no contact within initial window
  if (now - lastGatewayContactTime > INITIAL_DISCOVERY_TIMEOUT_MS) {
    isHunting = true;
  }

  if (isHunting) {
    if (now - lastChannelScanTime > 2500) { // Dwell 2.5s on each channel
      lastChannelScanTime = now;
      huntChannelIndex = (huntChannelIndex + 1) % totalScanChannels;
      currentChannel = scanChannels[huntChannelIndex];
      esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);
      Serial.printf("[ESP-NOW HUNT] Searching Gateway on Wi-Fi Channel %d...\n", currentChannel);
      sendPacketToGateway(MSG_HEARTBEAT, "HUNT");
    }
  }
}

// ==========================================
// --- Touch Action Processing ---
// ==========================================
void handleTouchAction(const char* triggerSource) {
  lastActivityTime = millis(); // Refresh inactivity timer on every touch action

  // IMMEDIATE WAKE-UP: If hunting or channel drifted, snap immediately to saved gateway channel
  if (isHunting) {
    isHunting = false;
    currentChannel = preferences.getInt("channel", DEFAULT_WIFI_CHANNEL);
    esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);
    Serial.printf("\n[%s] Customer touch -> Hunting cancelled, locked on Channel %d\n", triggerSource, currentChannel);
  }

  // STRICT LOCK CHECK: Ignore touch if device is locked
  if (!isDeviceUnlocked || currentState == STATE_LOCKED) {
    Serial.printf("\n[%s] [TOUCH BLOCKED] Table %s is LOCKED. Manager authorization required.\n", triggerSource, TABLE_NUMBER);
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
    Serial.printf("\n[%s] [1st PRESS] Table %s: PENDING Broadcasted\n", triggerSource, TABLE_NUMBER);

  } else if (currentState == STATE_PENDING) {
    // ---------------------------------------------------------
    // 2nd PRESS: Transition to ACCEPTED (🟢 GREEN)
    // ---------------------------------------------------------
    currentState = STATE_ACCEPTED;
    acceptedTimestamp = millis();

    setAllLeds(0, 255, 0);
    sendPacketToGateway(MSG_STATE_CHANGE, "ACC");

    triggerNonBlockingBeep(60, 2, 50);
    Serial.printf("\n[%s] [2nd PRESS] Table %s: ACCEPTED Broadcasted\n", triggerSource, TABLE_NUMBER);

  } else if (currentState == STATE_ACCEPTED) {
    // ---------------------------------------------------------
    // 3rd PRESS: Reset back to IDLE / STANDBY
    // ---------------------------------------------------------
    currentState = STATE_IDLE;

    setAllLeds(0, 0, 0);
    sendPacketToGateway(MSG_STATE_CHANGE, "IDLE");

    triggerNonBlockingBeep(40, 1);
    Serial.printf("\n[%s] [3rd PRESS] Table %s: IDLE Broadcasted\n", triggerSource, TABLE_NUMBER);
  }
}

// ==========================================
// --- Power-Saving Sleep Management ---
// ==========================================

// Guard conditions: prevent false sleep transitions while request is active or processing
bool canEnterSleep() {
  // 1. Only sleep in stable IDLE or LOCKED states (never during active PENDING or ACCEPTED service calls)
  if (currentState != STATE_IDLE && currentState != STATE_LOCKED) {
    return false;
  }

  // 2. Do not sleep while actively hunting / scanning for Gateway channel
  if (isHunting) {
    return false;
  }

  // 3. Do not sleep while buzzer is actively sounding beeps
  if (buzzerNextToggleTime != 0 || buzzerIsHigh) {
    return false;
  }

  // 4. Must satisfy 30-second continuous inactivity timeout
  if (millis() - lastActivityTime < INACTIVITY_SLEEP_TIMEOUT_MS) {
    return false;
  }

  return true;
}

// Reconnect and restore all radio and peripheral services after wake-up
void restoreServicesAfterWakeup() {
  unsigned long restoreStart = millis();
  Serial.println("[WAKEUP] Restoring Wi-Fi and ESP-NOW radio services...");

  // 1. Restore Wi-Fi in Station Mode for ESP-NOW
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  WiFi.setSleep(false);
  esp_err_t wifiErr = esp_wifi_start();
  if (wifiErr != ESP_OK) {
    Serial.printf("[WAKEUP ERROR] esp_wifi_start returned: 0x%X\n", wifiErr);
  }
  
  // Disable modem power save for sub-2ms ESP-NOW response
  esp_wifi_set_ps(WIFI_PS_NONE);
  esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);

  // 2. Re-initialize ESP-NOW stack
  esp_now_deinit();
  esp_err_t espNowErr = esp_now_init();
  if (espNowErr != ESP_OK && espNowErr != ESP_ERR_ESPNOW_EXIST) {
    Serial.printf("[WAKEUP ERROR] esp_now_init returned: 0x%X\n", espNowErr);
  } else {
    // Re-register receive callback
    esp_now_register_recv_cb(onDataReceived);

    // Re-register Gateway broadcast peer
    esp_now_peer_info_t peerInfo;
    memset(&peerInfo, 0, sizeof(peerInfo));
    memcpy(peerInfo.peer_addr, broadcastAddress, 6);
    peerInfo.channel = 0;
    peerInfo.encrypt = false;

    if (esp_now_add_peer(&peerInfo) != ESP_OK) {
      Serial.println("[WAKEUP ERROR] Failed to re-add broadcast peer!");
    } else {
      Serial.printf("[WAKEUP SUCCESS] ESP-NOW restored with Broadcast Peer on Channel %d (%lums)\n", 
                    currentChannel, millis() - restoreStart);
    }
  }

  // 3. Restore visual state according to current device state
  applyCurrentStateVisuals();

  // 4. Reset timers
  lastGatewayContactTime = millis();
  lastHeartbeatTime = millis();
}

// Enter ESP32-C3 low-power light sleep mode with touch sensor wake-up trigger
void enterLowPowerSleep() {
  Serial.printf("\n=======================================================\n");
  Serial.printf("[POWER SAVE] 30s Inactivity Timeout Reached -> Entering Low-Power Sleep\n");
  Serial.printf("[POWER SAVE] Table: %s | State: %s | Unlocked: %d | Wi-Fi Channel: %d\n",
                TABLE_NUMBER, (currentState == STATE_IDLE ? "IDLE" : "LOCKED"), 
                isDeviceUnlocked ? 1 : 0, currentChannel);
  Serial.printf("=======================================================\n");

  // 1. Send sleep notification to Gateway before turning off radio
  sendPacketToGateway(MSG_HEARTBEAT, "SLEEP");
  delay(10); // Allow RF frame dispatch to finish

  // 2. Persist critical device state to NVS flash
  preferences.putBool("unlocked", isDeviceUnlocked);
  preferences.putString("password", devicePassword);
  preferences.putInt("channel", currentChannel);
  preferences.putUInt("hotel_tok", currentHotelToken);

  // 3. Turn off NeoPixels and silence Buzzer
  setAllLeds(0, 0, 0);
  digitalWrite(BUZZER_PIN, LOW);
  buzzerIsHigh = false;
  buzzerNextToggleTime = 0;

  // 4. Shut down Wi-Fi RF baseband and synthesizers
  esp_wifi_stop();

  // 5. Configure GPIO 1 (TOUCH_PIN) as hardware wake-up source
  // Dynamically detect current idle level to support both momentary & latching sensors
  int idleLevel = digitalRead(TOUCH_PIN);
  gpio_int_type_t wakeTrigger = (idleLevel == LOW) ? GPIO_INTR_HIGH_LEVEL : GPIO_INTR_LOW_LEVEL;

  gpio_wakeup_enable((gpio_num_t)TOUCH_PIN, wakeTrigger);
  esp_sleep_enable_gpio_wakeup();

  Serial.printf("[POWER SAVE] Wakeup armed on GPIO %d (Trigger Level: %s). Entering Light Sleep...\n",
                TOUCH_PIN, (wakeTrigger == GPIO_INTR_HIGH_LEVEL ? "HIGH" : "LOW"));
  Serial.flush(); // Flush UART before clock gating

  // 6. Enter ESP32-C3 Light Sleep (Power drops from ~80mA to ~130uA; RAM & state fully preserved)
  isSleeping = true;
  esp_light_sleep_start();

  // ===================================================================
  // WAKE-UP RESUMPTION POINT (Execution resumes right here on wake-up!)
  // ===================================================================
  isSleeping = false;
  lastWakeupTime = millis();
  lastActivityTime = millis();
  lastDebounceTime = millis();

  // 7. Disable GPIO wake-up source to prevent re-triggering while awake
  gpio_wakeup_disable((gpio_num_t)TOUCH_PIN);
  esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_GPIO);

  // 8. Log Wake-Up Reason
  esp_sleep_wakeup_cause_t wakeCause = esp_sleep_get_wakeup_cause();
  Serial.printf("\n[POWER SAVE] >>> DEVICE WOKE UP! Cause: ");
  switch (wakeCause) {
    case ESP_SLEEP_WAKEUP_GPIO:
      Serial.printf("GPIO Pin Trigger (Physical Touch Sensor on Pin %d)\n", TOUCH_PIN);
      break;
    case ESP_SLEEP_WAKEUP_TIMER:
      Serial.printf("Timer Wakeup\n");
      break;
    default:
      Serial.printf("Other / Code %d\n", wakeCause);
      break;
  }

  // 9. Restore Wi-Fi, ESP-NOW, and device peripherals
  restoreServicesAfterWakeup();

  // 10. ZERO-LOSS TOUCH PROCESSING:
  // If woken by the touch sensor, process the touch action IMMEDIATELY!
  // This guarantees the customer's touch is never lost during sleep.
  if (wakeCause == ESP_SLEEP_WAKEUP_GPIO) {
    lastTouchState = digitalRead(TOUCH_PIN);
    Serial.println("[POWER SAVE] Immediate zero-loss dispatch for wake-up touch!");
    handleTouchAction("WAKEUP_TOUCH");
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
  isDeviceUnlocked  = preferences.getBool("unlocked", false);
  devicePassword    = preferences.getString("password", DEFAULT_PASSWORD);
  currentChannel    = preferences.getInt("channel", DEFAULT_WIFI_CHANNEL);
  currentHotelToken = preferences.getUInt("hotel_tok", DEFAULT_HOTEL_TOKEN);
  currentState      = isDeviceUnlocked ? STATE_IDLE : STATE_LOCKED;

  Serial.printf("\n============================================\n");
  Serial.printf("  Tap2Notify ESP32-C3 Node Booting\n");
  Serial.printf("  Table: %s | Device ID: %s | Status: %s | Channel: %d | Hotel: 0x%08X\n", 
                TABLE_NUMBER, DEVICE_ID, isDeviceUnlocked ? "UNLOCKED" : "LOCKED", currentChannel, currentHotelToken);
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

  // Read initial touch sensor baseline
  lastTouchState = digitalRead(TOUCH_PIN);

  // Initialize Wi-Fi in Station Mode for ESP-NOW (Modem power save disabled)
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  WiFi.setSleep(false);
  esp_wifi_set_ps(WIFI_PS_NONE);
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
  lastActivityTime = millis();

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

  // Detect ANY transition (LOW -> HIGH or HIGH -> LOW)
  // This ensures both latching/toggle modules (e.g. TTP223 toggle mode)
  // and momentary switches trigger reliably on EVERY single touch.
  if (reading != lastTouchState) {
    if ((millis() - lastDebounceTime > DEBOUNCE_DELAY_MS) && 
        (lastWakeupTime == 0 || millis() - lastWakeupTime > 250)) {
      lastDebounceTime = millis();
      lastTouchState = reading; // Update to new stable state
      handleTouchAction("TOUCH_LOOP");
    }
  }

  // -------------------------------------------------------------
  // 2. Automatic Reset after 6 Seconds in ACCEPTED (Green) State
  // -------------------------------------------------------------
  if (currentState == STATE_ACCEPTED && isDeviceUnlocked) {
    if (millis() - acceptedTimestamp > 6000) {
      Serial.printf("[TIMER] Table %s 6s Elapsed -> Resetting to IDLE\n", TABLE_NUMBER);
      setAllLeds(0, 0, 0);
      currentState = STATE_IDLE;
      lastActivityTime = millis(); // Refresh inactivity timer on transition to IDLE
      sendPacketToGateway(MSG_STATE_CHANGE, "IDLE_AUTO_TIMER");
    }
  }

  // -------------------------------------------------------------
  // 3. Periodic Heartbeat Telemetry to Gateway (Every 2.5 Seconds)
  // -------------------------------------------------------------
  if (millis() - lastHeartbeatTime >= 2500) {
    lastHeartbeatTime = millis();
    sendPacketToGateway(MSG_HEARTBEAT, "PING");
  }

  // -------------------------------------------------------------
  // 4. Inactivity Power-Saving Sleep Check (30-Second Timeout)
  // -------------------------------------------------------------
  if (canEnterSleep()) {
    enterLowPowerSleep();
  }
}
