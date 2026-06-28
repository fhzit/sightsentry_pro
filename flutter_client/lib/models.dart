import 'dart:math' as math;

import 'ble_company_ids.dart';
import 'oui_vendors.dart';

enum SignalType { wifi, ble }

enum DeviceCategory { phone, tablet, watch, headphone, accessPoint, other }

enum IdentitySource { broadcastName, bleManufacturerData, macOui, unknown }

enum DistanceBand { veryNear, near, medium, far }

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
    this.manufacturerData = '',
    this.serviceUuids = '',
    this.txPower,
    int? lastRssi,
    Map<int, int>? nodeRssi,
  })  : lastRssi = lastRssi ?? rssi,
        nodeRssi = nodeRssi ?? {nodeId: rssi};

  final int nodeId;
  final String mac;
  final int rssi;
  final int lastRssi;
  final SignalType type;
  final String name;
  final String rawType;
  final String manufacturerData;
  final String serviceUuids;
  final int? txPower;
  final DateTime lastSeen;
  final Map<int, int> nodeRssi;

  String get id => '${type.name}:${signalBucket(type, rawType)}:$mac';
  String get title => name.isNotEmpty ? name : vendor;
  String? get bleVendor => identifyBleManufacturer(manufacturerData);
  String get ouiVendor => identifyVendor(mac, fallback: '');
  String get vendor {
    final fromBle = bleVendor;
    if (fromBle != null && fromBle.isNotEmpty) return fromBle;
    if (ouiVendor.isNotEmpty) return ouiVendor;
    return type == SignalType.ble ? 'Bluetooth LE 设备' : '未知厂商';
  }

  IdentitySource get identitySource {
    if (name.isNotEmpty) return IdentitySource.broadcastName;
    if (bleVendor != null && bleVendor!.isNotEmpty) return IdentitySource.bleManufacturerData;
    if (ouiVendor.isNotEmpty) return IdentitySource.macOui;
    return IdentitySource.unknown;
  }

  String get identitySourceLabel => identitySource.label;
  String get typeLabel {
    if (type == SignalType.ble) return 'Bluetooth LE';
    return isWifiAp ? 'WiFi AP / 路由器' : 'WiFi Probe Request';
  }
  String get shortTypeLabel => type == SignalType.ble ? 'LE' : (isWifiAp ? 'AP' : 'WiFi');
  String get sourceLabel {
    if (type == SignalType.ble) return 'BLE 广播';
    return isWifiAp ? 'AP Beacon / Probe Response' : 'Probe Request';
  }
  bool get isWifiAp => type == SignalType.wifi && rawType.toUpperCase().contains('AP');
  bool get usesLegacyWifiType => type == SignalType.wifi && !rawType.toUpperCase().contains('PROBE') && !isWifiAp;
  DeviceCategory get category => inferDeviceCategory(name: name, vendor: vendor, type: type, rawType: rawType);
  String get categoryLabel => deviceCategoryLabel(category);
  bool get isPersonalDevice => category != DeviceCategory.other;
  double get distanceMeters => estimateDistanceMeters(rssi);
  DistanceBand get distanceBand => inferDistanceBand(rssi);
  String get distanceBandLabel => distanceBand.label;
  bool get hasBleMetadata => manufacturerData.isNotEmpty || serviceUuids.isNotEmpty || txPower != null;

  SentryDevice copyWithSample({
    required int nodeId,
    required int rssi,
    required DateTime now,
    String? name,
    String? manufacturerData,
    String? serviceUuids,
    int? txPower,
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
      manufacturerData: (manufacturerData != null && manufacturerData.isNotEmpty) ? manufacturerData : this.manufacturerData,
      serviceUuids: (serviceUuids != null && serviceUuids.isNotEmpty) ? serviceUuids : this.serviceUuids,
      txPower: txPower ?? this.txPower,
      lastRssi: rssi,
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
    this.manufacturerData = '',
    this.serviceUuids = '',
    this.txPower,
  });

  final int nodeId;
  final String mac;
  final int rssi;
  final SignalType type;
  final String name;
  final String rawType;
  final String manufacturerData;
  final String serviceUuids;
  final int? txPower;

  String get id => '${type.name}:${signalBucket(type, rawType)}:$mac';

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
    String manufacturerData = '';
    String serviceUuids = '';
    int? txPower;

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
      if (parts.length > 4) name = parts[4].trim();
      if (parts.length > 5) manufacturerData = normalizeHex(parts[5]);
      if (parts.length > 6) serviceUuids = parts[6].trim();
      if (parts.length > 7) txPower = int.tryParse(parts[7].trim());
    }

    if (!_macLike(mac)) return null;
    final rawType = typeText.toUpperCase();
    final type = rawType.contains('BLE') ? SignalType.ble : SignalType.wifi;
    return SentryFrame(
      nodeId: nodeId,
      mac: mac,
      rssi: rssi,
      type: type,
      name: name,
      rawType: rawType,
      manufacturerData: manufacturerData,
      serviceUuids: serviceUuids,
      txPower: txPower,
    );
  }

  static bool _macLike(String value) {
    return RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$').hasMatch(value);
  }
}

String signalBucket(SignalType type, String rawType) {
  if (type == SignalType.ble) return 'ble';
  return rawType.toUpperCase().contains('AP') ? 'ap' : 'probe';
}

String normalizeMac(String value) => value.trim().replaceAll('-', ':').toUpperCase();

String normalizeHex(String value) => value.trim().replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();

String identifyVendor(String mac, {String fallback = '未知厂商'}) {
  final normalized = normalizeMac(mac);
  if (normalized.length < 8) return fallback;
  final prefix = normalized.substring(0, 8);
  return manualOuiVendors[prefix] ?? ieeeOuiVendors[prefix] ?? fallback;
}

String? identifyBleManufacturer(String manufacturerData) {
  final hex = normalizeHex(manufacturerData);
  if (hex.length < 4) return null;
  final low = int.tryParse(hex.substring(0, 2), radix: 16);
  final high = int.tryParse(hex.substring(2, 4), radix: 16);
  if (low == null || high == null) return null;
  final companyId = low | (high << 8);
  return bleCompanyIds[companyId];
}

DeviceCategory inferDeviceCategory({required String name, required String vendor, required SignalType type, String rawType = ''}) {
  if (type == SignalType.wifi && rawType.toUpperCase().contains('AP')) {
    return DeviceCategory.accessPoint;
  }
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
  if (type == SignalType.wifi && _containsAny(haystack, const ['apple, inc.', 'samsung electronics', 'google', 'lg electronics'])) {
    return DeviceCategory.phone;
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
    case DeviceCategory.accessPoint:
      return 'AP/路由器';
    case DeviceCategory.other:
      return '其他';
  }
}

extension IdentitySourceLabel on IdentitySource {
  String get label {
    switch (this) {
      case IdentitySource.broadcastName:
        return '广播名称';
      case IdentitySource.bleManufacturerData:
        return 'BLE 厂商数据';
      case IdentitySource.macOui:
        return 'MAC OUI';
      case IdentitySource.unknown:
        return '未知';
    }
  }
}

extension DistanceBandLabel on DistanceBand {
  String get label {
    switch (this) {
      case DistanceBand.veryNear:
        return '很近';
      case DistanceBand.near:
        return '近';
      case DistanceBand.medium:
        return '中等';
      case DistanceBand.far:
        return '远';
    }
  }
}

DistanceBand inferDistanceBand(int rssi) {
  if (rssi >= -55) return DistanceBand.veryNear;
  if (rssi >= -67) return DistanceBand.near;
  if (rssi >= -80) return DistanceBand.medium;
  return DistanceBand.far;
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

String abbreviateMiddle(String value, {int maxLength = 32}) {
  if (value.length <= maxLength) return value;
  final edge = ((maxLength - 1) / 2).floor();
  return '${value.substring(0, edge)}…${value.substring(value.length - edge)}';
}

double signalQuality(int rssi) {
  return ((rssi + 100) / 55).clamp(0.0, 1.0);
}
