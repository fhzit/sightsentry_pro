import 'dart:math' as math;

import 'oui_vendors.dart';

enum SignalType { wifi, ble }

enum DeviceCategory { phone, tablet, watch, headphone, other }

const Map<String, String> manualOuiVendors = {
  '00:1A:2B': 'Intel',
  '00:30:65': 'Cisco',
  '00:40:96': 'Cisco',
  '5C:AA:FD': 'Apple, Inc.',
  '60:14:5C': 'Samsung Electronics Co.,Ltd',
  '88:1F:A1': 'Samsung Electronics Co.,Ltd',
  '94:10:3B': 'Samsung Electronics Co.,Ltd',
  'BC:17:BB': 'Samsung Electronics Co.,Ltd',
  'FC:86:2A': 'HUAWEI TECHNOLOGIES CO.,LTD',
};

class SentryDevice {
  SentryDevice({
    required this.nodeId,
    required this.mac,
    required this.rssi,
    required this.type,
    required this.lastSeen,
    this.name = '',
    this.rawType = '',
    Map<int, int>? nodeRssi,
  }) : nodeRssi = nodeRssi ?? {nodeId: rssi};

  final int nodeId;
  final String mac;
  final int rssi;
  final SignalType type;
  final String name;
  final String rawType;
  final DateTime lastSeen;
  final Map<int, int> nodeRssi;

  String get id => '${type.name}:$mac';
  String get title => name.isNotEmpty ? name : vendor;
  String get vendor => identifyVendor(mac, fallback: type == SignalType.ble ? 'Bluetooth LE 设备' : '未知厂商');
  String get typeLabel => type == SignalType.ble ? 'Bluetooth LE' : 'WiFi Probe Request';
  String get shortTypeLabel => type == SignalType.ble ? 'LE' : 'WiFi';
  String get sourceLabel => type == SignalType.ble ? 'BLE 广播' : 'Probe Request';
  bool get usesLegacyWifiType => type == SignalType.wifi && !rawType.toUpperCase().contains('PROBE');
  DeviceCategory get category => inferDeviceCategory(name: name, vendor: vendor, type: type);
  String get categoryLabel => deviceCategoryLabel(category);
  bool get isPersonalDevice => category != DeviceCategory.other;
  double get distanceMeters => estimateDistanceMeters(rssi);

  SentryDevice copyWithSample({
    required int nodeId,
    required int rssi,
    required DateTime now,
    String? name,
  }) {
    final updatedNodeRssi = Map<int, int>.from(nodeRssi)..[nodeId] = rssi;
    final smoothed = ((this.rssi * 7) + (rssi * 3)) ~/ 10;
    return SentryDevice(
      nodeId: nodeId,
      mac: mac,
      rssi: smoothed,
      type: type,
      name: (name != null && name.isNotEmpty) ? name : this.name,
      rawType: rawType,
      lastSeen: now,
      nodeRssi: updatedNodeRssi,
    );
  }
}

class SentryFrame {
  const SentryFrame({
    required this.nodeId,
    required this.mac,
    required this.rssi,
    required this.type,
    this.name = '',
    this.rawType = '',
  });

  final int nodeId;
  final String mac;
  final int rssi;
  final SignalType type;
  final String name;
  final String rawType;

  String get id => '${type.name}:$mac';

  static SentryFrame? parse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('BLE client')) return null;
    final parts = trimmed.split('|');
    if (parts.length < 3) return null;

    int nodeId;
    String mac;
    int rssi;
    String typeText;
    String name = '';

    final firstAsNode = int.tryParse(parts[0]);
    if (firstAsNode == null && parts[0].contains(':')) {
      nodeId = 0;
      mac = normalizeMac(parts[0]);
      rssi = int.tryParse(parts[1].trim()) ?? -100;
      typeText = parts[2].trim();
      if (parts.length > 3) name = parts.sublist(3).join('|').trim();
    } else {
      if (parts.length < 4) return null;
      nodeId = firstAsNode ?? 0;
      mac = normalizeMac(parts[1]);
      rssi = int.tryParse(parts[2].trim()) ?? -100;
      typeText = parts[3].trim();
      if (parts.length > 4) name = parts.sublist(4).join('|').trim();
    }

    if (!_macLike(mac)) return null;
    final rawType = typeText.toUpperCase();
    final type = rawType.contains('BLE') ? SignalType.ble : SignalType.wifi;
    return SentryFrame(nodeId: nodeId, mac: mac, rssi: rssi, type: type, name: name, rawType: rawType);
  }

  static bool _macLike(String value) {
    return RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$').hasMatch(value);
  }
}

String normalizeMac(String value) => value.trim().replaceAll('-', ':').toUpperCase();

String identifyVendor(String mac, {String fallback = '未知厂商'}) {
  final normalized = normalizeMac(mac);
  if (normalized.length < 8) return fallback;
  final prefix = normalized.substring(0, 8);
  return manualOuiVendors[prefix] ?? ieeeOuiVendors[prefix] ?? fallback;
}

DeviceCategory inferDeviceCategory({required String name, required String vendor, required SignalType type}) {
  final haystack = '$name $vendor'.toLowerCase();
  if (_containsAny(haystack, const ['watch', 'band', 'bracelet', 'amazfit', 'garmin', 'fitbit'])) {
    return DeviceCategory.watch;
  }
  if (_containsAny(haystack, const ['airpods', 'buds', 'headphone', 'headset', 'earphone', 'earbud', 'beats', 'bose', 'jabra', 'sennheiser', 'jbl', 'soundcore'])) {
    return DeviceCategory.headphone;
  }
  if (_containsAny(haystack, const ['ipad', 'tablet', 'pad ', ' tab', 'galaxy tab', 'matepad', 'lenovo tab'])) {
    return DeviceCategory.tablet;
  }
  if (_containsAny(haystack, const ['iphone', 'phone', 'pixel', 'galaxy', 'huawei', 'honor', 'xiaomi', 'redmi', 'oppo', 'oneplus', 'vivo', 'realme', 'motorola', 'nokia', 'sony', 'zte', 'meizu', 'nothing'])) {
    return DeviceCategory.phone;
  }
  if (_containsAny(haystack, const ['apple, inc.', 'samsung electronics', 'google', 'lg electronics'])) {
    return type == SignalType.ble ? DeviceCategory.watch : DeviceCategory.phone;
  }
  return DeviceCategory.other;
}

bool _containsAny(String value, List<String> needles) => needles.any(value.contains);

String deviceCategoryLabel(DeviceCategory category) {
  switch (category) {
    case DeviceCategory.phone:
      return '手机';
    case DeviceCategory.tablet:
      return '平板';
    case DeviceCategory.watch:
      return '手表';
    case DeviceCategory.headphone:
      return '耳机';
    case DeviceCategory.other:
      return '其他';
  }
}

double estimateDistanceMeters(int rssi, {double exponent = 2.5, int rssiAtOneMeter = -59}) {
  final ratio = (rssiAtOneMeter - rssi) / (10 * exponent);
  final distance = math.pow(10, ratio).toDouble();
  return distance.clamp(0.1, 100).toDouble();
}

String formatDistance(double meters) {
  if (meters < 1) return '${(meters * 100).round()} cm';
  if (meters < 10) return '${meters.toStringAsFixed(1)} m';
  return '${meters.round()} m';
}

double signalQuality(int rssi) {
  return ((rssi + 100) / 55).clamp(0.0, 1.0);
}
