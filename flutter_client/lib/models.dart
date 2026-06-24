import 'dart:math' as math;

enum SignalType { wifi, ble }

const Map<String, String> ouiVendors = {
  '00:1A:2B': 'Intel',
  '00:1E:8C': 'Apple',
  '00:21:CC': 'Apple',
  '00:23:12': 'Apple',
  '00:23:DF': 'Apple',
  '00:26:08': 'Apple',
  '00:26:BB': 'Apple',
  '00:30:65': 'Cisco',
  '00:40:96': 'Cisco',
  '0C:17:73': 'Huawei',
  '18:00:20': 'Apple',
  '28:63:36': 'Apple',
  '30:23:03': 'Apple',
  '34:15:9E': 'Apple',
  '38:2C:4A': 'Apple',
  '40:B0:34': 'Apple',
  '44:39:C4': 'Apple',
  '50:28:73': 'Huawei',
  '58:55:CA': 'Apple',
  '5C:AA:FD': 'Apple',
  '60:14:5C': 'Samsung',
  '64:B9:E8': 'Apple',
  '68:5B:35': 'Apple',
  '70:56:81': 'Apple',
  '78:CA:39': 'Apple',
  '7C:6D:62': 'Apple',
  '80:2A:A8': 'Apple',
  '84:38:35': 'Apple',
  '88:1F:A1': 'Samsung',
  '90:27:E4': 'Apple',
  '94:10:3B': 'Samsung',
  '98:01:A7': 'Apple',
  'A0:88:B4': 'Apple',
  'A4:5E:60': 'Apple',
  'AC:DE:48': 'Apple',
  'B4:99:4C': 'Apple',
  'BC:17:BB': 'Samsung',
  'C0:EE:FB': 'Apple',
  'C4:2C:03': 'Apple',
  'C8:2A:14': 'Apple',
  'D0:23:DB': 'Apple',
  'D4:9A:20': 'Apple',
  'DC:4A:3E': 'Apple',
  'E0:98:06': 'Apple',
  'E4:95:6E': 'Apple',
  'EC:35:86': 'Apple',
  'F0:18:98': 'Apple',
  'F4:5C:89': 'Apple',
  'FC:86:2A': 'Huawei',
};

class SentryDevice {
  SentryDevice({
    required this.nodeId,
    required this.mac,
    required this.rssi,
    required this.type,
    required this.lastSeen,
    this.name = '',
    Map<int, int>? nodeRssi,
  }) : nodeRssi = nodeRssi ?? {nodeId: rssi};

  final int nodeId;
  final String mac;
  final int rssi;
  final SignalType type;
  final String name;
  final DateTime lastSeen;
  final Map<int, int> nodeRssi;

  String get id => '${type.name}:$mac';
  String get title => name.isNotEmpty ? name : vendor;
  String get vendor => identifyVendor(mac, fallback: type == SignalType.ble ? 'Bluetooth LE 设备' : '通用');
  String get typeLabel => type == SignalType.ble ? 'Bluetooth LE' : 'WiFi';
  String get shortTypeLabel => type == SignalType.ble ? 'LE' : 'WIFI';
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
  });

  final int nodeId;
  final String mac;
  final int rssi;
  final SignalType type;
  final String name;

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
    final type = typeText.toUpperCase().contains('BLE') ? SignalType.ble : SignalType.wifi;
    return SentryFrame(nodeId: nodeId, mac: mac, rssi: rssi, type: type, name: name);
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
  return ouiVendors[prefix] ?? fallback;
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
