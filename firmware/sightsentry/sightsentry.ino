#include <esp_wifi.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <cstring>

#define NODE_ID 1
#define SCAN_INTERVAL_MS 1000
#define DEVICE_TIMEOUT_MS 10000
#define WIFI_HOP_INTERVAL_MS 120
#define WIFI_CHANNEL_MIN 1
#define WIFI_CHANNEL_MAX 13
#define MAX_DEVICE_COUNT 128
#define MODE_BUTTON_PIN 0
#define BUTTON_DEBOUNCE_MS 50

#define SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

enum DeviceType {
  DEV_WIFI,
  DEV_BLE,
};

enum OutputMode {
  OUTPUT_SERIAL,
  OUTPUT_BLE,
};

struct DeviceInfo {
  char mac[18];
  int rssi;
  DeviceType type;
  char name[32];
  unsigned long lastSeen;
};

struct DeviceEvent {
  uint8_t mac[6];
  int rssi;
  DeviceType type;
  char name[32];
};

DeviceInfo devices[MAX_DEVICE_COUNT];
size_t deviceCount = 0;
QueueHandle_t deviceEventQueue = nullptr;
SemaphoreHandle_t devicesMutex = nullptr;
BLEServer* pServer = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
volatile bool bleClientConnected = false;
volatile OutputMode outputMode = OUTPUT_SERIAL;

void bleScanLoop(void* param);
void wifiChannelHopLoop(void* param);
void processDeviceEvents();
void addOrUpdateDevice(const DeviceEvent& event);
void sendData();
void sendLine(const char* line, size_t length);
void filterDevices();
void startBLEServer();
void macToString(const uint8_t mac[6], char out[18]);
void sanitizeOutput(char* value);
bool parseWifiMgmtSourceMac(const uint8_t* payload, uint8_t out[6]);
void handleModeButton();

class MyAdvertisedDeviceCallbacks : public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice advertisedDevice) override {
    DeviceEvent event = {};
    BLEAddress address = advertisedDevice.getAddress();
    uint8_t* mac = address.getNative();
    if (!mac) {
      return;
    }
    memcpy(event.mac, mac, 6);
    event.rssi = advertisedDevice.getRSSI();
    event.type = DEV_BLE;
    String name = advertisedDevice.getName();
    if (name.length() > 0) {
      strncpy(event.name, name.c_str(), sizeof(event.name) - 1);
      event.name[sizeof(event.name) - 1] = '\0';
      sanitizeOutput(event.name);
    } else {
      event.name[0] = '\0';
    }
    if (deviceEventQueue) {
      xQueueSend(deviceEventQueue, &event, 0);
    }
  }
};

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    // mark client connected; continue scanning and keep serial output as well
    bleClientConnected = true;
    Serial.println("BLE client connected");
  }
  void onDisconnect(BLEServer* pServer) override {
    bleClientConnected = false;
    Serial.println("BLE client disconnected");
  }
};

void setup() {
  Serial.begin(115200);
  delay(1000);

  pinMode(MODE_BUTTON_PIN, INPUT_PULLUP);

  devicesMutex = xSemaphoreCreateMutex();
  deviceEventQueue = xQueueCreate(128, sizeof(DeviceEvent));

  esp_err_t err = esp_event_loop_create_default();
  if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
    Serial.printf("WiFi event loop create failed: %d\n", err);
  }

  wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
  err = esp_wifi_init(&cfg);
  if (err != ESP_OK) {
    Serial.printf("WiFi init failed: %d\n", err);
  }
  esp_wifi_set_storage(WIFI_STORAGE_RAM);
  esp_wifi_set_mode(WIFI_MODE_STA);
  esp_wifi_disconnect();
  err = esp_wifi_start();
  if (err != ESP_OK) {
    Serial.printf("WiFi start failed: %d\n", err);
  }

  wifi_promiscuous_filter_t filter = {};
  filter.filter_mask = WIFI_PROMIS_FILTER_MASK_MGMT;
  esp_wifi_set_promiscuous_filter(&filter);
  esp_wifi_set_promiscuous_rx_cb([](void* buf, wifi_promiscuous_pkt_type_t type) {
    if (type != WIFI_PKT_MGMT) {
      return;
    }

    wifi_promiscuous_pkt_t* pkt = reinterpret_cast<wifi_promiscuous_pkt_t*>(buf);
    const wifi_pkt_rx_ctrl_t& ctrl = pkt->rx_ctrl;
    const uint8_t* payload = pkt->payload;

    DeviceEvent event = {};
    if (!parseWifiMgmtSourceMac(payload, event.mac)) {
      return;
    }

    event.rssi = ctrl.rssi;
    event.type = DEV_WIFI;
    event.name[0] = '\0';
    if (deviceEventQueue) {
      BaseType_t xHigherPriorityTaskWoken = pdFALSE;
      xQueueSendFromISR(deviceEventQueue, &event, &xHigherPriorityTaskWoken);
      portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
    }
  });

  esp_wifi_set_promiscuous(true);
  esp_wifi_set_channel(WIFI_CHANNEL_MIN, WIFI_SECOND_CHAN_NONE);

  BLEDevice::init("SightSentry");
  startBLEServer();

  BLEScan* pBLEScan = BLEDevice::getScan();
  pBLEScan->setAdvertisedDeviceCallbacks(new MyAdvertisedDeviceCallbacks());
  pBLEScan->setActiveScan(true);
  pBLEScan->setInterval(100);
  pBLEScan->setWindow(99);

  xTaskCreate(bleScanLoop, "BLEScan", 4096, nullptr, 1, nullptr);
  xTaskCreate(wifiChannelHopLoop, "WiFiHop", 2048, nullptr, 1, nullptr);
}

void loop() {
  static unsigned long lastSend = 0;

  handleModeButton();
  processDeviceEvents();

  if (millis() - lastSend >= SCAN_INTERVAL_MS) {
    filterDevices();
    sendData();
    lastSend = millis();
  }

  delay(10);
}

void startBLEServer() {
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharacteristic->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
}

void bleScanLoop(void* param) {
  BLEScan* pBLEScan = BLEDevice::getScan();
  while (true) {
    pBLEScan->start(1, false);
    pBLEScan->clearResults();
    delay(100);
  }
}

void wifiChannelHopLoop(void* param) {
  int channel = WIFI_CHANNEL_MIN;
  while (true) {
    esp_wifi_set_channel(channel, WIFI_SECOND_CHAN_NONE);
    channel++;
    if (channel > WIFI_CHANNEL_MAX) {
      channel = WIFI_CHANNEL_MIN;
    }
    delay(WIFI_HOP_INTERVAL_MS);
  }
}

void handleModeButton() {
  static int lastState = HIGH;
  static unsigned long lastDebounce = 0;
  static bool pressed = false;

  int state = digitalRead(MODE_BUTTON_PIN);
  if (state != lastState) {
    lastDebounce = millis();
  }

  if ((millis() - lastDebounce) > BUTTON_DEBOUNCE_MS) {
    if (state == LOW && !pressed) {
      pressed = true;
      outputMode = (outputMode == OUTPUT_SERIAL) ? OUTPUT_BLE : OUTPUT_SERIAL;
    } else if (state == HIGH) {
      pressed = false;
    }
  }

  lastState = state;
}

void processDeviceEvents() {
  if (!deviceEventQueue) {
    return;
  }

  DeviceEvent event;
  while (xQueueReceive(deviceEventQueue, &event, 0) == pdTRUE) {
    addOrUpdateDevice(event);
  }
}

void addOrUpdateDevice(const DeviceEvent& event) {
  if (!devicesMutex) {
    return;
  }

  if (xSemaphoreTake(devicesMutex, portMAX_DELAY) != pdTRUE) {
    return;
  }

  char macStr[18];
  macToString(event.mac, macStr);

  for (size_t i = 0; i < deviceCount; ++i) {
    if (devices[i].type == event.type && strcmp(devices[i].mac, macStr) == 0) {
      devices[i].rssi = (devices[i].rssi * 7 + event.rssi * 3) / 10;
      devices[i].lastSeen = millis();
      if (event.name[0] != '\0') {
        strncpy(devices[i].name, event.name, sizeof(devices[i].name) - 1);
        devices[i].name[sizeof(devices[i].name) - 1] = '\0';
      }
      xSemaphoreGive(devicesMutex);
      return;
    }
  }

  DeviceInfo newDev = {};
  strncpy(newDev.mac, macStr, sizeof(newDev.mac));
  newDev.mac[sizeof(newDev.mac) - 1] = '\0';
  newDev.rssi = event.rssi;
  newDev.type = event.type;
  if (event.name[0] != '\0') {
    strncpy(newDev.name, event.name, sizeof(newDev.name) - 1);
    newDev.name[sizeof(newDev.name) - 1] = '\0';
  } else {
    newDev.name[0] = '\0';
  }
  newDev.lastSeen = millis();

  if (deviceCount >= MAX_DEVICE_COUNT) {
    size_t oldestIndex = 0;
    unsigned long oldestTime = devices[0].lastSeen;
    for (size_t i = 1; i < deviceCount; ++i) {
      if (devices[i].lastSeen < oldestTime) {
        oldestTime = devices[i].lastSeen;
        oldestIndex = i;
      }
    }
    devices[oldestIndex] = newDev;
  } else {
    devices[deviceCount++] = newDev;
  }

  xSemaphoreGive(devicesMutex);
}

bool parseWifiMgmtSourceMac(const uint8_t* payload, uint8_t out[6]) {
  if (!payload) {
    return false;
  }

  uint16_t frameCtrl = payload[0] | (payload[1] << 8);
  uint8_t type = (frameCtrl >> 2) & 0x03;
  if (type != 0) {
    return false;
  }

  memcpy(out, payload + 10, 6);
  return true;
}

void sanitizeOutput(char* value) {
  for (char* p = value; *p; ++p) {
    if (*p == '|' || *p == '\n' || *p == '\r') {
      *p = ' ';
    }
  }
}

void macToString(const uint8_t mac[6], char out[18]) {
  snprintf(out, 18, "%02X:%02X:%02X:%02X:%02X:%02X",
    mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

void sendData() {
  if (!devicesMutex) {
    return;
  }

  static DeviceInfo snapshot[MAX_DEVICE_COUNT];
  size_t snapshotCount = 0;

  if (xSemaphoreTake(devicesMutex, portMAX_DELAY) != pdTRUE) {
    return;
  }

  snapshotCount = deviceCount;
  if (snapshotCount > MAX_DEVICE_COUNT) {
    snapshotCount = MAX_DEVICE_COUNT;
  }
  for (size_t i = 0; i < snapshotCount; ++i) {
    snapshot[i] = devices[i];
  }

  xSemaphoreGive(devicesMutex);

  char line[128];
  for (size_t i = 0; i < snapshotCount; ++i) {
    const DeviceInfo& dev = snapshot[i];
    const char* typeStr = (dev.type == DEV_WIFI) ? "WIFI" : "BLE";
    int len = snprintf(line, sizeof(line), "%u|%s|%d|%s|%s\n",
      NODE_ID, dev.mac, dev.rssi, typeStr, dev.name);
    if (len > 0 && len < (int)sizeof(line)) {
      sendLine(line, (size_t)len);
    }
  }
}

void sendLine(const char* line, size_t length) {
  // Always write to serial for debugging and compatibility
  Serial.write(line, length);

  // Also send via BLE notify when a client is connected
  if (!(bleClientConnected && pCharacteristic)) {
    return;
  }

  const size_t chunkSize = 20; // safe default MTU chunk
  size_t sent = 0;
  while (sent < length) {
    size_t toSend = (length - sent > chunkSize) ? chunkSize : (length - sent);
    pCharacteristic->setValue((uint8_t*)(line + sent), toSend);
    pCharacteristic->notify();
    sent += toSend;
    // short delay to give BLE stack time to transmit
    delay(5);
  }
}

void filterDevices() {
  unsigned long now = millis();
  if (!devicesMutex) {
    return;
  }

  if (xSemaphoreTake(devicesMutex, portMAX_DELAY) != pdTRUE) {
    return;
  }

  size_t writeIndex = 0;
  for (size_t i = 0; i < deviceCount; ++i) {
    if (now - devices[i].lastSeen <= DEVICE_TIMEOUT_MS) {
      if (writeIndex != i) {
        devices[writeIndex] = devices[i];
      }
      ++writeIndex;
    }
  }
  deviceCount = writeIndex;

  xSemaphoreGive(devicesMutex);
}
