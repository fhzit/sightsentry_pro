import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

import 'connection_status.dart';
import 'models.dart';

const String sentryServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String sentryNotifyUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

class SentryController extends ChangeNotifier {
  final Map<String, SentryDevice> _devices = {};
  final List<String> _logs = [];
  final Set<int> _nodes = {};

  UsbPort? _usbPort;
  Transaction<String>? _usbTransaction;
  StreamSubscription<String>? _usbSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _bleStateSubscription;
  StreamSubscription<List<int>>? _bleNotifySubscription;
  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _bleCharacteristic;
  Timer? _expiryTimer;

  ConnectionStatus _status = ConnectionStatus.idle;
  String _filter = 'all';
  bool _personalDevicesOnly = false;
  bool _personalDevicesOnlyBleOnly = false;

  SentryController() {
    _expiryTimer = Timer.periodic(const Duration(seconds: 2), (_) => pruneExpired());
  }

  List<SentryDevice> get devices {
    final list = _devices.values.where((device) {
      if (_personalDevicesOnly && !_personalDevicesOnlyBleOnly && !device.isPersonalDevice) return false;
      if (_personalDevicesOnly && _personalDevicesOnlyBleOnly && device.type == SignalType.ble && !device.isPersonalDevice) return false;
      if (_filter == 'wifi') return device.type == SignalType.wifi;
      if (_filter == 'ble') return device.type == SignalType.ble;
      return true;
    }).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  List<String> get logs => List.unmodifiable(_logs.reversed.take(80));
  List<int> get nodes => _nodes.toList()..sort();
  ConnectionStatus get status => _status;
  String get filter => _filter;
  bool get personalDevicesOnly => _personalDevicesOnly;
  bool get personalDevicesOnlyBleOnly => _personalDevicesOnlyBleOnly;
  int get wifiCount => _devices.values.where((d) => d.type == SignalType.wifi).length;
  int get bleCount => _devices.values.where((d) => d.type == SignalType.ble).length;

  void setFilter(String value) {
    _filter = value;
    notifyListeners();
  }

  void setPersonalDevicesOnly(bool value) {
    _personalDevicesOnly = value;
    notifyListeners();
  }

  void setPersonalDevicesOnlyBleOnly(bool value) {
    _personalDevicesOnlyBleOnly = value;
    notifyListeners();
  }

  Future<void> connectUsb() async {
    await disconnect();
    _setStatus(const ConnectionStatus(
      kind: ConnectionKind.usb,
      state: ConnectionStateKind.connecting,
      label: '正在连接 OTG',
      detail: '查找 USB 串口设备',
    ));

    try {
      final devices = await UsbSerial.listDevices();
      if (devices.isEmpty) {
        throw StateError('没有发现 USB 串口设备，请确认 OTG 线和 ESP32 已连接');
      }

      final device = _pickUsbDevice(devices);
      final port = await device.create();
      if (port == null) throw StateError('无法创建 USB 串口');
      if (!await port.open()) throw StateError('USB 权限被拒绝或串口无法打开');

      await port.setDTR(true);
      await port.setRTS(true);
      await port.setPortParameters(115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

      _usbPort = port;
      _usbTransaction = Transaction.stringTerminated(port.inputStream!, Uint8List.fromList([10]));
      _usbSubscription = _usbTransaction!.stream.listen(_handleLine, onError: (Object error) {
        _log('USB 读取错误：$error');
      }, onDone: () {
        _setStatus(const ConnectionStatus(kind: ConnectionKind.usb, state: ConnectionStateKind.idle, label: 'USB 已断开'));
      });

      _setStatus(ConnectionStatus(
        kind: ConnectionKind.usb,
        state: ConnectionStateKind.connected,
        label: 'OTG 已连接',
        detail: '${device.productName ?? 'ESP32 串口'} · 115200 baud',
      ));
      _log('OTG connected: ${device.productName ?? device.deviceName}');
    } catch (error) {
      await disconnect();
      _setStatus(ConnectionStatus(kind: ConnectionKind.usb, state: ConnectionStateKind.error, label: 'OTG 连接失败', detail: '$error'));
      _log('OTG failed: $error');
    }
  }

  UsbDevice _pickUsbDevice(List<UsbDevice> devices) {
    const preferredVendors = {6790, 4292, 1027, 9025, 12346};
    return devices.firstWhere(
      (device) => preferredVendors.contains(device.vid),
      orElse: () => devices.first,
    );
  }

  Future<void> connectBle() async {
    await disconnect();
    _setStatus(const ConnectionStatus(
      kind: ConnectionKind.ble,
      state: ConnectionStateKind.scanning,
      label: '正在扫描 BLE',
      detail: '查找 SightSentry 节点',
    ));

    try {
      await _requestBlePermissions();
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        throw StateError('蓝牙未开启');
      }

      BluetoothDevice? target;
      final completer = Completer<BluetoothDevice?>();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final name = result.device.platformName;
          final hasService = result.advertisementData.serviceUuids
              .map((uuid) => uuid.str.toLowerCase())
              .contains(sentryServiceUuid);
          if (name.toLowerCase().contains('sightsentry') || hasService) {
            target = result.device;
            if (!completer.isCompleted) completer.complete(target);
            return;
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8), withServices: [Guid(sentryServiceUuid)]);
      target = await completer.future.timeout(const Duration(seconds: 9), onTimeout: () => target);
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;

      if (target == null) throw StateError('没有发现 SightSentry BLE 节点');
      _setStatus(ConnectionStatus(kind: ConnectionKind.ble, state: ConnectionStateKind.connecting, label: '正在连接 BLE', detail: target!.platformName));

      _bleDevice = target;
      await target!.connect(timeout: const Duration(seconds: 12), autoConnect: false);
      _bleStateSubscription = target!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && _status.kind == ConnectionKind.ble) {
          _setStatus(const ConnectionStatus(kind: ConnectionKind.ble, state: ConnectionStateKind.idle, label: 'BLE 已断开'));
        }
      });

      final services = await target!.discoverServices();
      for (final service in services) {
        if (service.uuid.str.toLowerCase() == sentryServiceUuid) {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid.str.toLowerCase() == sentryNotifyUuid) {
              _bleCharacteristic = characteristic;
            }
          }
        }
      }
      if (_bleCharacteristic == null) throw StateError('节点缺少通知特征值');

      await _bleCharacteristic!.setNotifyValue(true);
      var buffer = '';
      _bleNotifySubscription = _bleCharacteristic!.lastValueStream.listen((value) {
        buffer += utf8.decode(value, allowMalformed: true);
        final lines = buffer.split('\n');
        buffer = lines.removeLast();
        for (final line in lines) {
          _handleLine(line);
        }
      });

      _setStatus(ConnectionStatus(
        kind: ConnectionKind.ble,
        state: ConnectionStateKind.connected,
        label: 'BLE 已连接',
        detail: target!.platformName.isEmpty ? target!.remoteId.str : target!.platformName,
      ));
      _log('BLE connected: ${target!.platformName}');
    } catch (error) {
      await disconnect();
      _setStatus(ConnectionStatus(kind: ConnectionKind.ble, state: ConnectionStateKind.error, label: 'BLE 连接失败', detail: '$error'));
      _log('BLE failed: $error');
    }
  }

  Future<void> _requestBlePermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  void _handleLine(String line) {
    final frame = SentryFrame.parse(line);
    if (frame == null) {
      if (line.trim().isNotEmpty) _log(line.trim());
      return;
    }

    final now = DateTime.now();
    final current = _devices[frame.id];
    _nodes.add(frame.nodeId);
    if (current == null) {
      _devices[frame.id] = SentryDevice(
        nodeId: frame.nodeId,
        mac: frame.mac,
        rssi: frame.rssi,
        type: frame.type,
        name: frame.name,
        rawType: frame.rawType,
        lastSeen: now,
      );
    } else {
      _devices[frame.id] = current.copyWithSample(nodeId: frame.nodeId, rssi: frame.rssi, now: now, name: frame.name);
    }
    notifyListeners();
  }

  void pruneExpired() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 30));
    _devices.removeWhere((_, device) => device.lastSeen.isBefore(cutoff));
    notifyListeners();
  }

  void clearDevices() {
    _devices.clear();
    _nodes.clear();
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _usbSubscription?.cancel();
    _usbSubscription = null;
    _usbTransaction?.dispose();
    _usbTransaction = null;
    await _usbPort?.close();
    _usbPort = null;

    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await FlutterBluePlus.stopScan().catchError((_) {});
    await _bleNotifySubscription?.cancel();
    _bleNotifySubscription = null;
    await _bleStateSubscription?.cancel();
    _bleStateSubscription = null;
    if (_bleCharacteristic != null) {
      await _bleCharacteristic!.setNotifyValue(false).catchError((_) => false);
      _bleCharacteristic = null;
    }
    await _bleDevice?.disconnect().catchError((_) {});
    _bleDevice = null;

    _setStatus(ConnectionStatus.idle);
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    notifyListeners();
  }

  void _log(String message) {
    final time = DateTime.now();
    final stamp = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    _logs.add('[$stamp] $message');
    if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    unawaited(disconnect());
    super.dispose();
  }
}
