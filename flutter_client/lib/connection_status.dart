enum ConnectionKind { none, usb, ble }

enum ConnectionStateKind { idle, scanning, connecting, connected, error }

class ConnectionStatus {
  const ConnectionStatus({
    required this.kind,
    required this.state,
    this.label = '未连接',
    this.detail = '',
  });

  final ConnectionKind kind;
  final ConnectionStateKind state;
  final String label;
  final String detail;

  bool get isConnected => state == ConnectionStateKind.connected;

  static const idle = ConnectionStatus(kind: ConnectionKind.none, state: ConnectionStateKind.idle);
}
