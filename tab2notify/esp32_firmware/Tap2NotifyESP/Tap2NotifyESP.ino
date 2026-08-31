#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Adafruit_NeoPixel.h>

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
const int TABLE_NUMBER = 1; // Table 1, Table 2, Table 3...

#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLEServer*         pServer         = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool               deviceConnected = false;
bool               oldDeviceConnected = false;

// Device States
enum DeviceState { STATE_IDLE, STATE_PENDING, STATE_ACCEPTED };
DeviceState currentState = STATE_IDLE;

unsigned long acceptedTimestamp = 0;
int lastTouchState              = LOW;
unsigned long lastDebounceTime  = 0;
String assignedWaiterName       = "";

// ==========================================
// --- LED & Buzzer Helper Functions ---
// ==========================================

void setAllLeds(int r, int g, int b) {
  for (int i = 0; i < NUM_LEDS; i++) {
    strip.setPixelColor(i, strip.Color(r, g, b));
  }
  strip.show();
}

// Direct Full-Volume Buzzer Beep - ONLY active during function call, held LOW otherwise
void triggerOriginalBeep(int durationMs) {
  if (durationMs <= 0) return;
  digitalWrite(BUZZER_PIN, HIGH);
  delay(durationMs);
  digitalWrite(BUZZER_PIN, LOW);
}

// ==========================================
// --- High-Speed Real-Time BLE Advertising ---
// ==========================================

void updateBleAdvertisement() {
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->stop();

  // Dynamic Name containing state (Instantly detected by Android / iOS)
  // Pending:  "T2N_T1_REQ"
  // Accepted: "T2N_T1_ACC"
  // Idle:     "T2N_T1_IDLE"
  String dynamicName = "T2N_T" + String(TABLE_NUMBER) + "_";
  if (currentState == STATE_PENDING) {
    dynamicName += "REQ";
  } else if (currentState == STATE_ACCEPTED) {
    dynamicName += "ACC";
  } else {
    dynamicName += "IDLE";
  }

  // Update underlying GAP device name
  esp_ble_gap_set_device_name(dynamicName.c_str());

  // 1. Primary Advertising Packet (< 31 bytes)
  BLEAdvertisementData advData;
  advData.setName(dynamicName.c_str());
  advData.setFlags(0x06); // BR_EDR_NOT_SUPPORTED | LE_GENERAL_DISCOVERABLE

  // Compact manufacturer data: "1:0" (Pending), "1:1:Staff" (Accepted), "1:-1" (Idle)
  String payload = String(TABLE_NUMBER) + ":";
  if (currentState == STATE_PENDING) {
    payload += "0";
  } else if (currentState == STATE_ACCEPTED) {
    payload += "1:" + assignedWaiterName;
  } else {
    payload += "-1";
  }
  advData.setManufacturerData(payload.c_str());

  // 2. Scan Response Packet (Service UUID)
  BLEAdvertisementData scanResponseData;
  scanResponseData.setCompleteServices(BLEUUID(SERVICE_UUID));

  pAdvertising->setAdvertisementData(advData);
  pAdvertising->setScanResponseData(scanResponseData);

  // Fast advertising interval: 20ms - 30ms (Instant response)
  pAdvertising->setMinInterval(0x20); // 20ms
  pAdvertising->setMaxInterval(0x30); // 30ms
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);

  pAdvertising->start();
  Serial.printf("[BLE ADV] Broadcast: [ %s ] -> State: %s (flag = %d)\n", 
                dynamicName.c_str(), 
                currentState == STATE_PENDING ? "PENDING / RED" : (currentState == STATE_ACCEPTED ? "ACCEPTED / GREEN" : "IDLE"),
                currentState == STATE_PENDING ? 0 : (currentState == STATE_ACCEPTED ? 1 : -1));
}

// ==========================================
// --- BLE Server Callbacks ---
// ==========================================

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("[BLE] Manager Phone Connected via Bluetooth!");
  };

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("[BLE] Manager Phone Disconnected. Resuming BLE Advertising...");
  }
};

// Callback when Manager writes to Characteristic (Accept / Reset Request)
class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue().c_str();

    if (value.length() > 0) {
      Serial.printf("[BLE RECEIVED] Command: %s\n", value.c_str());

      // Parse command: {"flag":1,"waiter":"Rajesh"} or "1:Rajesh" or {"flag":-1}
      if (value.indexOf("\"flag\":1") >= 0 || value.startsWith("1:") || value.indexOf("\"flag\": 1") >= 0) {
        // Extract Waiter Name
        String waiter = "Staff";
        int waiterIdx = value.indexOf("\"waiter\":\"");
        if (waiterIdx >= 0) {
          int start = waiterIdx + 10;
          int end = value.indexOf("\"", start);
          if (end > start) {
            waiter = value.substring(start, end);
          }
        } else if (value.startsWith("1:")) {
          waiter = value.substring(2);
        }

        assignedWaiterName = waiter;
        currentState = STATE_ACCEPTED;
        acceptedTimestamp = millis();

        Serial.printf("\n>>> [BLE ACCEPTED] Table %d Accepted! Assigned Server: %s <<<\n", TABLE_NUMBER, assignedWaiterName.c_str());

        // Update BLE advertisement immediately
        updateBleAdvertisement();

        // Stop buzzer pin completely
        digitalWrite(BUZZER_PIN, LOW);

        // Turn LED GREEN (flag = 1)
        setAllLeds(0, 255, 0);

        // Play 2 clean confirmation beeps
        triggerOriginalBeep(80);
        delay(60);
        triggerOriginalBeep(80);

      } else if (value.indexOf("\"flag\":-1") >= 0 || value.startsWith("-1") || value.indexOf("\"flag\": -1") >= 0) {
        // Reset to Idle
        currentState = STATE_IDLE;
        assignedWaiterName = "";
        setAllLeds(0, 0, 0);
        digitalWrite(BUZZER_PIN, LOW);
        Serial.printf("[BLE RESET] Table %d reset to IDLE.\n", TABLE_NUMBER);
        updateBleAdvertisement();
      }
    }
  }
};

// ==========================================
// --- Setup ---
// ==========================================
void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.printf("\n=== Tab2Notify Table %d Bluetooth (BLE) Booting ===\n", TABLE_NUMBER);

  // Initialize GPIO Pins (Strictly LOW on Buzzer)
  pinMode(TOUCH_PIN, INPUT_PULLDOWN);   // GPIO 1: Touch / Button
  pinMode(BUZZER_PIN, OUTPUT);          // GPIO 2: Buzzer
  digitalWrite(BUZZER_PIN, LOW);

  // Initialize NeoPixel LEDs (GPIO 0)
  strip.begin();
  strip.show();
  strip.setBrightness(60);
  setAllLeds(0, 0, 0); // Off / Idle

  // Initialize Touch State
  delay(50);
  lastTouchState = digitalRead(TOUCH_PIN);

  // Initialize BLE Device with exact assigned Table Number
  String bootName = "T2N_T" + String(TABLE_NUMBER) + "_IDLE";
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
  String initialVal = String(TABLE_NUMBER) + ":-1";
  pCharacteristic->setValue(initialVal.c_str());

  // Start Service
  pService->start();

  // Start Instant Advertising
  updateBleAdvertisement();

  Serial.println("-------------------------------------------");
  Serial.printf("✓ Bluetooth Low Energy (BLE) ACTIVE!\n");
  Serial.printf("✓ Assigned to Table %d\n", TABLE_NUMBER);
  Serial.println("✓ Real-Time Instant State Advertising: ACTIVE\n");
  Serial.println("-------------------------------------------");
}

// ==========================================
// --- Main Loop ---
// ==========================================
void loop() {
  // Ensure buzzer pin is always LOW when not explicitly beeping
  digitalWrite(BUZZER_PIN, LOW);

  // Restart advertising if disconnected
  if (!deviceConnected && oldDeviceConnected) {
    delay(300);
    pServer->startAdvertising();
    Serial.println("[BLE] Restarted BLE advertising");
    oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  // -------------------------------------------------------------
  // 1. Detect Customer Button Press on GPIO 1 (Instant BLE Broadcast)
  // -------------------------------------------------------------
  int reading = digitalRead(TOUCH_PIN);

  // Detect state change from LOW to HIGH (Instant response on EVERY press)
  if (reading == HIGH && lastTouchState == LOW) {
    if (millis() - lastDebounceTime > 150) {
      lastDebounceTime = millis();
      Serial.printf("\n[BUTTON TAP] Table %d touched! Instant BLE broadcast -> flag = 0 (PENDING / RED)...\n", TABLE_NUMBER);

      // 1. Transition state to PENDING (flag = 0)
      currentState = STATE_PENDING;

      // 2. LED turns RED (flag = 0)
      setAllLeds(255, 0, 0);

      // 3. Immediately Broadcast updated BLE Advertisement (Instant name change to T2N_T1_REQ!)
      updateBleAdvertisement();

      // 4. Update characteristic notification
      if (pCharacteristic) {
        String payload = String(TABLE_NUMBER) + ":0:pending";
        pCharacteristic->setValue(payload.c_str());
        pCharacteristic->notify();
      }

      // 5. Sound buzzer
      triggerOriginalBeep(150);
    }
  }
  lastTouchState = reading;

  // -------------------------------------------------------------
  // 2. Accepted State (flag = 1): Green LED stays for 5 seconds
  // -------------------------------------------------------------
  if (currentState == STATE_ACCEPTED) {
    if (millis() - acceptedTimestamp > 5000) {
      Serial.println("[TIMER] Resetting LEDs back to Standby/Idle");
      setAllLeds(0, 0, 0);
      currentState = STATE_IDLE;
      updateBleAdvertisement();
    }
  }

  delay(10);
}
