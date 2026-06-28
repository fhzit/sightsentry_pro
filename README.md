# SightSentry Pro - WiFi/蓝牙信号嗅探定位系统

## 项目简介

SightSentry Pro 是一个基于 ESP32C6 的 WiFi 和蓝牙信号嗅探定位系统，支持多节点协同工作。当前 Android 客户端采用 **Flutter** 构建，最低支持 **Android 9 (API 28)**。

## 项目结构

```
sightsentry-pro/
├── flutter_client/         # Flutter Android 客户端
│   ├── lib/                # Dart 应用源码
│   ├── android/            # Android 工程配置
│   └── pubspec.yaml        # Flutter 依赖配置
├── firmware/               # ESP32C6 固件源码
│   └── sightsentry/        # PlatformIO/Arduino 固件工程
├── src/                    # 保留的旧前端源码
└── .github/workflows/      # GitHub Actions APK 构建流程
```

## 开发环境

### Android 客户端
- Flutter stable
- Dart 3.4+
- Java 17
- Android SDK
- **最低支持 Android 9 (API 28)**

### 固件
- ESP32C6 开发板
- PlatformIO 或 Arduino IDE
- USB 数据线（支持 OTG）

## 运行开发版本

```bash
cd flutter_client
flutter pub get
flutter run
```

## 构建发布版本

```bash
cd flutter_client
flutter pub get
flutter analyze
flutter build apk --release
```

APK 输出位置：

```bash
flutter_client/build/app/outputs/flutter-apk/app-release.apk
```

GitHub Actions 会在推送到 `main` 后自动运行 `Build Android APK`，并上传 `sightsentry-pro-release-apk` 构建产物。

## 功能特性

### 固件端 (ESP32C6)
- 并行 WiFi 2.4G 混杂模式嗅探
- BLE 蓝牙持续扫描
- USB 虚拟串口数据输出
- BLE UART 广播服务
- 设备去重和过期清理

### Android 端
- Flutter 原生 Android 客户端
- USB OTG 串口连接
- Bluetooth LE 连接
- 实时设备列表展示
- OUI 厂商库自动识别
- RSSI 距离估算
- 深色移动端界面

## 数据格式

固件基础输出保持前 5 个字段不变，客户端兼容旧版固件：

```
节点编号|MAC地址|RSSI|信号类型|名称
```

新版固件会在末尾追加 BLE 广播元数据字段，WiFi AP 帧会把 SSID 放在 `名称` 字段：

```
节点编号|MAC地址|RSSI|信号类型|名称|ManufacturerDataHex|ServiceUUIDs|TxPower|Appearance
```

WiFi 设备来自 802.11 管理帧。新版固件会输出 `WIFI_PROBE`（客户端 Probe Request）和 `WIFI_AP`（AP Beacon / Probe Response）；新版客户端同时兼容旧固件的 `WIFI` 和新版固件的 `WIFI_PROBE`/`WIFI_AP`。客户端设备使用 Probe Request 的源 MAC 做 IEEE OUI 厂商识别；AP/路由器使用 BSSID 做厂商识别，并把 SSID 展示为名称。BLE 设备优先使用广播名称，其次根据 Manufacturer Data 的 Bluetooth Company Identifier 推断厂商，最后回退到 MAC OUI。

WiFi 探测和 BLE 探测在客户端内按 `信号类型 + MAC` 分开建档、分开展示，不会把 WiFi Probe、WiFi AP 与 BLE 广播融合成同一个设备。

RSSI 距离为估算值，客户端会显示“很近 / 近 / 中等 / 远”的距离等级，并在详情页区分最近 RSSI 与平滑 RSSI。

示例：

```
1|AA:BB:CC:DD:EE:FF|-65|WIFI_PROBE|
1|AA:BB:CC:11:22:33|-54|WIFI_AP|Campus-WiFi
1|11:22:33:44:55:66|-72|BLE|AirPods|4C001005...|180F|-8|
```

## Android 权限

应用需要以下权限：
- `BLUETOOTH` / `BLUETOOTH_ADMIN` - Android 11 及以下蓝牙通信
- `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` - Android 12+ 蓝牙扫描与连接
- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` - BLE 扫描兼容权限
- `NEARBY_WIFI_DEVICES` - Android 13+ 附近设备权限
- `INTERNET` - 网络访问

## 注意事项

1. WiFi/BLE 嗅探功能在部分地区需要合规授权。
2. Android 9.0+ 已支持当前 Flutter 客户端。
3. 多节点使用时确保每个节点有唯一的 `NODE_ID`。
4. 首次安装需要开启“允许安装未知来源应用”。

## 许可证

MIT License
