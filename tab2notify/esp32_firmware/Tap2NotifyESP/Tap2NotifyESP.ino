#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <ESPmDNS.h>
#include <Adafruit_NeoPixel.h>

// ==========================================
// --- Hardware Pin Configurations ---
// ==========================================
const int TOUCH_PIN = 1;     // Touch Sensor OUT (e.g. TTP223)
const int BUZZER_PIN = 2;    // Buzzer I/O
const int LED_PIN = 0;       // WS2812B NeoPixel Data IN
const int NUM_LEDS = 7;      // 7-LED Circular Module

Adafruit_NeoPixel strip(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

// Preferences for saving Wi-Fi credentials in flash memory
Preferences preferences;

// Web server & Captive Portal DNS
WebServer server(80);
DNSServer dnsServer;
const byte DNS_PORT = 53;

// Modes & State (Prefix enum values to avoid ESP32-C3 ROM naming conflicts)
bool inConfigPortalMode = false;
enum ReqState { REQ_IDLE, REQ_PENDING, REQ_ACCEPTED, REQ_REJECTED };
ReqState currentStatus = REQ_IDLE;
unsigned long acceptedTimestamp = 0;

// ==========================================
// --- LED & Buzzer Helper Functions ---
// ==========================================

void setAllLeds(int r, int g, int b) {
  for (int i = 0; i < NUM_LEDS; i++) {
    strip.setPixelColor(i, strip.Color(r, g, b));
  }
  strip.show();
}

// Quick upward frequency sweep simulating a "water drop" / "bloop"
void playWaterDropSound() {
  for (int freq = 500; freq < 1600; freq += 120) {
    tone(BUZZER_PIN, freq, 15);
    delay(15);
  }
}

// Short beep for UI confirmations
void playBeep() {
  tone(BUZZER_PIN, 1200, 80);
  delay(90);
}

// ==========================================
// --- Router Mode Server Routes ---
// ==========================================

void addCorsHeaders() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "*");
}

void handleStatus() {
  addCorsHeaders();
  String statusStr;
  switch (currentStatus) {
    case REQ_PENDING: statusStr = "pending"; break;
    case REQ_ACCEPTED: statusStr = "accepted"; break;
    case REQ_REJECTED: statusStr = "rejected"; break;
    default: statusStr = "idle"; break;
  }
  String json = "{\"room\":\"101\",\"table\":\"T1\",\"service\":\"water\",\"status\":\"" + statusStr + "\"}";
  server.send(200, "application/json", json);
}

void handleAccept() {
  addCorsHeaders();
  if (currentStatus == REQ_PENDING) {
    Serial.println("\n>>> [ROUTER] Manager ACCEPTED Request! <<<");
    currentStatus = REQ_ACCEPTED;
    acceptedTimestamp = millis();

    // Turn LED Green
    setAllLeds(0, 255, 0);
    // Play water drop sound
    playWaterDropSound();

    server.send(200, "application/json", "{\"result\":\"ok\",\"status\":\"accepted\"}");
  } else {
    server.send(200, "application/json", "{\"result\":\"no_pending_request\"}");
  }
}

void handleReject() {
  addCorsHeaders();
  Serial.println("\n>>> [ROUTER] Manager REJECTED Request <<<");
  currentStatus = REQ_REJECTED;
  setAllLeds(0, 0, 0);
  server.send(200, "application/json", "{\"result\":\"ok\",\"status\":\"rejected\"}");
}

// Reset Wi-Fi via web endpoint
void handleResetWifi() {
  preferences.begin("wifi-config", false);
  preferences.clear();
  preferences.end();
  server.send(200, "text/html", "<h2>Wi-Fi credentials cleared! Restarting in Setup Mode...</h2>");
  delay(1500);
  ESP.restart();
}

// Main Manager Web Dashboard
void handleDashboard() {
  String html = "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'>"
    "<title>Tab2Notify Manager</title>"
    "<style>"
    "body{font-family:Arial,sans-serif;background:#121212;color:#fff;text-align:center;padding:24px;}"
    ".card{background:#1e1e1e;border-radius:16px;padding:24px;max-width:380px;margin:auto;box-shadow:0 8px 24px rgba(0,0,0,0.5);}"
    "h1{color:#ff9800;font-size:24px;margin-bottom:4px;}p{color:#aaa;margin-top:0;}"
    ".btn{display:block;width:100%;padding:14px;margin:12px 0;font-size:18px;font-weight:bold;border:none;border-radius:10px;cursor:pointer;}"
    ".btn-accept{background:#2e7d32;color:#fff;}"
    ".btn-reject{background:#d32f2f;color:#fff;}"
    ".btn-reset{background:#333;color:#ff9800;font-size:14px;padding:10px;margin-top:20px;}"
    ".status{font-size:18px;font-weight:bold;padding:12px;border-radius:8px;margin:16px 0;}"
    ".pending{background:#ff9800;color:#000;}"
    ".idle{background:#292929;color:#888;}"
    ".accepted{background:#2e7d32;color:#fff;}"
    "</style></head><body>"
    "<div class='card'>"
    "<h1>Tab2Notify</h1>"
    "<p>Local Wi-Fi Manager</p>"
    "<div id='status-box' class='status idle'>Checking...</div>"
    "<h3>Room 101 &bull; Table T1</h3>"
    "<p>Service: Water Request 💧</p>"
    "<button class='btn btn-accept' onclick=\"fetch('/accept').then(()=>checkStatus())\">ACCEPT REQUEST</button>"
    "<button class='btn btn-reject' onclick=\"fetch('/reject').then(()=>checkStatus())\">REJECT</button>"
    "<form action='/reset-wifi' method='POST' onsubmit=\"return confirm('Reset Wi-Fi credentials?');\">"
    "<button type='submit' class='btn btn-reset'>⚙ Change Wi-Fi Settings</button>"
    "</form>"
    "</div>"
    "<script>"
    "function checkStatus(){"
    "  fetch('/status').then(r=>r.json()).then(d=>{"
    "    let b=document.getElementById('status-box');"
    "    if(d.status==='pending'){b.className='status pending';b.innerText='🔔 PENDING REQUEST!';}"
    "    else if(d.status==='accepted'){b.className='status accepted';b.innerText='✓ REQUEST ACCEPTED';}"
    "    else{b.className='status idle';b.innerText='Waiting for Guest...';}"
    "  });"
    "}"
    "setInterval(checkStatus,1500);checkStatus();"
    "</script></body></html>";

  server.send(200, "text/html", html);
}

// ==========================================
// --- Mobile Wi-Fi Provisioning Portal ---
// ==========================================

void handlePortalRoot() {
  int n = WiFi.scanNetworks();
  String options = "";
  for (int i = 0; i < n; ++i) {
    options += "<option value='" + WiFi.SSID(i) + "'>" + WiFi.SSID(i) + " (" + String(WiFi.RSSI(i)) + " dBm)</option>";
  }

  String html = "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'>"
    "<title>Tab2Notify Wi-Fi Setup</title>"
    "<style>"
    "body{font-family:Arial,sans-serif;background:#121212;color:#fff;text-align:center;padding:24px;}"
    ".card{background:#1e1e1e;border-radius:16px;padding:24px;max-width:380px;margin:auto;box-shadow:0 8px 24px rgba(0,0,0,0.5);}"
    "h1{color:#ff9800;font-size:22px;}p{color:#bbb;font-size:14px;}"
    "select,input{width:100%;padding:12px;margin:8px 0 16px;box-sizing:border-box;background:#2a2a2a;color:#fff;border:1px solid #444;border-radius:8px;font-size:16px;}"
    ".btn{width:100%;padding:14px;font-size:18px;font-weight:bold;background:#ff9800;color:#000;border:none;border-radius:8px;cursor:pointer;}"
    "</style></head><body>"
    "<div class='card'>"
    "<h1>⚙ Tab2Notify Wi-Fi Setup</h1>"
    "<p>Select your hotel/home Wi-Fi router:</p>"
    "<form action='/save' method='POST'>"
    "<label style='float:left;font-size:13px;'>Available Wi-Fi Networks:</label>"
    "<select name='ssid' id='ssid'>" + (n == 0 ? "<option value=''>No networks found</option>" : options) + "</select>"
    "<label style='float:left;font-size:13px;'>Wi-Fi Password:</label>"
    "<input type='password' name='password' placeholder='Enter Wi-Fi Password' required>"
    "<button type='submit' class='btn'>Connect & Save</button>"
    "</form>"
    "</div></body></html>";

  server.send(200, "text/html", html);
}

void handlePortalSave() {
  String newSsid = server.arg("ssid");
  String newPass = server.arg("password");

  if (newSsid.length() > 0) {
    Serial.println("\n[PORTAL] Received Wi-Fi credentials from mobile phone!");
    Serial.print("SSID: "); Serial.println(newSsid);

    preferences.begin("wifi-config", false);
    preferences.putString("ssid", newSsid);
    preferences.putString("password", newPass);
    preferences.end();

    String html = "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'>"
      "<style>body{background:#121212;color:#fff;text-align:center;padding:40px;font-family:Arial;}</style></head><body>"
      "<h2>✓ Wi-Fi Details Saved!</h2>"
      "<p>The ESP32 is now connecting to <b>" + newSsid + "</b>.</p>"
      "<p>Your phone can now switch back to your regular Wi-Fi.</p>"
      "</body></html>";

    server.send(200, "text/html", html);
    delay(2000);
    ESP.restart();
  } else {
    server.send(400, "text/plain", "Missing SSID");
  }
}

// Start Captive Portal Access Point
void startConfigPortal() {
  inConfigPortalMode = true;
  Serial.println("\n=============================================");
  Serial.println("  Starting Mobile Wi-Fi Setup Hotspot");
  Serial.println("  Connect phone to Wi-Fi: [ Tab2Notify-Setup ]");
  Serial.println("  Open browser to: http://192.168.4.1");
  Serial.println("=============================================");

  // Show Blue LEDs indicating Setup Mode
  setAllLeds(0, 0, 255);

  WiFi.mode(WIFI_AP);
  WiFi.softAP("Tab2Notify-Setup");
  delay(500);

  // DNS Server for Captive Portal (redirects any request to 192.168.4.1)
  dnsServer.start(DNS_PORT, "*", WiFi.softAPIP());

  server.on("/", handlePortalRoot);
  server.on("/save", HTTP_POST, handlePortalSave);
  server.onNotFound(handlePortalRoot); // Captive portal redirect
  server.begin();
}

// ==========================================
// --- Setup ---
// ==========================================
void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n=== Tab2Notify ESP32-C3 Booting ===");

  pinMode(TOUCH_PIN, INPUT_PULLDOWN);

  strip.begin();
  strip.show();
  strip.setBrightness(60);
  setAllLeds(0, 0, 0);

  // Check if touch button is held down at boot to force reset Wi-Fi
  if (digitalRead(TOUCH_PIN) == HIGH) {
    Serial.println("[RESET] Touch button held at boot! Resetting Wi-Fi memory...");
    preferences.begin("wifi-config", false);
    preferences.clear();
    preferences.end();
    playBeep();
  }

  // Read saved Wi-Fi from memory
  preferences.begin("wifi-config", true);
  String savedSsid = preferences.getString("ssid", "");
  String savedPass = preferences.getString("password", "");
  preferences.end();

  if (savedSsid.length() > 0) {
    Serial.print("Saved Wi-Fi found: ");
    Serial.println(savedSsid);
    Serial.println("Attempting to connect...");

    WiFi.mode(WIFI_STA);
    WiFi.begin(savedSsid.c_str(), savedPass.c_str());

    // Wait up to 15 seconds to connect
    int timeout = 30;
    while (WiFi.status() != WL_CONNECTED && timeout > 0) {
      delay(500);
      Serial.print(".");
      timeout--;
    }

    if (WiFi.status() == WL_CONNECTED) {
      // Start mDNS service (allows accessing as http://tab2notify.local)
      if (MDNS.begin("tab2notify")) {
        Serial.println("✓ mDNS responder started: http://tab2notify.local");
      }

      Serial.println("\n-------------------------------------------");
      Serial.println("✓ Connected to Router successfully!");
      Serial.print("✓ ESP32 IP Address: http://");
      Serial.println(WiFi.localIP());
      Serial.println("-------------------------------------------");

      // Setup Router Mode Web Server
      server.on("/", HTTP_GET, handleDashboard);
      server.on("/status", HTTP_GET, handleStatus);
      server.on("/accept", HTTP_GET, handleAccept);
      server.on("/accept", HTTP_POST, handleAccept);
      server.on("/reject", HTTP_GET, handleReject);
      server.on("/reject", HTTP_POST, handleReject);
      server.on("/reset-wifi", HTTP_POST, handleResetWifi);

      server.begin();
      setAllLeds(0, 0, 0); // Ready
      return;
    } else {
      Serial.println("\n[ERROR] Failed to connect to saved Wi-Fi. Launching Setup Portal...");
    }
  } else {
    Serial.println("No saved Wi-Fi found. Launching Setup Portal...");
  }

  // If no Wi-Fi saved or connection failed -> Start Mobile Setup Hotspot
  startConfigPortal();
}

// ==========================================
// --- Main Loop ---
// ==========================================
void loop() {
  if (inConfigPortalMode) {
    dnsServer.processNextRequest();
    server.handleClient();
    return;
  }

  // --- Normal Router Operation Mode ---
  server.handleClient();

  // 1. Check physical Touch button press
  int touchState = digitalRead(TOUCH_PIN);

  if (touchState == HIGH && currentStatus != REQ_PENDING) {
    Serial.println("\n[TOUCH DETECTED] Guest requested service!");
    currentStatus = REQ_PENDING;

    // Show RED on LEDs
    setAllLeds(255, 0, 0);
    // Play water drop sound
    playWaterDropSound();

    delay(1000); // Debounce delay
  }

  // 2. If status was ACCEPTED, keep Green light on for 5 seconds then reset to IDLE
  if (currentStatus == REQ_ACCEPTED) {
    if (millis() - acceptedTimestamp > 5000) {
      Serial.println("[TIMER] Resetting LEDs back to IDLE");
      setAllLeds(0, 0, 0);
      currentStatus = REQ_IDLE;
    }
  }
}
