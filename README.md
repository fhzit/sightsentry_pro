# SightSentry Pro - WiFi/蓝牙信号嗅探定位系统

## 项目简介

SightSentry Pro 是一个基于 ESP32C6 的 WiFi 和蓝牙信号嗅探定位系统，支持多节点协同工作。采用 Tauri 框架构建，可打包成 **Android APK** 移动端应用。

## 项目结构

```
sightsentry-pro/
├── src/                    # Tauri 前端源码
│   ├── index.html         # 主页面
│   ├── styles.css         # 样式表
│   └── app.js             # 核心逻辑
├── src-tauri/              # Tauri 后端源码
│   ├── src/               # Rust 源代码
│   │   ├── main.rs        # 主入口
│   │   ├── lib.rs         # 库入口
│   │   └── cmd.rs         # Tauri 命令
│   ├── Cargo.toml         # Rust 依赖
│   ├── tauri.conf.json    # Tauri 配置
│   ├── build.gradle       # Android Gradle 配置
│   ├── local.properties   # SDK/NDK 路径
│   ├── capabilities/       # 权限配置
│   └── icons/             # 应用图标
└── firmware/              # ESP32C6 固件源码
```

## 开发环境

### 前端
- Node.js 18+
- npm 或 pnpm
- Vite 5.x

### 后端
- Rust 1.70+
- Tauri CLI 2.x

### Android
- Android SDK (API 34)
- Android NDK (r25c)
- Android Gradle Plugin 8.2.0
- Gradle 8.2
- **最低支持 Android 9 (API 28)**

### 硬件
- ESP32C6 开发板
- USB 数据线 (支持 OTG)

## 安装步骤

### 1. 安装前端依赖

```bash
npm install
```

### 2. 安装 Rust 环境

访问 https://rustup.rs 安装 Rust 工具链。

### 3. 安装 Android 开发环境

1. 下载 Android Studio: https://developer.android.com/studio
2. 安装 Android SDK (API 34)
3. 安装 Android NDK (25.2.9519663)
4. 配置 `src-tauri/local.properties` 中的 SDK 路径

### 4. 配置串口驱动（Windows）

下载并安装 CH340/CP210x USB 转串口驱动。

## 运行开发版本

```bash
# 开发模式（热重载）
npm run tauri:dev

# 仅前端开发
npm run dev
```

## 构建发布版本

```bash
# 构建 Android APK
npm run tauri:build

# 调试 APK 输出位置
# src-tauri/target/release/apk/
```

## 功能特性

### 固件端 (ESP32C6)
- 并行 WiFi 2.4G 混杂模式嗅探
- BLE 蓝牙持续扫描
- USB 虚拟串口数据输出
- BLE UART 广播服务
- 设备去重和过期清理

### Android 端
- 移动端原生应用
- WebSerial USB 串口直连
- WebBluetooth BLE 无线连接
- 实时雷达图可视化
- 设备列表和详情展示
- OUI 厂商库自动识别
- RSSI 距离估算
- 深色/浅色主题
- 设置参数自定义

## 数据格式

固件输出：
```
节点编号|MAC地址|RSSI|信号类型
```

示例：
```
1|AA:BB:CC:DD:EE:FF|-65|WIFI
1|11:22:33:44:55:66|-72|BLE
```

## 配置说明

在应用设置中可调整：
- **距离计算参数 (n)**: 路径损耗指数，默认 2.5
- **1米处 RSSI**: 参考信号强度，默认 -59 dBm
- **设备超时**: 离线设备清理时间，默认 30 秒
- **刷新频率**: 界面更新间隔，默认 1000 毫秒

## Android 权限

应用需要以下权限：
- `BLUETOOTH` - 蓝牙基础通信
- `BLUETOOTH_ADMIN` - 蓝牙管理
- `BLUETOOTH_SCAN` - 蓝牙设备扫描
- `BLUETOOTH_CONNECT` - 蓝牙设备连接
- `ACCESS_FINE_LOCATION` - 精确定位
- `ACCESS_COARSE_LOCATION` - 模糊定位
- `NEARBY_WIFI_DEVICES` - 附近 WiFi 设备

## 注意事项

1. WiFi 嗅探功能在部分地区需要合规授权
2. Android 9.0+ 已支持所有功能
3. 多节点使用时确保每个节点有唯一的 `NODE_ID`
4. 应用图标需要替换 `src-tauri/icons/` 目录下的文件
5. 首次安装需要开启"允许安装未知来源应用"

## 许可证

MIT License
