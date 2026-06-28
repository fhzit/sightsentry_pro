# SightSentry Pro Flutter Client

Flutter rewrite of the Android client for SightSentry Pro.

## Features

- Android 9+ support (`minSdkVersion 28`)
- ESP32C6 node connection over USB OTG serial at 115200 baud
- BLE UART connection using Nordic UART compatible UUIDs
- Parses firmware frames: `nodeId|mac|rssi|type|name`, including `WIFI_PROBE`, `WIFI_AP`, and `BLE`
- WiFiman-inspired dark device list and detail pages
- Device detail page with MAC, vendor, signal strength, Bluetooth/WiFi type, and estimated distance
- Built-in app icon: dark radar rings, green scan beam, pink target dot

## Vendor Recognition

Vendor recognition uses the first 3 bytes of the MAC address (OUI prefix). The built-in table covers common Apple, Huawei, Samsung, Cisco, Intel, CH340/ESP32-related test devices, and can be extended in `lib/models.dart` via `ouiVendors`.

## Distance Estimation

Distance is estimated from RSSI with a log-distance path loss formula:

```text
distance = 10 ^ ((rssiAtOneMeter - rssi) / (10 * pathLossExponent))
```

Defaults:

- `rssiAtOneMeter = -59 dBm`
- `pathLossExponent = 2.5`
- Output is clamped to `0.1m..100m`

This is an approximation; walls, antenna orientation, phone model, and BLE/WiFi transmit power can affect accuracy.

## Build

This workspace installs the Android toolchain under the user home directory:

```bash
export JAVA_HOME=/opt/data/home/devtools/jdk-17
export ANDROID_HOME=/opt/data/home/android-sdk
export ANDROID_SDK_ROOT=/opt/data/home/android-sdk
export PATH=/opt/data/home/devtools/flutter/bin:/opt/data/home/devtools/jdk-17/bin:/opt/data/home/android-sdk/cmdline-tools/latest/bin:/opt/data/home/android-sdk/platform-tools:$PATH

flutter pub get
flutter build apk --release
```
