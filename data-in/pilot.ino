#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <Adafruit_MCP23X17.h>
#include <WEMOS_SHT3X.h>
#include <SDI12.h>
#include <time.h>
#include <esp_task_wdt.h>
#include <SPIFFS.h>
#include <mbedtls/pk.h>
#include <mbedtls/entropy.h>
#include <mbedtls/ctr_drbg.h>

// Watchdog configurations
#define WDT_TIMEOUT 30
#define TASK_RESET_PERIOD 15000

// Storage configurations
#define MAX_RETRY_COUNT 5
#define MAX_STORED_READINGS 100
#define STORAGE_FILE "/failed_readings.json"
#define IDENTITY_FILE "/identity.pem"

// Pin definitions
#define PH_PIN 36
#define DATA_PIN 12
#define I2C_SDA 21
#define I2C_SCL 22

// Network configurations
const char* WIFI_SSID = "Growa";
const char* WIFI_PASSWORD = "******!";
const char* ICP_HOST = "https://icp0.io";
const char* CANISTER_ID = "ljyqf-uqaaa-aaaag-atzmq-cai";
const char* NTP_SERVER = "pool.ntp.org";
const long GMT_OFFSET_SEC = 3 * 3600;  // Qatar timezone (UTC+3)

// Timer intervals
const unsigned long READ_INTERVAL = 300000;  // 5 minutes
unsigned long lastReadTime = 0;
unsigned long lastWatchdogReset = 0;

// Initialize hardware
SHT3X sht30(0x44);
SDI12 mySDI12(DATA_PIN);
Adafruit_MCP23X17 mcp;

// Struct for sensor readings
struct SensorReading {
    String entity_id;
    float value;
    unsigned long timestamp;
};

// Queue for failed readings
std::vector<SensorReading> failedReadings;

// ICP Identity Management Class
class ICPIdentity {
private:
    mbedtls_pk_context pk_ctx;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context ctr_drbg;
    String principal;
    
public:
    ICPIdentity() {
        mbedtls_pk_init(&pk_ctx);
        mbedtls_entropy_init(&entropy);
        mbedtls_ctr_drbg_init(&ctr_drbg);
    }
    
    ~ICPIdentity() {
        mbedtls_pk_free(&pk_ctx);
        mbedtls_entropy_free(&entropy);
        mbedtls_ctr_drbg_free(&ctr_drbg);
    }
    
    bool init() {
        if (!SPIFFS.exists(IDENTITY_FILE)) {
            return generateNewIdentity();
        }
        return loadExistingIdentity();
    }
    
    String sign(const String &message) {
        unsigned char hash[32];
        unsigned char signature[64];
        size_t sig_len;
        
        mbedtls_sha256((const unsigned char*)message.c_str(), message.length(), hash, 0);
        
        int ret = mbedtls_pk_sign(&pk_ctx, MBEDTLS_MD_SHA256, hash, sizeof(hash),
                                 signature, &sig_len,
                                 mbedtls_ctr_drbg_random, &ctr_drbg);
        
        if (ret != 0) {
            Serial.printf("Signing failed: %d\n", ret);
            return "";
        }
        
        return base64_encode(signature, sig_len);
    }
    
    String getPrincipal() {
        if (principal.length() == 0) {
            unsigned char pubkey[32];
            size_t pubkey_len;
            
            mbedtls_pk_write_pubkey_der(&pk_ctx, pubkey, sizeof(pubkey));
            principal = base64_encode(pubkey, sizeof(pubkey));
        }
        return principal;
    }

private:
    bool generateNewIdentity() {
        int ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy, NULL, 0);
        if (ret != 0) {
            Serial.printf("RNG seed failed: %d\n", ret);
            return false;
        }
        
        ret = mbedtls_pk_setup(&pk_ctx, mbedtls_pk_info_from_type(MBEDTLS_PK_ED25519));
        if (ret != 0) {
            Serial.printf("Key setup failed: %d\n", ret);
            return false;
        }
        
        ret = mbedtls_pk_generate_key(&pk_ctx, &ctr_drbg);
        if (ret != 0) {
            Serial.printf("Key generation failed: %d\n", ret);
            return false;
        }
        
        return saveIdentity();
    }
    
    bool loadExistingIdentity() {
        File file = SPIFFS.open(IDENTITY_FILE, "r");
        if (!file) return false;
        
        String pem = file.readString();
        file.close();
        
        int ret = mbedtls_pk_parse_key(&pk_ctx, 
                                     (const unsigned char*)pem.c_str(),
                                     pem.length() + 1,
                                     NULL, 0,
                                     mbedtls_ctr_drbg_random,
                                     &ctr_drbg);
        
        return ret == 0;
    }
    
    bool saveIdentity() {
        unsigned char buf[16384];
        int ret = mbedtls_pk_write_key_pem(&pk_ctx, buf, sizeof(buf));
        if (ret != 0) return false;
        
        File file = SPIFFS.open(IDENTITY_FILE, "w");
        if (!file) return false;
        
        file.write(buf, strlen((char*)buf));
        file.close();
        
        return true;
    }
    
    static String base64_encode(const unsigned char* input, size_t length) {
        const char base64_chars[] = 
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        
        String encoded;
        int i = 0;
        int j = 0;
        unsigned char array_3[3];
        unsigned char array_4[4];
        
        while (length--) {
            array_3[i++] = *(input++);
            if (i == 3) {
                array_4[0] = (array_3[0] & 0xfc) >> 2;
                array_4[1] = ((array_3[0] & 0x03) << 4) + ((array_3[1] & 0xf0) >> 4);
                array_4[2] = ((array_3[1] & 0x0f) << 2) + ((array_3[2] & 0xc0) >> 6);
                array_4[3] = array_3[2] & 0x3f;
                
                for(i = 0; i < 4; i++)
                    encoded += base64_chars[array_4[i]];
                i = 0;
            }
        }
        
        if (i) {
            for(j = i; j < 3; j++)
                array_3[j] = '\0';
            
            array_4[0] = (array_3[0] & 0xfc) >> 2;
            array_4[1] = ((array_3[0] & 0x03) << 4) + ((array_3[1] & 0xf0) >> 4);
            array_4[2] = ((array_3[1] & 0x0f) << 2) + ((array_3[2] & 0xc0) >> 6);
            
            for (j = 0; j < i + 1; j++)
                encoded += base64_chars[array_4[j]];
            
            while(i++ < 3)
                encoded += '=';
        }
        
        return encoded;
    }
};

// Global identity instance
ICPIdentity identity;

// Storage management functions
bool initStorage() {
    if (!SPIFFS.begin(true)) {
        Serial.println("SPIFFS initialization failed");
        return false;
    }
    Serial.println("SPIFFS initialized");
    return true;
}

void saveFailedReadings() {
    File file = SPIFFS.open(STORAGE_FILE, FILE_WRITE);
    if (!file) return;

    DynamicJsonDocument doc(16384);
    JsonArray array = doc.createNestedArray("readings");

    for (const auto& reading : failedReadings) {
        JsonObject obj = array.createNestedObject();
        obj["entity_id"] = reading.entity_id;
        obj["value"] = reading.value;
        obj["timestamp"] = reading.timestamp;
    }

    serializeJson(doc, file);
    file.close();
}

void loadFailedReadings() {
    if (!SPIFFS.exists(STORAGE_FILE)) return;

    File file = SPIFFS.open(STORAGE_FILE, FILE_READ);
    if (!file) return;

    DynamicJsonDocument doc(16384);
    DeserializationError error = deserializeJson(doc, file);
    file.close();

    if (error) return;

    failedReadings.clear();
    JsonArray array = doc["readings"];
    for (JsonObject obj : array) {
        SensorReading reading;
        reading.entity_id = obj["entity_id"].as<String>();
        reading.value = obj["value"].as<float>();
        reading.timestamp = obj["timestamp"].as<unsigned long>();
        failedReadings.push_back(reading);
    }
}

// Sensor reading functions
bool readES2Sensor(float &conductivity, float &temperature) {
    mySDI12.begin();
    delay(500);
    
    String command = "0M!";
    mySDI12.sendCommand(command);
    delay(1000);
    
    command = "0D0!";
    mySDI12.sendCommand(command);
    
    String sdiResponse = mySDI12.readStringUntil('\n');
    mySDI12.end();
    
    if (sdiResponse.length() > 0) {
        int firstPlus = sdiResponse.indexOf('+', 1);
        int secondPlus = sdiResponse.indexOf('+', firstPlus + 1);
        
        if (firstPlus > 0 && secondPlus > 0) {
            conductivity = sdiResponse.substring(firstPlus, secondPlus).toFloat();
            temperature = sdiResponse.substring(secondPlus).toFloat();
            return true;
        }
    }
    
    return false;
}

float readPH(float water_temp) {
    const int SAMPLES = 10;
    float voltage = 0;
    
    for(int i = 0; i < SAMPLES; i++) {
        voltage += analogRead(PH_PIN) * (10.0 / 4095.0);
        delay(10);
    }
    voltage /= SAMPLES;
    
    float ph = 7.0 + ((voltage - 2.5) * (4.0 - 7.0)) / (3.1 - 2.5);
    return ph;
}

// Communication functions
String encodeCandidArguments(const char* entity_id, float value) {
    DynamicJsonDocument doc(256);
    JsonArray args = doc.createNestedArray("args");
    
    JsonObject textArg = args.createNestedObject();
    textArg["type"] = "text";
    textArg["value"] = entity_id;
    
    JsonObject floatArg = args.createNestedObject();
    floatArg["type"] = "float64";
    floatArg["value"] = value;
    
    String output;
    serializeJson(doc, output);
    return output;
}

bool sendToCanister(const char* entity_id, float value) {
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("WiFi not connected");
        return false;
    }

    HTTPClient http;
    String url = String(ICP_HOST) + "/api/v2/canister/" + CANISTER_ID + "/call";
    
    // Prepare and sign payload
    String payload = encodeCandidArguments(entity_id, value);
    String signature = identity.sign(payload);
    
    if (signature.length() == 0) {
        Serial.println("Failed to sign payload");
        return false;
    }
    
    // Add identity and signature
    DynamicJsonDocument doc(1024);
    deserializeJson(doc, payload);
    doc["sender"] = identity.getPrincipal();
    doc["signature"] = signature;
    
    String finalPayload;
    serializeJson(doc, finalPayload);
    
    http.begin(url);
    http.addHeader("Content-Type", "application/json");
    
    int httpCode = http.POST(finalPayload);
    bool success = (httpCode == 200 || httpCode == 202);
    
    if (success) {
        Serial.printf("Sent %s: %.2f to canister\n", entity_id, value);
    } else {
        Serial.printf("Failed to send data: %d\n", httpCode);
        
        if (failedReadings.size() < MAX_STORED_READINGS) {
            SensorReading reading;
            reading.entity_id = String(entity_id);
            reading.value = value;
            reading.timestamp = millis();
            failedReadings.push_back(reading);
            saveFailedReadings();
        }
    }
    
    http.end();
    return success;
}

void retryFailedReadings() {
    if (failedReadings.empty()) return;

    Serial.println("Retrying failed readings...");
    auto it = failedReadings.begin();
    while (it != failedReadings.end()) {
        if (sendToCanister(it->entity_id.c_str(), it->value)) {
            it = failedReadings.erase(it);
        } else {
            ++it;
        }
    }

    if (failedReadings.empty()) {
        SPIFFS.remove(STORAGE_FILE);
    } else {
        saveFailedReadings();
    }
}

void readAndSendSensorData() {
    float air_temp = 0;
    float humidity = 0;
    float water_temp = 0;
    float ec = 0;
    float ph = 0;
    
    // Read SHT30
    if (sht30.get()) {
        air_temp = sht30.cTemp;
        humidity = sht30.humidity;
    } else {
        Serial.println("Error reading SHT30");
        return;
    }
    
    // Read ES2
    if (!readES2Sensor(ec, water_temp)) {
        Serial.println("Error reading ES2");
        return;
    }
    
    // Read pH
    ph = readPH(water_temp);
    
    // Send all readings
    sendToCanister("21", ph);
    sendToCanister("22", ec);
    sendToCanister("23", water_temp);
    sendToCanister("24", air_temp);
    sendToCanister("25", humidity);
    
    // Print readings to Serial
    Serial.println("\n=== Sensor Readings ===");
    Serial.printf("pH: %.2f\n", ph);
    Serial.printf("EC: %.2f\n", ec);
    Serial.printf("Water Temp: %.2f°C\n", water_temp);
    Serial.printf("Air Temp: %.2f°C\n", air_temp);
    Serial.printf("Humidity: %.2f%%\n", humidity);
    Serial.println("=====================\n");
}

// Safety check for MCP23017
bool checkMCP() {
    Wire.beginTransmission(0x20);
    byte error = Wire.endTransmission();
    return error == 0;
}

void setup() {
    Serial.begin(115200);
    Serial.println("\nStarting Hydroponic System");
    
    // Initialize watchdog
    esp_task_wdt_init(WDT_TIMEOUT, true);
    esp_task_wdt_add(NULL);
    Serial.println("Watchdog initialized");
    
    // Initialize storage
    if (!initStorage()) {
        Serial.println("Storage initialization failed - Restarting");
        ESP.restart();
    }
    
    // Initialize identity
    if (!identity.init()) {
        Serial.println("Identity initialization failed - Restarting");
        ESP.restart();
    }
    
    Serial.println("Identity initialized");
    Serial.print("Principal: ");
    Serial.println(identity.getPrincipal());
    
    // Load any stored readings
    loadFailedReadings();
    Serial.printf("Loaded %d stored readings\n", failedReadings.size());
    
    // Initialize I2C
    Wire.begin(I2C_SDA, I2C_SCL);
    if (!checkMCP()) {
        Serial.println("MCP23017 not found - Restarting");
        ESP.restart();
    }
    
    if (!mcp.begin_I2C()) {
        Serial.println("MCP23017 initialization failed - Restarting");
        ESP.restart();
    }
    Serial.println("MCP23017 initialized");
    
    // Initialize WiFi
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    
    Serial.print("Connecting to WiFi");
    int wifiAttempts = 0;
    while (WiFi.status() != WL_CONNECTED && wifiAttempts < 20) {
        delay(500);
        Serial.print(".");
        wifiAttempts++;
    }
    Serial.println();
    
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("WiFi connection failed - Restarting");
        ESP.restart();
    }
    
    Serial.print("WiFi connected - IP: ");
    Serial.println(WiFi.localIP());
    
    // Initialize time
    configTime(GMT_OFFSET_SEC, 0, NTP_SERVER);
    
    // Configure ADC for pH sensor
    analogSetPinAttenuation(PH_PIN, ADC_11db);
    
    // Initialize SDI-12
    mySDI12.begin();
    
    Serial.println("System initialization complete!");
}

void checkWiFiConnection() {
    static unsigned long lastWiFiCheck = 0;
    const unsigned long WIFI_CHECK_INTERVAL = 30000; // 30 seconds
    
    if (millis() - lastWiFiCheck >= WIFI_CHECK_INTERVAL) {
        lastWiFiCheck = millis();
        
        if (WiFi.status() != WL_CONNECTED) {
            Serial.println("WiFi connection lost - Attempting reconnect");
            WiFi.disconnect();
            delay(1000);
            WiFi.reconnect();
            
            int attempts = 0;
            while (WiFi.status() != WL_CONNECTED && attempts < 10) {
                delay(1000);
                attempts++;
            }
            
            if (WiFi.status() != WL_CONNECTED) {
                Serial.println("WiFi reconnection failed - Restarting");
                ESP.restart();
            }
            
            Serial.println("WiFi reconnected");
        }
    }
}

void loop() {
    unsigned long currentTime = millis();
    
    // Reset watchdog
    if (currentTime - lastWatchdogReset >= TASK_RESET_PERIOD) {
        esp_task_wdt_reset();
        lastWatchdogReset = currentTime;
    }
    
    // Check WiFi connection
    checkWiFiConnection();
    
    // Regular sensor readings
    if (currentTime - lastReadTime >= READ_INTERVAL) {
        lastReadTime = currentTime;
        
        // Check MCP23017 before reading sensors
        if (!checkMCP()) {
            Serial.println("MCP23017 connection lost - Restarting");
            ESP.restart();
        }
        
        readAndSendSensorData();
        
        // Try to send any failed readings
        retryFailedReadings();
    }
    
    // Small delay to prevent watchdog issues
    delay(100);
}
