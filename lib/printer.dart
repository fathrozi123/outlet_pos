import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'db.dart';
import 'nota.dart';

class Printer {
  /// Minta izin Bluetooth (Android 12+) sebelum memakai printer.
  static Future<bool> askPermission() async {
    if (await Permission.bluetoothConnect.isGranted) return true;
    final r =
        await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    return r[Permission.bluetoothConnect]?.isGranted ?? false;
  }

  static Future<bool> isConnected() async {
    if (!await askPermission()) return false;
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  static Future<List<BluetoothInfo>> paired() async {
    await askPermission();
    return PrintBluetoothThermal.pairedBluetooths;
  }

  static Future<bool> connect(String mac) =>
      PrintBluetoothThermal.connect(macPrinterAddress: mac);

  static Future<bool> ensure() async {
    if (await isConnected()) return true;
    final mac = await Db.getSetting('printer_mac');
    if (mac == null || mac.isEmpty) return false;
    return connect(mac);
  }

  static String _lr(String l, String r, int w) {
    final sp = w - l.length - r.length;
    if (sp >= 1) return l + ' ' * sp + r;
    final cut = (w - r.length - 1).clamp(0, w).toInt();
    return '${l.substring(0, cut.clamp(0, l.length).toInt())} $r';
  }

  static Future<List<int>> build(Rec t) async {
    final paper = await Db.getSetting('paper') ?? '58';
    final w = paper == '80' ? 48 : 32;
    final g = Generator(paper == '80' ? PaperSize.mm80 : PaperSize.mm58,
        await CapabilityProfile.load());
    // nama & alamat nota mengikuti outlet tempat transaksi dibuat
    final nc = await NotaCfg.get('${t['outlet'] ?? ''}');
    final name = nc['name']!.isEmpty ? 'Outlet' : nc['name']!;
    final addr = nc['addr']!;
    const center = PosStyles(align: PosAlign.center);
    List<int> b = [];
    b += g.reset();
    b += g.text(name,
        styles: const PosStyles(align: PosAlign.center, bold: true));
    if (addr.isNotEmpty) b += g.text(addr, styles: center);
    b += g.hr();
    b += g.text(_lr(t['code'] as String, fmtDt(t['created_at'] as String), w));
    b += g.text('Kasir: ${t['user_name']}');
    b += g.hr();
    for (final i in (t['items'] as List)) {
      final m = i as Map;
      b += g.text('${m['product_name']}${kemTag(m['kemasan'] as String?)}');
      final cat = (m['note'] ?? '').toString().trim();
      if (cat.isNotEmpty) b += g.text('Catatan: $cat');
      b += g.text(_lr('${m['qty']} x ${rp(m['price'] as num)}',
          rp(m['subtotal'] as num), w));
    }
    b += g.hr();
    b += g.text(_lr('Subtotal', rp(t['subtotal'] as num), w));
    if ((t['discount_amt'] as num) > 0) {
      b += g.text(_lr('Diskon ${t['discount_pct']}%',
          '-${rp(t['discount_amt'] as num)}', w));
    }
    b += g.text(_lr('TOTAL', rp(t['total'] as num), w),
        styles: const PosStyles(bold: true));
    if (t['payment'] == 'QRIS') {
      b += g.text(_lr('Bayar QRIS', rp(t['total'] as num), w));
    } else {
      b += g.text(_lr('Tunai', rp(t['cash'] as num), w));
      b += g.text(_lr('Kembali', rp(t['change_amt'] as num), w));
      if (jajanOf(t) > 0) {
        b += g.text(_lr('Jajan ${rp(kJajanPrice)} x ${jajanOf(t)}',
            rp(jajanOf(t) * kJajanPrice), w));
        b += g.text(_lr('Kembali uang',
            rp((t['change_amt'] as num) - jajanOf(t) * kJajanPrice), w));
      }
    }
    b += g.hr();
    b += g.feed(3);
    return b;
  }

  /// Slip pesanan (tanpa harga) untuk dapur / penyiapan.
  static Future<List<int>> buildOrder(Rec t) async {
    final paper = await Db.getSetting('paper') ?? '58';
    final g = Generator(paper == '80' ? PaperSize.mm80 : PaperSize.mm58,
        await CapabilityProfile.load());
    List<int> b = [];
    b += g.reset();
    b += g.text('PESANAN',
        styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2));
    b += g.text(t['code'] as String,
        styles: const PosStyles(align: PosAlign.center));
    b += g.text(fmtDt(t['created_at'] as String),
        styles: const PosStyles(align: PosAlign.center));
    b += g.hr();
    for (final i in (t['items'] as List)) {
      final m = i as Map;
      b += g.text('${m['qty']}x ${m['product_name']}',
          styles: const PosStyles(bold: true, height: PosTextSize.size2));
      if (!noKem(m['kemasan'] as String?)) {
        b += g.text('   (${m['kemasan']})');
      }
      final cat = (m['note'] ?? '').toString().trim();
      if (cat.isNotEmpty) b += g.text('   Catatan: $cat');
    }
    b += g.hr();
    b += g.feed(3);
    return b;
  }

  static Future<bool> printOrder(Rec t) async {
    if (!await ensure()) return false;
    return PrintBluetoothThermal.writeBytes(await buildOrder(t));
  }

  /// Teks struk untuk disalin / dikirim lewat WhatsApp.
  static Future<String> receiptText(Rec t) async {
    final nc = await NotaCfg.get('${t['outlet'] ?? ''}');
    final name = nc['name']!.isEmpty ? 'Outlet' : nc['name']!;
    final sb = StringBuffer()
      ..writeln(name)
      ..writeln('${t['code']}  ${fmtDt(t['created_at'] as String)}')
      ..writeln('Kasir: ${t['user_name']}')
      ..writeln('');
    for (final i in (t['items'] as List)) {
      final m = i as Map;
      sb.writeln(
          '${m['qty']}x ${m['product_name']}${kemTag(m['kemasan'] as String?)}  ${rp(m['subtotal'] as num)}');
      final cat = (m['note'] ?? '').toString().trim();
      if (cat.isNotEmpty) sb.writeln('   Catatan: $cat');
    }
    sb.writeln('');
    sb.writeln('Subtotal: ${rp(t['subtotal'] as num)}');
    if ((t['discount_amt'] as num) > 0) {
      sb.writeln(
          'Diskon ${t['discount_pct']}%: -${rp(t['discount_amt'] as num)}');
    }
    sb.writeln('TOTAL: ${rp(t['total'] as num)}');
    if (t['payment'] == 'QRIS') {
      sb.writeln('Bayar QRIS: ${rp(t['total'] as num)}');
    } else {
      sb
        ..writeln('Tunai: ${rp(t['cash'] as num)}')
        ..writeln('Kembali: ${rp(t['change_amt'] as num)}');
      if (jajanOf(t) > 0) {
        sb
          ..writeln(
              'Jajan $kJajanPrice x ${jajanOf(t)}: ${rp(jajanOf(t) * kJajanPrice)}')
          ..writeln(
              'Kembali uang: ${rp((t['change_amt'] as num) - jajanOf(t) * kJajanPrice)}');
      }
    }
    return sb.toString().trimRight();
  }

  static Future<bool> printTrx(Rec t) async {
    if (!await ensure()) return false;
    return PrintBluetoothThermal.writeBytes(await build(t));
  }

  static Future<bool> printTest() async {
    if (!await ensure()) return false;
    final paper = await Db.getSetting('paper') ?? '58';
    final g = Generator(paper == '80' ? PaperSize.mm80 : PaperSize.mm58,
        await CapabilityProfile.load());
    List<int> b = [];
    b += g.reset();
    b += g.text('Printer aman boskuh',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.feed(3);
    return PrintBluetoothThermal.writeBytes(b);
  }
}
