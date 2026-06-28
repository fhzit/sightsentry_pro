import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'connection_status.dart';
import 'models.dart';
import 'sentry_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SightSentryApp());
}

class SightSentryApp extends StatelessWidget {
  const SightSentryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SightSentry Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(primary: AppColors.blue, surface: AppColors.card),
      ),
      home: const HomePage(),
    );
  }
}

class AppColors {
  static const background = Color(0xFF050607);
  static const surface = Color(0xFF111316);
  static const card = Color(0xFF191C20);
  static const cardAlt = Color(0xFF20242A);
  static const divider = Color(0xFF2D3239);
  static const primaryText = Color(0xFFF4F7FB);
  static const secondaryText = Color(0xFF8F98A5);
  static const blue = Color(0xFF1E9BFF);
  static const pink = Color(0xFFFF4E78);
  static const green = Color(0xFF4DDBA7);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final SentryController controller;

  @override
  void initState() {
    super.initState();
    controller = SentryController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final devices = controller.devices;
        return Scaffold(
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TitleBar(controller: controller),
                        const SizedBox(height: 18),
                        _SignalFilterBar(controller: controller),
                        const SizedBox(height: 16),
                        _StatusCard(controller: controller),
                        const SizedBox(height: 22),
                        _DeviceHeader(count: devices.length, onClear: controller.clearDevices),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  sliver: devices.isEmpty
                      ? const SliverToBoxAdapter(child: _EmptyCard())
                      : SliverToBoxAdapter(child: _DeviceListCard(devices: devices)),
                ),
                if (controller.logs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                      child: _LogCard(logs: controller.logs),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.controller});

  final SentryController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('SightSentry Pro', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryText)),
        const Spacer(),
        IconButton(
          tooltip: '设置',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(controller: controller))),
          icon: const Icon(Icons.settings_rounded, color: AppColors.blue, size: 28),
        ),
      ],
    );
  }
}

class _SignalFilterBar extends StatelessWidget {
  const _SignalFilterBar({required this.controller});

  final SentryController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              active: controller.filter == 'wifi',
              icon: Icons.wifi_rounded,
              label: 'WiFi',
              count: controller.wifiCount,
              onTap: () => controller.setFilter(controller.filter == 'wifi' ? 'all' : 'wifi'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SegmentButton(
              active: controller.filter == 'ble',
              icon: Icons.bluetooth_rounded,
              label: '蓝牙',
              count: controller.bleCount,
              onTap: () => controller.setFilter(controller.filter == 'ble' ? 'all' : 'ble'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({required this.active, required this.icon, required this.label, required this.onTap, this.count});

  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(color: active ? AppColors.surface : Colors.transparent, borderRadius: BorderRadius.circular(17)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? AppColors.blue : AppColors.secondaryText, size: 28),
            const SizedBox(height: 6),
            Text(count == null ? label : '$label · $count', style: TextStyle(color: active ? AppColors.blue : AppColors.secondaryText, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final SentryController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
              children: [
                Row(children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryText)),
                  const Expanded(child: Center(child: Text('设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primaryText)))),
                  const SizedBox(width: 48),
                ]),
                const SizedBox(height: 20),
                const Text('连接方式', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryText)),
                const SizedBox(height: 10),
                _SettingsCard(children: [
                  _ConnectionOption(
                    icon: Icons.usb_rounded,
                    title: 'USB OTG',
                    subtitle: controller.status.kind == ConnectionKind.usb ? controller.status.label : '通过 USB 串口连接 ESP32 节点',
                    active: controller.status.kind == ConnectionKind.usb,
                    onTap: controller.connectUsb,
                  ),
                  const Divider(height: 1, color: AppColors.divider, indent: 60),
                  _ConnectionOption(
                    icon: Icons.bluetooth_rounded,
                    title: '蓝牙 BLE',
                    subtitle: controller.status.kind == ConnectionKind.ble ? controller.status.label : '通过 BLE UART 连接 SightSentry 节点',
                    active: controller.status.kind == ConnectionKind.ble,
                    onTap: controller.connectBle,
                  ),
                ]),
                const SizedBox(height: 22),
                const Text('设备显示', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryText)),
                const SizedBox(height: 10),
                _SettingsCard(children: [
                  SwitchListTile.adaptive(
                    value: controller.personalDevicesOnly,
                    onChanged: controller.setPersonalDevicesOnly,
                    activeThumbColor: AppColors.blue,
                    title: const Text('只显示手机/平板/手表/耳机', style: TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w700)),
                    subtitle: const Text('隐藏无法识别为个人终端的设备', style: TextStyle(color: AppColors.secondaryText)),
                  ),
                  const Divider(height: 1, color: AppColors.divider, indent: 16),
                  Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: SwitchListTile.adaptive(
                      value: controller.personalDevicesOnlyBleOnly,
                      onChanged: controller.personalDevicesOnly ? controller.setPersonalDevicesOnlyBleOnly : null,
                      activeThumbColor: AppColors.blue,
                      title: const Text('仅对蓝牙生效', style: TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w700)),
                      subtitle: const Text('开启后 WiFi 设备不受上方筛选限制', style: TextStyle(color: AppColors.secondaryText)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18)),
      child: Column(children: children),
    );
  }
}

class _ConnectionOption extends StatelessWidget {
  const _ConnectionOption({required this.icon, required this.title, required this.subtitle, required this.active, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: active ? AppColors.blue : AppColors.secondaryText),
      title: Text(title, style: TextStyle(color: active ? AppColors.blue : AppColors.primaryText, fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.secondaryText)),
      trailing: active ? const Icon(Icons.check_circle_rounded, color: AppColors.green) : const Icon(Icons.chevron_right_rounded, color: AppColors.secondaryText),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final SentryController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final busy = status.state == ConnectionStateKind.connecting || status.state == ConnectionStateKind.scanning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: status.isConnected ? AppColors.green.withValues(alpha: .15) : AppColors.blue.withValues(alpha: .14), shape: BoxShape.circle),
            child: busy
                ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.blue))
                : Icon(status.isConnected ? Icons.link_rounded : Icons.link_off_rounded, color: status.isConnected ? AppColors.green : AppColors.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(status.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryText)),
              const SizedBox(height: 4),
              Text(status.detail.isEmpty ? '支持 ESP32C6 USB OTG 或 BLE UART 节点' : status.detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.secondaryText)),
            ]),
          ),
          if (status.kind != ConnectionKind.none)
            IconButton(onPressed: controller.disconnect, icon: const Icon(Icons.close_rounded, color: AppColors.secondaryText)),
        ],
      ),
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({required this.count, required this.onClear});

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('设备 ($count)', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primaryText)),
        const Spacer(),
        IconButton(onPressed: onClear, icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.secondaryText)),
        const Icon(Icons.swap_vert_rounded, color: AppColors.secondaryText),
      ],
    );
  }
}

class _DeviceListCard extends StatelessWidget {
  const _DeviceListCard({required this.devices});

  final List<SentryDevice> devices;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          for (var index = 0; index < devices.length; index++) ...[
            _DeviceRow(device: devices[index]),
            if (index != devices.length - 1) const Divider(height: 1, color: AppColors.divider, indent: 72),
          ],
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device});

  final SentryDevice device;

  @override
  Widget build(BuildContext context) {
    final color = device.type == SignalType.ble ? AppColors.pink : AppColors.blue;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeviceDetailPage(device: device))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        child: Row(
          children: [
            _DeviceGlyph(type: device.type),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(device.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primaryText))),
                  if (device.type == SignalType.ble) const _LeBadge(),
                ]),
                const SizedBox(height: 4),
                Text('${device.vendor} · ${device.categoryLabel} · ${device.identitySourceLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.secondaryText, fontSize: 12)),
                const SizedBox(height: 2),
                Text(device.mac.toLowerCase(), style: const TextStyle(color: AppColors.secondaryText, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 6),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${device.rssi} dBm', style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text('${device.distanceBandLabel} · ${formatDistance(device.distanceMeters)}', style: const TextStyle(color: AppColors.secondaryText, fontSize: 12)),
            ]),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.secondaryText),
          ],
        ),
      ),
    );
  }
}

class DeviceDetailPage extends StatelessWidget {
  const DeviceDetailPage({super.key, required this.device});

  final SentryDevice device;

  @override
  Widget build(BuildContext context) {
    final color = device.type == SignalType.ble ? AppColors.pink : AppColors.blue;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryText)),
              const Expanded(child: Center(child: Text('设备详情', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primaryText)))),
              TextButton(onPressed: () {}, child: const Text('编辑', style: TextStyle(color: AppColors.blue, fontSize: 16))),
            ]),
            const SizedBox(height: 22),
            Center(child: _LargeDeviceGlyph(type: device.type)),
            const SizedBox(height: 18),
            Center(child: Text(device.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryText))),
            const SizedBox(height: 8),
            Center(child: _TypeBadge(label: device.typeLabel)),
            const SizedBox(height: 24),
            _InfoCard(rows: [
              _InfoRow('MAC', device.mac),
              _InfoRow('制造商', device.vendor),
              _InfoRow('信号来源', device.usesLegacyWifiType ? '${device.sourceLabel}（兼容 WIFI）' : device.sourceLabel),
              _InfoRow('识别依据', device.identitySourceLabel),
              _InfoRow('设备类别', device.categoryLabel),
              _InfoRow('节点', '节点 ${device.nodeId}'),
            ]),
            const SizedBox(height: 24),
            Text(device.type == SignalType.ble ? '蓝牙' : 'WiFi', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryText)),
            const SizedBox(height: 10),
            _SignalCard(device: device, color: color),
            const SizedBox(height: 16),
            _InfoCard(rows: [
              _InfoRow('距离等级', device.distanceBandLabel),
              _InfoRow('估算距离', formatDistance(device.distanceMeters)),
              _InfoRow('平滑信号', '${device.rssi} dBm'),
              _InfoRow('最近信号', '${device.lastRssi} dBm'),
              _InfoRow(device.type == SignalType.ble ? '蓝牙类型' : '无线类型', device.typeLabel),
            ]),
            if (device.type == SignalType.ble && device.hasBleMetadata) ...[
              const SizedBox(height: 16),
              _InfoCard(rows: [
                if (device.bleVendor != null) _InfoRow('BLE 厂商', device.bleVendor!),
                if (device.manufacturerData.isNotEmpty) _InfoRow('Manufacturer Data', abbreviateMiddle(device.manufacturerData, maxLength: 28)),
                if (device.serviceUuids.isNotEmpty) _InfoRow('Service UUID', abbreviateMiddle(device.serviceUuids, maxLength: 28)),
                if (device.txPower != null) _InfoRow('TX Power', '${device.txPower} dBm'),
              ]),
            ],
            const SizedBox(height: 12),
            const Text('距离为 RSSI 估算值，会受遮挡、人体、天线方向和设备发射功率影响。', style: TextStyle(color: AppColors.secondaryText, fontSize: 13, height: 1.45)),
          ],
        ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.device, required this.color});

  final SentryDevice device;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final quality = signalQuality(device.rssi);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(device.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryText))),
                if (device.type == SignalType.ble) const _LeBadge(),
              ]),
              const SizedBox(height: 5),
              Text(device.mac.toLowerCase(), style: const TextStyle(color: AppColors.secondaryText)),
            ]),
          ),
          Text('${device.rssi} dBm', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16)),
        ]),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(children: [
            Container(height: 4, color: color.withValues(alpha: .18)),
            FractionallySizedBox(widthFactor: quality, child: Container(height: 4, color: color)),
            Align(alignment: Alignment((quality * 2 - 1).clamp(-1, 1), 0), child: Container(width: 3, height: 14, color: Colors.white)),
          ]),
        ),
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(children: [
              Text(rows[i].label, style: const TextStyle(color: AppColors.secondaryText, fontSize: 16)),
              const Spacer(),
              Flexible(child: Text(rows[i].value, textAlign: TextAlign.right, style: const TextStyle(color: AppColors.primaryText, fontSize: 16, fontWeight: FontWeight.w600))),
            ]),
          ),
          if (i != rows.length - 1) const Divider(height: 1, color: AppColors.divider, indent: 16),
        ],
      ]),
    );
  }
}

class _InfoRow {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
}

class _DeviceGlyph extends StatelessWidget {
  const _DeviceGlyph({required this.type});

  final SignalType type;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: CustomPaint(painter: DeviceGlyphPainter(type: type)),
    );
  }
}

class _LargeDeviceGlyph extends StatelessWidget {
  const _LargeDeviceGlyph({required this.type});
  final SignalType type;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 92, height: 72, child: CustomPaint(painter: DeviceGlyphPainter(type: type, large: true)));
  }
}

class DeviceGlyphPainter extends CustomPainter {
  DeviceGlyphPainter({required this.type, this.large = false});
  final SignalType type;
  final bool large;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFABB3BC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = large ? 3.2 : 2.2
      ..strokeCap = StrokeCap.round;
    final r = Radius.circular(large ? 7 : 5);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * .08, size.height * .18, size.width * .58, size.height * .52), r), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * .36, size.height * .34, size.width * .52, size.height * .48), r), paint);
    canvas.drawLine(Offset(size.width * .28, size.height * .82), Offset(size.width * .68, size.height * .82), paint);
    if (type == SignalType.ble) {
      final blue = paint..color = AppColors.blue;
      final cx = size.width * .78;
      final cy = size.height * .21;
      canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy + 10), blue);
      canvas.drawLine(Offset(cx, cy), Offset(cx + 10, cy - 8), blue);
      canvas.drawLine(Offset(cx, cy), Offset(cx + 10, cy + 8), blue);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LeBadge extends StatelessWidget {
  const _LeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 7),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: AppColors.secondaryText.withValues(alpha: .55)), borderRadius: BorderRadius.circular(5)),
      child: const Text('LE', style: TextStyle(fontSize: 10, color: AppColors.secondaryText, fontWeight: FontWeight.w800)),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: const TextStyle(color: AppColors.secondaryText, fontWeight: FontWeight.w700)),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: const Column(children: [
        Icon(Icons.travel_explore_rounded, size: 42, color: AppColors.secondaryText),
        SizedBox(height: 12),
        Text('暂无设备', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primaryText)),
        SizedBox(height: 6),
        Text('点击 OTG 或 Bluetooth 连接硬件节点后开始接收数据', textAlign: TextAlign.center, style: TextStyle(color: AppColors.secondaryText)),
      ]),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.logs});
  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('日志', style: TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final log in logs.take(5)) Text(log, style: const TextStyle(color: AppColors.secondaryText, fontSize: 12)),
      ]),
    );
  }
}

class IconSketchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..shader = const LinearGradient(colors: [Color(0xFF053B68), Color(0xFF061016)]).createShader(Offset.zero & size);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * .22)), bg);
    final ring = Paint()
      ..color = AppColors.blue.withValues(alpha: .9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .055;
    final center = Offset(size.width * .5, size.height * .54);
    for (final radius in [.18, .31]) {
      canvas.drawCircle(center, size.width * radius, ring..color = AppColors.blue.withValues(alpha: radius == .18 ? .9 : .45));
    }
    final sweep = Paint()
      ..color = AppColors.green.withValues(alpha: .55)
      ..strokeWidth = size.width * .04
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, center + Offset(math.cos(-.75), math.sin(-.75)) * size.width * .36, sweep);
    canvas.drawCircle(center, size.width * .055, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(size.width * .68, size.height * .34), size.width * .055, Paint()..color = AppColors.pink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
