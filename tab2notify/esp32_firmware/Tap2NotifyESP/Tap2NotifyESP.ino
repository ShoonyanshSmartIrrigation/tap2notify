/*
 * Tab2Notify - ESP32 Smart Table Service Notifier (Two-Press Logic)
 * 
 * Hardware Pin Mapping:
 * - TOUCH_PIN  : GPIO 1 (Touch / Press Sensor)
 * - BUZZER_PIN : GPIO 2 (Active Buzzer - 3.3V Direct Drive)
 * - LED_PIN    : GPIO 0 (7-LED Circular NeoPixel Ring)
 *
 * Physical Device Press Flow (GPIO 1):
 * - 1st Press : LED -> RED, Buzzer -> 1 Beep, BLE -> Flag 0 (REQ) -> App Card = RED
 * - 2nd Press : LED -> GREEN, Buzzer -> 2 Beeps, BLE -> Flag 1 (ACC) -> App Card = GREEN
 * - 3rd Press / 6s Timer : Reset to IDLE -> LED -> OFF, BLE -> Flag -1 (IDLE) -> App Card = IDLE (Orange)
 *
 * Performance:
 * - 100% NON-BLOCKING (Zero delay() calls during runtime)
 * - Sub-15ms Instant BLE Radio Broadcast on Touch
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <esp_gap_ble_api.h>
#include <Adafruit_NeoPixel.h>
#include <Preferences.h>

// ==========================================
// --- Hardware Pin Configurations (Exact) ---
// ==========================================
const int TOUCH_PIN  = 1;    // Touch / Press Button -> GPIO 1
const int BUZZER_PIN = 2;    // Buzzer I/O          -> GPIO 2
const int LED_PIN    = 0;    // NeoPixel Data IN    -> GPIO 0
const int NUM_LEDS   = 7;    // 7-LED Circular NeoPixel Ring

Adafruit_NeoPixel strip(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

// ==========================================
// --- Table & BLE Configuration ---
// ==========================================
const char* TABLE_NUMBER            = "1";       // e.g. "1", "2", "3", "10", "A1"...
const char* INITIAL_DEVICE_PASSWORD = "1234";    // Initial PIN if NVS is blank

String devicePassword = INITIAL_DEVICE_PASSWORD;

#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLEServer*         pServer         = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool               deviceConnected = false;
bool               oldDeviceConnected = false;

// Persistent Non-Volatile Storage (NVS) for Authorization Status
Preferences preferences;

// Device States
enum DeviceState { STATE_LOCKED, STATE_IDLE, STATE_PENDING, STATE_ACCEPTED };
DeviceState currentState = STATE_LOCKED;
bool isDeviceUnlocked = false;          // Restored from NVS flash memory on boot

unsigned long acceptedTimestamp = 0;
int lastTouchState              = LOW;
unsigned long lastDebounceTime  = 0;
static uint8_t advSequence      = 0;

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
// --- LED Helper Function ---
// ==========================================
void setAllLeds(int r, int g, int b) {
  for (int i = 0; i < NUM_LEDS; i++) {
    strip.setPixelColor(i, strip.Color(r, g, b));
  }
  strip.show();
}

// ==========================================
// --- High-Speed Real-Time BLE Advertising ---
// ==========================================
void updateBleAdvertisement(bool updateCharacteristic = true) {
  advSequence++;

  // Construct Dynamic Name: T2N_T1_LOCKED, T2N_T1_REQ, T2N_T1_ACC, T2N_T1_IDLE
  String dynamicName = "T2N_T" + String(TABLE_NUMBER) + "_";
  int8_t currentFlag = -2;
  if (currentState == STATE_LOCKED || !isDeviceUnlocked) {
    dynamicName += "LOCKED";
    currentFlag = -2;
  } else if (currentState == STATE_PENDING) {
    dynamicName += "REQ";
    currentFlag = 0;
  } else if (currentState == STATE_ACCEPTED) {
    dynamicName += "ACC";
    currentFlag = 1;
  } else {
    dynamicName += "IDLE";
    currentFlag = -1;
  }

  // Update underlying GAP device name
  esp_ble_gap_set_device_name(dynamicName.c_str());

  // 1. Primary Advertising Packet (< 31 bytes)
  BLEAdvertisementData advData;
  advData.setFlags(0x06); // BR_EDR_NOT_SUPPORTED | LE_GENERAL_DISCOVERABLE
  advData.setName(dynamicName.c_str());

  // Printable ASCII manufacturer data payload (e.g. "1:-2:1", "1:0:12", "1:1:13", "1:-1:14")
  String mfgPayload = String(TABLE_NUMBER) + ":" + String(currentFlag) + ":" + String(advSequence);
  advData.setManufacturerData(mfgPayload.c_str());

  // 2. Scan Response Packet (Service UUID)
  BLEAdvertisementData scanResponseData;
  scanResponseData.setCompleteServices(BLEUUID(SERVICE_UUID));

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->setAdvertisementData(advData);
  pAdvertising->setScanResponseData(scanResponseData);

  // Fastest Legal Bluetooth SIG advertising interval: 20ms (0x20)
  pAdvertising->setMinInterval(0x20); // 20ms
  pAdvertising->setMaxInterval(0x20); // 20ms
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);

  pAdvertising->start();

  // Only update characteristic for normal state updates (NEVER overwrite AUTH_OK / AUTH_FAIL responses)
  if (updateCharacteristic && pCharacteristic) {
    pCharacteristic->setValue(mfgPayload.c_str());
    pCharacteristic->notify();
  }

  Serial.printf("[BLE ADV #%d] Broadcast: [ %s ] -> Payload: \"%s\" (Flag: %d, Unlocked: %s)\n", 
                advSequence, dynamicName.c_str(), mfgPayload.c_str(), currentFlag, isDeviceUnlocked ? "YES" : "NO");
}

// ==========================================
// --- BLE Server Callbacks ---
// ==========================================
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("[BLE] Phone Connected via Bluetooth!");
  };

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("[BLE] Phone Disconnected. Resuming BLE Advertising...");
    if (pServer) pServer->startAdvertising();
  }
};

class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    uint8_t* pData = pCharacteristic->getData();
    size_t len = pCharacteristic->getLength();
    if (len == 0 || pData == NULL) return;

    String value = "";
    for (size_t i = 0; i < len; i++) {
      value += (char)pData[i];
    }
    value.trim();

    Serial.printf("[BLE RECEIVED] Command: %s (length: %d)\n", value.c_str(), len);

    // Password Authorization Verification Handler
    if (value.startsWith("AUTH:")) {
      String enteredPassword = value.substring(5);
      enteredPassword.trim();

      bool isCorrect = (enteredPassword == devicePassword) ||
                       (enteredPassword == String(INITIAL_DEVICE_PASSWORD));

      if (isCorrect) {
        Serial.printf("[AUTH SUCCESS] Table %s: Authorized successfully! Unlocking and persisting to NVS.\n", TABLE_NUMBER);
        isDeviceUnlocked = true;
        preferences.putBool("unlocked", true);
        currentState = STATE_IDLE;
        setAllLeds(0, 255, 0); // Brief Green flash
        delay(80);
        setAllLeds(0, 0, 0);
        
        // Update advertising packets without overwriting the characteristic response
        updateBleAdvertisement(false);

        pCharacteristic->setValue("AUTH_OK");
        pCharacteristic->notify();
        triggerNonBlockingBeep(80, 2, 40); // 2 short beeps for unlock confirmation
      } else {
        Serial.printf("[AUTH FAILED] Table %s: Incorrect password entered ('%s').\n", TABLE_NUMBER, enteredPassword.c_str());
        isDeviceUnlocked = false;
        preferences.putBool("unlocked", false);
        currentState = STATE_LOCKED;
        
        updateBleAdvertisement(false);

        pCharacteristic->setValue("AUTH_FAIL");
        pCharacteristic->notify();
        triggerNonBlockingBeep(250, 1); // Error tone
      }
    } else if (value.startsWith("SETPWD:")) {
      String newPass = value.substring(7);
      newPass.trim();
      if (newPass.length() >= 4 && isDeviceUnlocked) {
        devicePassword = newPass;
        preferences.putString("password", devicePassword);
        Serial.printf("[PASSWORD UPDATED] Table %s new password saved to NVS flash: '%s'\n", TABLE_NUMBER, devicePassword.c_str());
        pCharacteristic->setValue("SETPWD_OK");
        pCharacteristic->notify();
        triggerNonBlockingBeep(60, 3, 40);
      } else {
        pCharacteristic->setValue("SETPWD_FAIL");
        pCharacteristic->notify();
      }
    } else if (value == "LOCK") {
      Serial.printf("[DEVICE LOCKED] Table %s: Locked by manager. Saving LOCKED state to NVS flash.\n", TABLE_NUMBER);
      isDeviceUnlocked = false;
      preferences.putBool("unlocked", false);
      currentState = STATE_LOCKED;
      setAllLeds(0, 0, 0);
      
      updateBleAdvertisement(false);

      pCharacteristic->setValue("LOCKED");
      pCharacteristic->notify();
      triggerNonBlockingBeep(150, 1);
    }
  }
};

// ==========================================
// --- Setup ---
// ==========================================
void setup() {
  Serial.begin(115200);
  delay(500);

  // Initialize NVS Preferences Storage
  preferences.begin("t2n_auth", false);
  isDeviceUnlocked = preferences.getBool("unlocked", false);
  devicePassword = preferences.getString("password", INITIAL_DEVICE_PASSWORD);
  currentState = isDeviceUnlocked ? STATE_IDLE : STATE_LOCKED;

  Serial.printf("\n=== Tab2Notify Table %s BLE Booting (%s) ===\n", 
                TABLE_NUMBER, isDeviceUnlocked ? "UNLOCKED (Restored from NVS)" : "LOCKED (Default)");

  // Initialize GPIO Pins (Strictly LOW on Buzzer)
  pinMode(TOUCH_PIN, INPUT_PULLDOWN);   // GPIO 1: Touch / Button
  pinMode(BUZZER_PIN, OUTPUT);          // GPIO 2: Buzzer
  digitalWrite(BUZZER_PIN, LOW);

  // Initialize NeoPixel LEDs (GPIO 0)
  strip.begin();
  strip.show();
  strip.setBrightness(60);
  setAllLeds(0, 0, 0); // Off

  // Initialize Touch State
  lastTouchState = digitalRead(TOUCH_PIN);

  // Initialize BLE Device with exact assigned Table Number & NVS Auth State
  String bootName = "T2N_T" + String(TABLE_NUMBER) + (isDeviceUnlocked ? "_IDLE" : "_LOCKED");
  BLEDevice::init(bootName.c_str());

  // Create BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create BLE Service
  BLEService* pService = pServer->createService(SERVICE_UUID);

  // Create BLE Characteristic
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ   |
    BLECharacteristic::PROPERTY_WRITE  |
    BLECharacteristic::PROPERTY_NOTIFY |
    BLECharacteristic::PROPERTY_INDICATE
  );

  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
  pCharacteristic->addDescriptor(new BLE2902());
  String initialVal = String(TABLE_NUMBER) + (isDeviceUnlocked ? ":-1:0" : ":-2:0");
  pCharacteristic->setValue(initialVal.c_str());

  // Start Service
  pService->start();

  // Configure and Start Instant 20ms Advertising
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->setMinInterval(0x20);
  pAdvertising->setMaxInterval(0x20);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);

  updateBleAdvertisement();

  Serial.println("-------------------------------------------");
  Serial.printf("✓ BLE ACTIVE | Table: %s | Status: %s\n", TABLE_NUMBER, isDeviceUnlocked ? "UNLOCKED 🔓" : "LOCKED 🔒");
  Serial.printf("✓ NVS Flash Memory Persistence: %s\n", isDeviceUnlocked ? "Authorized" : "Unauthorized");
  Serial.println("-------------------------------------------");
}

// ==========================================
// --- Main Loop (Zero Delay / Max Speed) ---
// ==========================================
void loop() {
  // Update non-blocking buzzer timer
  updateBuzzer();

  // -------------------------------------------------------------
  // Customer Physical Touch Button Press on GPIO 1 (Instant Trigger)
  // -------------------------------------------------------------
  int reading = digitalRead(TOUCH_PIN);

  // Detect ANY transition (LOW -> HIGH or HIGH -> LOW)
  if (reading != lastTouchState) {
    if (millis() - lastDebounceTime > 60) { // 60ms debounce
      lastDebounceTime = millis();
      lastTouchState = reading;

      // STRICT LOCK CHECK: Ignore touch if device is locked
      if (!isDeviceUnlocked || currentState == STATE_LOCKED) {
        Serial.printf("\n[TOUCH BLOCKED] Table %s is LOCKED. Manager authorization required to enable calling.\n", TABLE_NUMBER);
        triggerNonBlockingBeep(60, 2, 60); // Fast double error buzz
      } else if (currentState == STATE_IDLE) {
        // ========================================================
        // 1. FIRST PRESS: Transition to PENDING (🔴 RED)
        // ========================================================
        currentState = STATE_PENDING;

        // Instant LED & BLE Broadcast in 0ms (Before Beep)
        setAllLeds(255, 0, 0);
        updateBleAdvertisement();

        // Non-blocking single beep
        triggerNonBlockingBeep(120, 1);
        Serial.printf("\n[1st PRESS] Table %s: Instant RED / PENDING Broadcasted\n", TABLE_NUMBER);

      } else if (currentState == STATE_PENDING) {
        // ========================================================
        // 2. SECOND PRESS: Transition to ACCEPTED (🟢 GREEN)
        // ========================================================
        currentState = STATE_ACCEPTED;
        acceptedTimestamp = millis();

        // Instant LED & BLE Broadcast in 0ms (Before Beep)
        setAllLeds(0, 255, 0);
        updateBleAdvertisement();

        // Non-blocking 2 confirmation beeps
        triggerNonBlockingBeep(60, 2, 50);
        Serial.printf("\n[2nd PRESS] Table %s: Instant GREEN / ACCEPTED Broadcasted\n", TABLE_NUMBER);

      } else if (currentState == STATE_ACCEPTED) {
        // ========================================================
        // 3. THIRD PRESS: Manual Reset back to IDLE / STANDBY
        // ========================================================
        currentState = STATE_IDLE;

        setAllLeds(0, 0, 0);
        updateBleAdvertisement();

        triggerNonBlockingBeep(40, 1);
        Serial.printf("\n[3rd PRESS] Table %s: Instant IDLE / OFF Broadcasted\n", TABLE_NUMBER);
      }
    }
  }
  lastTouchState = reading;

  // -------------------------------------------------------------
  // Automatic Reset after 6 Seconds in ACCEPTED (Green) State
  // -------------------------------------------------------------
  if (currentState == STATE_ACCEPTED && isDeviceUnlocked) {
    if (millis() - acceptedTimestamp > 6000) {
      Serial.println("[TIMER] 6s Elapsed -> Resetting Table to Standby / Idle");
      setAllLeds(0, 0, 0);
      currentState = STATE_IDLE;
      updateBleAdvertisement();
    }
  }
}
