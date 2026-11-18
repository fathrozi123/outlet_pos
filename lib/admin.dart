import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'attendance_photo.dart';
import 'db.dart';
import 'excel_export.dart';
import 'nota.dart';
import 'product_image.dart';
import 'rekapitulasi.dart';
import 'scope.dart';
import 'target.dart';

/// Gaya tombol terisi di halaman admin: latar putih, teks merah.
final _kBtnPutih = FilledButton.styleFrom(
  backgroundColor: Colors.white,
  foregroundColor: Color(0xFF97291F),
  side: const BorderSide(color: Color(0xFF97291F)),
);

const _periods = {'Harian': 10, 'Bulanan': 7, 'Tahunan': 4};
String _now(int len) => DateTime.now().toIso8601String().substring(0, len);

Widget _title(BuildContext c, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(t, style: Theme.of(c).textTheme.titleLarge));

Widget _note(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(t, style: const TextStyle(fontSize: 12)));

Widget _bar(String label, num v, num max, String trailing) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text(trailing, style: const TextStyle(fontWeight: FontWeight.bold))
        ]),
        const SizedBox(height: 3),
        LinearProgressIndicator(
            value: max == 0 ? 0 : (v / max).toDouble(),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4)),
      ]),
    );

class _PeriodBar extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _PeriodBar(this.value, this.onChanged);
  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
        style: SegmentedButton.styleFrom(
          foregroundColor: Color(0xFF97291F),
          selectedForegroundColor: Color(0xFF97291F),
          backgroundColor: Colors.white,
          selectedBackgroundColor: const Color(0xFFF6E1DF),
          side: const BorderSide(color: Color(0xFF97291F)),
        ),
        showSelectedIcon: false,
        segments: [
          for (final k in _periods.keys) ButtonSegment(value: k, label: Text(k))
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

class _Q extends StatelessWidget {
  final Future<List<Rec>> f;
  final Widget Function(List<Rec>) b;
  const _Q(this.f, this.b);
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Rec>>(
        future: f,
        builder: (c, s) => s.hasData
            ? b(s.data!)
            : const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator())),
      );
}

// ===================== DASHBOARD ADMIN =====================
// Mengikuti outlet yang dipilih di bilah atas (AdminScope).
const _bulanId = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember'
];

/// Pemberitahuan merah di Dashboard Mitra: menyebut outlet mana yang masa
/// langganannya tinggal 1 bulan atau kurang, dan outlet yang sudah berakhir
/// (terkunci). Tidak tampil kalau semua outlet masih lama / tidak berlangganan.
class SubscriptionNotice extends StatelessWidget {
  const SubscriptionNotice({super.key});

  static Future<List<Rec>> _load() async {
    await Db.ensureV3();
    return Db.q(
        'SELECT name, sub_required, sub_until FROM outlets WHERE owner_id=? ORDER BY name',
        [Session.id]);
  }

  static String _tgl(String iso) {
    final d = DateTime.parse(iso);
    return '${d.day} ${_bulanId[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (!Session.isMitra) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: Session.tick,
      builder: (c, _, __) => FutureBuilder<List<Rec>>(
        future: _load(),
        builder: (c, snap) {
          final rows = snap.data ?? const <Rec>[];
          final warn =
              <MapEntry<Rec, int>>[]; // outlet hampir habis + sisa hari
          final ended = <Rec>[]; // outlet sudah berakhir / belum diaktifkan
          for (final o in rows) {
            final d = outletSubWarnDays(o);
            if (d != null) {
              warn.add(MapEntry(o, d));
            } else if (outletSubLock(o) != null) {
              ended.add(o);
            }
          }
          if (warn.isEmpty && ended.isEmpty) return const SizedBox.shrink();
          warn.sort((a, b) => a.value.compareTo(b.value));
          const merah = Color(0xFF97291F);
          const base = TextStyle(color: merah, height: 1.4);
          Widget bullet(String nama, String ket) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text.rich(TextSpan(style: base, children: [
                  const TextSpan(text: '• '),
                  TextSpan(
                      text: nama,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: ' — $ket'),
                ])),
              );
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9E8E6),
                border: Border.all(color: merah),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, color: merah, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Pemberitahuan Masa Langganan Outlet',
                            style: TextStyle(
                                color: merah,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        const SizedBox(height: 6),
                        Text('Yth. ${Session.name},', style: base),
                        const SizedBox(height: 4),
                        if (warn.isNotEmpty) ...[
                          const Text(
                              'Masa langganan outlet berikut akan segera berakhir:',
                              style: base),
                          for (final w in warn)
                            bullet(
                                w.key['name'] as String,
                                'berakhir ${_tgl(w.key['sub_until'] as String)} '
                                '(${w.value == 0 ? 'hari ini' : w.value == 1 ? 'besok' : '${w.value} hari lagi'})'),
                        ],
                        if (ended.isNotEmpty) ...[
                          if (warn.isNotEmpty) const SizedBox(height: 6),
                          const Text(
                              'Outlet berikut sudah tidak aktif (terkunci) karena langganannya berakhir:',
                              style: base),
                          for (final o in ended)
                            bullet(
                                o['name'] as String,
                                ((o['sub_until'] ?? '') as String).isEmpty
                                    ? 'langganan belum diaktifkan'
                                    : 'berakhir ${_tgl(o['sub_until'] as String)}'),
                        ],
                        const SizedBox(height: 6),
                        const Text(
                            'Agar outlet tetap aktif dan tidak terkunci, mohon '
                            'berkenan menghubungi Develop untuk melakukan '
                            'perpanjangan langganan.',
                            style: base),
                        const SizedBox(height: 4),
                        const Text(
                            'Terima kasih atas perhatian dan kepercayaan Anda.',
                            style: base),
                      ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  // Bawaan: HARI INI. Kartu penjualan, transaksi, modal, dan beban mengikuti
  // rentang tanggal yang dipilih (mis. 1-7); kartu bulan ini tetap bulan berjalan.
  DateTimeRange? picked; // null = hari ini (ikut tanggal berjalan)

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  Widget _stat(String label, String v, IconData i, {bool green = false}) {
    final cs = Theme.of(context).colorScheme;
    final fg = green ? Colors.white : const Color(0xFF2B1B1B);
    return Container(
      width: 175,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: green ? Colors.green.shade700 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: green
              ? Colors.transparent
              : cs.outlineVariant.withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: green
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: green
                ? Colors.white.withValues(alpha: 0.2)
                : cs.primaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(i, size: 20, color: green ? Colors.white : cs.primary),
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(v,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: green ? Colors.white70 : cs.outline,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }

  static String _dm(DateTime d) =>
      _iso(d).substring(5).split('-').reversed.join('/');

  String _rangeText(DateTimeRange r) => _iso(r.start) == _iso(r.end)
      ? _iso(r.start)
      : '${_dm(r.start)} - ${_dm(r.end)}';

  Widget _dateBar() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          if (picked != null)
            TextButton(
                onPressed: () => setState(() => picked = null),
                child: const Text('Hari ini')),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(picked == null ? 'Hari ini' : _rangeText(picked!)),
            onPressed: () async {
              final now = DateTime.now();
              final r = await showDateRangePicker(
                  context: context,
                  initialDateRange:
                      picked ?? DateTimeRange(start: now, end: now),
                  firstDate: DateTime(2024),
                  lastDate: now,
                  helpText: 'Pilih rentang tanggal',
                  saveText: 'Terapkan');
              if (r != null) {
                final today = _iso(now);
                setState(() => picked =
                    _iso(r.start) == today && _iso(r.end) == today ? null : r);
              }
            },
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final da = picked?.start ?? now, db = picked?.end ?? now;
    final ta = _iso(da), tb = _iso(db), mo = _now(7);
    final lbl = picked == null ? 'hari ini' : _rangeText(picked!);
    final o = AdminScope.value;
    final oa = Scope.args; // mitra: hanya outlet miliknya
    final oc = Scope.and('outlet');
    final fut = Future.wait([
      Db.q(
          'SELECT COALESCE(SUM(total),0) t, COUNT(*) n FROM transactions WHERE substr(created_at,1,10) BETWEEN ? AND ?$oc',
          [ta, tb, ...oa]),
      Db.q(
          'SELECT COALESCE(SUM(total),0) t, COUNT(*) n FROM transactions WHERE substr(created_at,1,7)=?$oc',
          [mo, ...oa]),
      Db.q(
          'SELECT substr(created_at,1,10) p, SUM(total) t FROM transactions ${Scope.where('outlet')} GROUP BY p ORDER BY p DESC LIMIT 7',
          oa),
      Db.q(
          "SELECT outlet, COUNT(*) n, SUM(total) t FROM transactions WHERE substr(created_at,1,7)=?$oc GROUP BY outlet ORDER BY t DESC",
          [mo, ...oa]),
      Db.q(
          'SELECT product_name, SUM(qty) q FROM transaction_items WHERE trx_id IN (SELECT id FROM transactions WHERE substr(created_at,1,7)=?$oc) GROUP BY product_name ORDER BY q DESC LIMIT 5',
          [mo, ...oa]),
      Rekap.recap(da, db), // modal & beban dari Rekapitulasi (rentang dipilih)
      // penjualan bulan ini per kelompok (Outlet Pusat / tiap Mitra)
      (() async {
        await Db.ensureV3();
        return Db.q(
            "SELECT COALESCE(g.name,'Tanpa kelompok') AS grp, COUNT(*) n, COALESCE(SUM(t.total),0) t FROM transactions t LEFT JOIN outlets o ON o.name=t.outlet LEFT JOIN outlet_groups g ON g.id=o.group_id WHERE substr(t.created_at,1,7)=?${Scope.and('t.outlet')} GROUP BY grp ORDER BY t DESC",
            [mo, ...oa]);
      })(),
    ]);
    final gl = Scope.groupLabel;
    final judul = o.isEmpty
        ? (gl.isNotEmpty
            ? 'Dashboard — $gl'
            : Scope.restricted
                ? 'Dashboard — Analisis Penjualan Outlet Saya'
                : 'Dashboard — Analisis Penjualan Semua Toko')
        : 'Dashboard — $o';
    return FutureBuilder<List<List<Rec>>>(
      future: fut,
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final d = s.data!;
        final days = d[2];
        final maxDay = days.fold<num>(
            0, (a, e) => (e['t'] as num) > a ? e['t'] as num : a);
        final outlets = d[3];
        final maxOut = outlets.fold<num>(
            0, (a, e) => (e['t'] as num) > a ? e['t'] as num : a);
        final top = d[4];
        final rc = d[5][0];
        final grp = d[6];
        final maxGrp =
            grp.fold<num>(0, (a, e) => (e['t'] as num) > a ? e['t'] as num : a);
        final maxTop =
            top.fold<num>(0, (a, e) => (e['q'] as num) > a ? e['q'] as num : a);
        return ListView(padding: const EdgeInsets.all(16), children: [
          const SubscriptionNotice(),
          _title(c, judul),
          _dateBar(),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _stat('Penjualan $lbl', rp(d[0][0]['t'] as num), Icons.today),
            _stat('Transaksi $lbl', '${d[0][0]['n']}', Icons.receipt),
            _stat('Modal $lbl', rp(rc['modal'] as num),
                Icons.account_balance_wallet),
            _stat('Beban $lbl', rp(rc['beban'] as num), Icons.request_quote),
            _stat('Penjualan bulan ini', rp(d[1][0]['t'] as num),
                Icons.calendar_month,
                green: true),
            _stat('Transaksi bulan ini', '${d[1][0]['n']}', Icons.shopping_bag,
                green: true),
          ]),
          if (o.isNotEmpty) ...[
            const SizedBox(height: 20),
            TargetCard(outlet: o),
          ],
          const SizedBox(height: 20),
          Text('7 hari terakhir', style: Theme.of(c).textTheme.titleMedium),
          for (final e in days)
            _bar(e['p'] as String, e['t'] as num, maxDay, rp(e['t'] as num)),
          if (o.isEmpty &&
              AdminScope.groupId == 0 &&
              Scope.groups.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Penjualan per kelompok (bulan ini)',
                style: Theme.of(c).textTheme.titleMedium),
            for (final e in grp)
              _bar('${e['grp']} (${e['n']} transaksi)', e['t'] as num, maxGrp,
                  rp(e['t'] as num)),
          ],
          if (o.isEmpty) ...[
            const SizedBox(height: 20),
            Text('Penjualan per toko (bulan ini)',
                style: Theme.of(c).textTheme.titleMedium),
            for (final e in outlets)
              _bar('${e['outlet']} (${e['n']} transaksi)', e['t'] as num,
                  maxOut, rp(e['t'] as num)),
          ],
          const SizedBox(height: 20),
          Text('5 produk terlaris (bulan ini)',
              style: Theme.of(c).textTheme.titleMedium),
          for (final e in top)
            _bar(e['product_name'] as String, e['q'] as num, maxTop,
                '${e['q']} pcs'),
        ]);
      },
    );
  }
}

// ===================== LAPORAN: RINGKASAN PENJUALAN (gaya Qasir) =====================
// Rumus:  Total Pendapatan Kotor = Penjualan Kotor - Diskon
//         Total Pendapatan Bersih = Penjualan Kotor - Diskon - Modal (%) - Beban
//   Modal (Rp) = Total Pendapatan Kotor x Modal (%) per outlet.
//   Modal (%) dan Beban diatur di menu Rekapitulasi.
//   Penjualan Kotor = jumlah subtotal semua transaksi (sebelum diskon)
//   Diskon          = jumlah potongan diskon semua transaksi
//   Rata-rata       = Total Pendapatan Kotor / Jumlah Transaksi
Widget _sumRow(String label, String value, {bool bold = false, Color? color}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(label,
                style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
        const SizedBox(width: 12),
        Text(value,
            style: TextStyle(
                fontWeight: bold ? FontWeight.bold : null, color: color)),
      ]),
    );

class ReportSummary extends StatefulWidget {
  const ReportSummary({super.key});
  @override
  State<ReportSummary> createState() => _ReportSummaryState();
}

class _ReportSummaryState extends State<ReportSummary> {
  DateTimeRange range = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 7)),
      end: DateTime.now());
  // Mengikuti outlet yang dipilih di bilah atas ('' = semua outlet)
  final String outlet = AdminScope.value;
  String per = 'Harian';
  Future<List<List<Rec>>>? fut;
  String _text = '';
  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  void _load() {
    final len = _periods[per]!;
    final args = <Object?>[_iso(range.start), _iso(range.end)];
    var w = 'substr(created_at,1,10) BETWEEN ? AND ?';
    w += Scope.and('outlet'); // mitra: hanya outlet miliknya
    args.addAll(Scope.args);
    fut = Future.wait([
      Db.q(
          'SELECT COUNT(*) n, COALESCE(SUM(subtotal),0) kotor, COALESCE(SUM(discount_amt),0) diskon, COALESCE(SUM(total),0) bersih FROM transactions WHERE $w',
          args),
      Db.q(
          'SELECT substr(created_at,1,$len) p, COUNT(*) n, SUM(total) t FROM transactions WHERE $w GROUP BY p ORDER BY p DESC',
          args),
      Rekap.recap(range.start, range.end),
    ]);
  }

  void _setRange(DateTime a, DateTime b) => setState(() {
        range = DateTimeRange(start: a, end: b);
        _load();
      });

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: DateTime.now(),
        initialDateRange: range);
    if (r != null) _setRange(r.start, r.end);
  }

  Future<void> _export({
    required int count,
    required num kotor,
    required num diskon,
    required num bersih,
    required num modal,
    required num beban,
    required num pendapatan,
    required List<Rec> periods,
  }) async {
    try {
      final rangeTxt =
          '${_fmt.format(range.start)} - ${_fmt.format(range.end)}';
      if (!mounted) return;
      await shareExcel(
        context: context,
        title: 'Ringkasan Penjualan',
        fileName: 'ringkasan_penjualan_${_iso(range.start)}_${_iso(range.end)}',
        sheets: {
          'Laporan Penjualan': [
            ['Ringkasan Penjualan', 'Nilai'],
            ['Outlet', outlet.isEmpty ? 'Semua Toko' : outlet],
            ['Periode', rangeTxt],
            ['Penjualan Kotor', kotor],
            ['Diskon', diskon],
            ['Total Pendapatan Kotor', bersih],
            ['Modal', modal],
            ['Beban', beban],
            ['Total Pendapatan Bersih', pendapatan],
            ['Jumlah Transaksi', count],
            [
              'Rata-rata per Transaksi',
              count == 0 ? 0 : (bersih / count).round()
            ],
          ],
          'Tren Penjualan': [
            ['Periode', 'Jumlah Transaksi', 'Penjualan Bersih'],
            for (final e in periods) [e['p'], e['n'], e['t']],
          ],
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Laporan dan tren penjualan siap dibagikan')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    if (fut == null) _load(); // aman setelah hot reload
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF97291F),
        shape: const StadiumBorder(side: BorderSide(color: Color(0xFF97291F))),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: _text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ringkasan disalin')));
          }
        },
        icon: const Icon(Icons.copy),
        label: const Text('Salin Ringkasan'),
      ),
      body: FutureBuilder<List<List<Rec>>>(
        future: fut,
        builder: (c, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final r = d[0][0];
          final n = r['n'] as int;
          final kotor = r['kotor'] as num,
              diskon = r['diskon'] as num,
              bersih = r['bersih'] as num;
          final rows = d[1];
          final modal = d[2][0]['modal'] as num,
              beban = d[2][0]['beban'] as num;
          final pendapatan = bersih - modal - beban;
          final max = rows.fold<num>(
              0, (a, e) => (e['t'] as num) > a ? e['t'] as num : a);
          final rangeTxt =
              '${_fmt.format(range.start)} - ${_fmt.format(range.end)}';
          _text =
              'Ringkasan Penjualan\n${outlet.isEmpty ? 'Semua Toko' : outlet}\n$rangeTxt\n\n'
              'Penjualan Kotor: ${rp(kotor)}\nDiskon: -${rp(diskon)}\nTotal Pendapatan Kotor: ${rp(bersih)}\n'
              'Modal: -${rp(modal)}\nBeban: -${rp(beban)}\nTotal Pendapatan Bersih: ${rp(pendapatan)}\n'
              'Jumlah Transaksi: $n\nRata-rata per Transaksi: ${rp(n == 0 ? 0 : (bersih / n).round())}';

          return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        'Ringkasan Penjualan${outlet.isEmpty ? '' : ' • $outlet'}',
                        style: Theme.of(c).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _export(
                        count: n,
                        kotor: kotor,
                        diskon: diskon,
                        bersih: bersih,
                        modal: modal,
                        beban: beban,
                        pendapatan: pendapatan,
                        periods: rows,
                      ),
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text('Ekspor Excel'),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(outlet.isEmpty ? 'Semua Outlet' : outlet,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: cs.primary)),
                ),
                InkWell(
                  onTap: _pickRange,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_month)),
                    child: Text(rangeTxt),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  ActionChip(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF97291F)),
                      labelStyle: const TextStyle(
                          color: Color(0xFF97291F),
                          fontWeight: FontWeight.w600),
                      label: const Text('Hari ini'),
                      onPressed: () => _setRange(now, now)),
                  ActionChip(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF97291F)),
                      labelStyle: const TextStyle(
                          color: Color(0xFF97291F),
                          fontWeight: FontWeight.w600),
                      label: const Text('7 hari'),
                      onPressed: () => _setRange(
                          now.subtract(const Duration(days: 6)), now)),
                  ActionChip(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF97291F)),
                      labelStyle: const TextStyle(
                          color: Color(0xFF97291F),
                          fontWeight: FontWeight.w600),
                      label: const Text('Bulan ini'),
                      onPressed: () =>
                          _setRange(DateTime(now.year, now.month, 1), now)),
                  ActionChip(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF97291F)),
                      labelStyle: const TextStyle(
                          color: Color(0xFF97291F),
                          fontWeight: FontWeight.w600),
                      label: const Text('Tahun ini'),
                      onPressed: () =>
                          _setRange(DateTime(now.year, 1, 1), now)),
                ]),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Penjualan',
                              style: Theme.of(c)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Penjualan Kotor - Diskon - Modal - Beban',
                              style: TextStyle(color: cs.outline)),
                          const SizedBox(height: 8),
                          _sumRow('Penjualan Kotor', rp(kotor)),
                          const Divider(height: 1),
                          _sumRow('Diskon', '-${rp(diskon)}',
                              color: diskon > 0 ? Color(0xFF97291F) : null),
                          const Divider(height: 1),
                          _sumRow('Total Pendapatan Kotor', rp(bersih),
                              bold: true),
                          const Divider(height: 1),
                          _sumRow('Modal', '-${rp(modal)}',
                              color: modal > 0 ? Color(0xFF97291F) : null),
                          const Divider(height: 1),
                          _sumRow('Beban', '-${rp(beban)}',
                              color: beban > 0 ? Color(0xFF97291F) : null),
                          const Divider(height: 1),
                          _sumRow('Total Pendapatan Bersih', rp(pendapatan),
                              bold: true,
                              color: pendapatan < 0 ? Color(0xFF97291F) : null),
                          const Divider(height: 1),
                          _sumRow('Jumlah Transaksi', '$n'),
                          const Divider(height: 1),
                          _sumRow('Rata-rata per Transaksi',
                              rp(n == 0 ? 0 : (bersih / n).round())),
                        ]),
                  ),
                ),
                const SizedBox(height: 20),
                _SalesBarChart(outlet: outlet),
                const SizedBox(height: 20),
                Text('Rincian penjualan bersih',
                    style: Theme.of(c).textTheme.titleMedium),
                const SizedBox(height: 8),
                _PeriodBar(
                    per,
                    (v) => setState(() {
                          per = v;
                          _load();
                        })),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Belum ada transaksi pada rentang ini')),
                for (final e in rows)
                  _bar('${e['p']} • ${e['n']} transaksi', e['t'] as num, max,
                      rp(e['t'] as num)),
              ]);
        },
      ),
    );
  }
}

// ===================== GRAFIK BAR PENJUALAN =====================
// Pilihan rentang: 1/3/6 bulan, 1/3/5 tahun, atau Semua. Pengelompokan batang
// menyesuaikan rentang (harian, mingguan, bulanan, kuartal, tahunan).
const _chartRanges = {
  '1 Bulan': 1,
  '3 Bulan': 3,
  '6 Bulan': 6,
  '1 Tahun': 12,
  '3 Tahun': 36,
  '5 Tahun': 60,
  'Semua': 0,
};
const _mNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des'
];
const _modeName = {
  'day': 'hari',
  'week': 'minggu',
  'month': 'bulan',
  'quarter': 'kuartal',
  'year': 'tahun'
};

class _Bucket {
  final String label, full;
  num t = 0;
  int n = 0;
  _Bucket(this.label, this.full);
}

class _ChartData {
  final List<_Bucket> buckets;
  final String mode;
  _ChartData(this.buckets, this.mode);
}

String _short(num v) {
  String f(double x) => x
      .toStringAsFixed(x >= 10 ? 0 : 1)
      .replaceAll('.', ',')
      .replaceAll(RegExp(r',0$'), '');
  if (v >= 1e9) return '${f(v / 1e9)} M';
  if (v >= 1e6) return '${f(v / 1e6)} jt';
  if (v >= 1e3) return '${f(v / 1e3)} rb';
  return '${v.round()}';
}

class _SalesBarChart extends StatefulWidget {
  final String outlet; // '' = semua outlet
  const _SalesBarChart({required this.outlet});
  @override
  State<_SalesBarChart> createState() => _SalesBarChartState();
}

class _SalesBarChartState extends State<_SalesBarChart> {
  String range = '1 Bulan';
  late Future<_ChartData> fut = _load();
  final _sc = ScrollController();
  _ChartData? _last;

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static DateTime _monday(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  Future<void> _export(_ChartData data) async {
    try {
      final total = data.buckets.fold<num>(0, (sum, b) => sum + b.t);
      final count = data.buckets.fold<int>(0, (sum, b) => sum + b.n);
      if (!mounted) return;
      await shareExcel(
        context: context,
        title: 'Tren Penjualan',
        fileName:
            'tren_penjualan_${range.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}',
        sheets: {
          'Tren Penjualan': [
            ['Tren Penjualan', 'Nilai'],
            ['Outlet', widget.outlet.isEmpty ? 'Semua Toko' : widget.outlet],
            ['Rentang Grafik', range],
            ['Pengelompokan', _modeName[data.mode] ?? data.mode],
            ['Total Penjualan', total],
            ['Jumlah Transaksi', count],
            [],
            ['Periode', 'Jumlah Transaksi', 'Penjualan Bersih'],
            for (final b in data.buckets) [b.full, b.n, b.t],
          ],
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ekspor tren penjualan siap dibagikan')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
      }
    }
  }

  Future<void> _exportSelected() async {
    try {
      final data = await fut;
      if (mounted) await _export(data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal memuat tren: $e')));
      }
    }
  }

  Future<_ChartData> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final oa = Scope.args; // mitra: hanya outlet miliknya
    final months = _chartRanges[range]!;

    DateTime start;
    if (months == 0) {
      final r = await Db.q(
          'SELECT MIN(substr(created_at,1,10)) m FROM transactions ${Scope.where('outlet')}',
          oa);
      final m = r.first['m'] as String?;
      if (m == null) return _ChartData([], 'month');
      start = DateTime.parse(m);
    } else {
      final tm = today.month - months;
      final last =
          DateTime(today.year, tm + 1, 0).day; // hari terakhir bulan tujuan
      final d = today.day < last ? today.day : last;
      start = DateTime(today.year, tm, d).add(const Duration(days: 1));
    }

    final span = today.difference(start).inDays;
    final String mode;
    if (months == 0) {
      mode = span <= 62
          ? 'day'
          : span <= 400
              ? 'month'
              : span <= 1200
                  ? 'quarter'
                  : 'year';
    } else if (months == 1) {
      mode = 'day';
    } else if (months == 3) {
      mode = 'week';
    } else if (months <= 12) {
      mode = 'month';
    } else if (months == 36) {
      mode = 'quarter';
    } else {
      mode = 'year';
    }

    String key(DateTime d) {
      if (mode == 'day') return _iso(d);
      if (mode == 'week') return _iso(_monday(d));
      if (mode == 'month') return '${d.year}-${_two(d.month)}';
      if (mode == 'quarter') return '${d.year}-Q${(d.month - 1) ~/ 3 + 1}';
      return '${d.year}';
    }

    DateTime cur;
    if (mode == 'day') {
      cur = start;
    } else if (mode == 'week') {
      cur = _monday(start);
    } else if (mode == 'month') {
      cur = DateTime(start.year, start.month, 1);
    } else if (mode == 'quarter') {
      cur = DateTime(start.year, (start.month - 1) ~/ 3 * 3 + 1, 1);
    } else {
      cur = DateTime(start.year, 1, 1);
    }

    final map = <String, _Bucket>{};
    final list = <_Bucket>[];
    while (!cur.isAfter(today)) {
      final yy = _two(cur.year % 100);
      final q = (cur.month - 1) ~/ 3 + 1;
      final String label, full;
      if (mode == 'day') {
        label = '${_two(cur.day)}/${_two(cur.month)}';
        full = '$label/${cur.year}';
      } else if (mode == 'week') {
        label = '${_two(cur.day)}/${_two(cur.month)}';
        full = 'Minggu mulai $label/${cur.year}';
      } else if (mode == 'month') {
        label = '${_mNames[cur.month - 1]} $yy';
        full = '${_mNames[cur.month - 1]} ${cur.year}';
      } else if (mode == 'quarter') {
        label = 'Q$q $yy';
        full = 'Kuartal $q ${cur.year}';
      } else {
        label = '${cur.year}';
        full = label;
      }
      final b = _Bucket(label, full);
      map[key(cur)] = b;
      list.add(b);
      if (mode == 'day') {
        cur = DateTime(cur.year, cur.month, cur.day + 1);
      } else if (mode == 'week') {
        cur = DateTime(cur.year, cur.month, cur.day + 7);
      } else if (mode == 'month') {
        cur = DateTime(cur.year, cur.month + 1, 1);
      } else if (mode == 'quarter') {
        cur = DateTime(cur.year, cur.month + 3, 1);
      } else {
        cur = DateTime(cur.year + 1, 1, 1);
      }
    }

    final rows = await Db.q(
        'SELECT substr(created_at,1,10) d, SUM(total) t, COUNT(*) n FROM transactions WHERE substr(created_at,1,10) >= ?${Scope.and('outlet')} GROUP BY d',
        [_iso(start), ...oa]);
    for (final r in rows) {
      final b = map[key(DateTime.parse(r['d'] as String))];
      if (b == null) continue;
      b.t += r['t'] as num;
      b.n += r['n'] as int;
    }
    return _ChartData(list, mode);
  }

  Widget _chart(_ChartData d) {
    final cs = Theme.of(context).colorScheme;
    final bs = d.buckets;
    final maxV = bs.fold<num>(0, (a, e) => e.t > a ? e.t : a);
    const barArea = 170.0;
    final minSlot = d.mode == 'day' ? 30.0 : 48.0;
    return LayoutBuilder(builder: (c, cons) {
      final fill = cons.maxWidth / bs.length;
      final slot = fill > minSlot ? fill : minSlot;
      final showVal = slot >= 44;
      return SingleChildScrollView(
        controller: _sc,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: slot * bs.length,
          height: barArea + 44,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final b in bs)
              SizedBox(
                width: slot,
                child: Tooltip(
                  triggerMode: TooltipTriggerMode.tap,
                  message: '${b.full}\n${rp(b.t)} • ${b.n} transaksi',
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (showVal && b.t > 0)
                          Text(_short(b.t),
                              style: const TextStyle(fontSize: 10)),
                        const SizedBox(height: 2),
                        Container(
                          width: slot * 0.6 > 34 ? 34 : slot * 0.6,
                          height: (maxV == 0 || b.t <= 0)
                              ? 0.0
                              : (b.t / maxV * barArea)
                                  .clamp(2.0, barArea)
                                  .toDouble(),
                          decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4))),
                        ),
                        const SizedBox(height: 4),
                        Container(height: 1, color: cs.outlineVariant),
                        const SizedBox(height: 4),
                        Text(b.label,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                                fontSize: d.mode == 'day' ? 9 : 10,
                                color: cs.outline)),
                      ]),
                ),
              ),
          ]),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Grafik Penjualan',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _exportSelected,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Ekspor Tren Excel'),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final k in _chartRanges.keys)
              ChoiceChip(
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF97291F)),
                labelStyle: const TextStyle(
                    color: Color(0xFF97291F), fontWeight: FontWeight.w600),
                selectedColor: const Color(0xFFF6E1DF),
                checkmarkColor: Color(0xFF97291F),
                label: Text(k),
                selected: range == k,
                onSelected: (_) => setState(() {
                  range = k;
                  fut = _load();
                }),
              ),
          ]),
          const SizedBox(height: 12),
          FutureBuilder<_ChartData>(
            future: fut,
            builder: (c, snap) {
              if (snap.hasError) return const Text('Gagal memuat grafik');
              if (!snap.hasData) {
                return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()));
              }
              final d = snap.data!;
              final total = d.buckets.fold<num>(0, (a, e) => a + e.t);
              final n = d.buckets.fold<int>(0, (a, e) => a + e.n);
              if (n == 0) {
                return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Belum ada transaksi pada periode ini'));
              }
              if (!identical(_last, d)) {
                _last = d;
                // tampilkan periode terbaru (ujung kanan) lebih dulu
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_sc.hasClients) {
                    _sc.jumpTo(_sc.position.maxScrollExtent);
                  }
                });
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Per ${_modeName[d.mode]} • Total ${rp(total)} • $n transaksi',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline)),
                    const SizedBox(height: 12),
                    _chart(d),
                  ]);
            },
          ),
        ]),
      ),
    );
  }
}

// ===================== LAPORAN: TREN PRODUK =====================
class ReportTrend extends StatefulWidget {
  const ReportTrend({super.key});
  @override
  State<ReportTrend> createState() => _ReportTrendState();
}

class _ReportTrendState extends State<ReportTrend> {
  String per = 'Bulanan';
  bool _exporting = false;

  Future<List<Rec>> _fetchRows(int len) async {
    String t(Object? v) => (v ?? '').toString().trim();
    String kem(Object? v) => noKem(t(v)) ? '' : t(v);
    int n(Object? v) => v is num ? v.toInt() : 0;
    final sold = await Db.q(
        "SELECT i.product_name n, i.kemasan k, SUM(i.qty) q FROM transaction_items i WHERE i.trx_id IN (SELECT id FROM transactions WHERE substr(created_at,1,$len)=?${Scope.and('outlet')}) AND i.product_name IN (SELECT name FROM products WHERE category='utama') GROUP BY i.product_name, i.kemasan",
        [_now(len), ...Scope.args]);
    final all = await Db.q(
        "SELECT p.name n, v.kemasan k FROM variants v JOIN products p ON p.id=v.product_id WHERE p.category='utama'");
    final m = <String, Rec>{};
    Rec row(Rec e) => {'name': t(e['n']), 'kem': kem(e['k']), 'q': 0};
    for (final e in all) {
      m.putIfAbsent('${t(e['n'])}|${kem(e['k'])}', () => row(e));
    }
    for (final e in sold) {
      final r = m.putIfAbsent('${t(e['n'])}|${kem(e['k'])}', () => row(e));
      r['q'] = n(r['q']) + n(e['q']);
    }
    final List<Rec> list = m.values.toList()
      ..sort((a, b) {
        final c = n(b['q']).compareTo(n(a['q']));
        return c != 0 ? c : t(a['name']).compareTo(t(b['name']));
      });
    return list;
  }

  Future<void> _exportExcel() async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final len = _periods[per]!;
      final o = AdminScope.value;
      final rows = await _fetchRows(len);

      // Label periode untuk info sheet
      final periodeLabel = per == 'Harian'
          ? 'Hari ini'
          : per == 'Bulanan'
              ? 'Bulan ini'
              : 'Tahun ini';

      // Baris data: satu baris per produk+kemasan, diurutkan qty desc
      final dataRows = rows
          .map((e) => [
                '${e['name']}',
                (e['kem'] as String).isEmpty ? '-' : '${e['kem']}',
                e['q'] as int,
              ])
          .toList();

      // Hitung total per kemasan untuk sheet ringkasan
      final Map<String, int> totalPerKemasan = {};
      for (final e in rows) {
        final k = (e['kem'] as String).isEmpty ? 'Tanpa Kemasan' : '${e['kem']}';
        totalPerKemasan[k] = (totalPerKemasan[k] ?? 0) + (e['q'] as int);
      }
      final grandTotal = rows.fold<int>(0, (a, e) => a + (e['q'] as int));

      final perLabel = per.toLowerCase().replaceAll(' ', '_');
      final outletLabel = o.isEmpty ? 'semua' : o.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

      await shareExcel(
        title: 'Tren Produk – $periodeLabel',
        fileName: 'tren_produk_${perLabel}_$outletLabel',
        sheets: {
          'Tren Produk': [
            ['Tren Produk', 'Nilai'],
            ['Outlet', o.isEmpty ? 'Semua Outlet' : o],
            ['Periode', periodeLabel],
            ['Total Terjual', grandTotal],
            [],
            ['Produk', 'Kemasan', 'Qty Terjual (pcs)'],
            ...dataRows,
          ],
          'Ringkasan Kemasan': [
            ['Kemasan', 'Total Qty (pcs)'],
            for (final e in totalPerKemasan.entries) [e.key, e.value],
            [],
            ['Grand Total', grandTotal],
          ],
        },
      );

      messenger.showSnackBar(
          const SnackBar(content: Text('Ekspor tren produk siap dibagikan')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final len = _periods[per]!;
    final o = AdminScope.value;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _title(
          context,
          'Tren Produk (${per == 'Harian' ? 'hari ini' : per == 'Bulanan' ? 'bulan ini' : 'tahun ini'})${o.isEmpty ? '' : ' • $o'}'),
      _PeriodBar(per, (v) => setState(() => per = v)),
      const SizedBox(height: 12),
      // Tombol ekspor Excel
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _exporting ? null : _exportExcel,
          icon: _exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.file_download_outlined, size: 18),
          label: Text(_exporting ? 'Mengekspor…' : 'Ekspor Excel'),
        ),
      ),
      const SizedBox(height: 12),
      // Seluruh penjualan per produk per kemasan (mis. Pipa Besar 123,
      // Pipa Normal 223, Pipa Kecil 15). Kemasan yang belum terjual tampil 0.
      _Q(
        _fetchRows(len),
        (rows) {
          if (rows.isEmpty) return const Text('Belum ada produk');
          int n(Object? v) => v is num ? v.toInt() : 0;
          final max =
              rows.fold<int>(0, (a, e) => n(e['q']) > a ? n(e['q']) : a);
          // Tiga kolom: Kecil, Normal, Besar. Kemasan lain / tanpa kemasan
          // masuk "Lainnya" (hanya tampil bila ada penjualannya).
          const sizes = ['Kecil', 'Normal', 'Besar'];
          final groups = <String, List<Rec>>{for (final k in sizes) k: []};
          final other = <Rec>[];
          for (final e in rows) {
            final k = '${e['kem']}';
            (groups[k] ?? other).add(e);
          }
          other.removeWhere((e) => n(e['q']) == 0);
          if (other.isNotEmpty) groups['Lainnya'] = other;

          Widget section(String k, List<Rec> list) {
            final total = list.fold<int>(0, (a, e) => a + n(e['q']));
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('Kemasan $k',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold))),
                        Text('$total pcs',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ]),
                      const Divider(height: 20),
                      if (list.isEmpty)
                        const Text('Belum ada produk')
                      else
                        for (final e in list)
                          _bar('${e['name']}', n(e['q']), max,
                              '${n(e['q'])} pcs'),
                    ]),
              ),
            );
          }

          return LayoutBuilder(builder: (c, cons) {
            final cols = cons.maxWidth >= 720 ? 3 : 1;
            final w = (cons.maxWidth - 12 * (cols - 1)) / cols;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final g in groups.entries)
                SizedBox(width: w, child: section(g.key, g.value)),
            ]);
          });
        },
      ),
    ]);
  }
}

// ===================== LAPORAN: ABSENSI =====================
/// Dikelompokkan per akun pegawai; buka tiap pegawai untuk melihat riwayat
/// absen beserta foto masuk & keluar (ketuk foto untuk memperbesar).
class ReportAttendance extends StatelessWidget {
  const ReportAttendance({super.key});

  Widget _row(BuildContext context, Rec e) {
    final out = e['check_out'] as String?;
    final inAt = e['check_in'] as String;
    String dur = '';
    if (out != null) {
      final d = DateTime.parse(out).difference(DateTime.parse(inAt));
      dur = ' • ${d.inHours}j ${d.inMinutes % 60}m';
    }
    return ListTile(
      dense: true,
      leading: Icon(out == null ? Icons.timer : Icons.check_circle,
          color: out == null ? Colors.orange : Colors.green),
      title: Text('Masuk ${fmtDt(inAt)}'),
      subtitle:
          Text(out == null ? 'Belum check out' : 'Keluar ${fmtDt(out)}$dur'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        AttendancePhoto.chip(context, e['photo_in'] as String?, 'Masuk',
            '${e['name']} • Masuk ${fmtDt(inAt)}'),
        if (out != null)
          AttendancePhoto.chip(context, e['photo_out'] as String?, 'Keluar',
              '${e['name']} • Keluar ${fmtDt(out)}'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = AdminScope.value;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _title(context, 'Laporan Absensi${o.isEmpty ? '' : ' • $o'}'),
      _Q(
        (() async {
          await Db.ensureCols();
          return Db.q(
              'SELECT u.id AS uid, u.name, u.outlet, a.check_in, a.check_out, a.photo_in, a.photo_out FROM attendance a JOIN users u ON u.id=a.user_id ${Scope.where('u.outlet')} ORDER BY a.check_in DESC LIMIT 300',
              Scope.args);
        })(),
        (rows) {
          if (rows.isEmpty) return const Text('Belum ada absensi');
          final byUser = <int, List<Rec>>{};
          for (final e in rows) {
            byUser.putIfAbsent(e['uid'] as int, () => []).add(e);
          }
          return Column(children: [
            for (final list in byUser.values)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  leading: SizedBox(
                    width: 40,
                    height: 40,
                    child: AttendancePhoto.exists(
                            list.first['photo_in'] as String?)
                        ? ClipOval(
                            child: Image.file(
                                File(list.first['photo_in'] as String),
                                fit: BoxFit.cover))
                        : const CircleAvatar(child: Icon(Icons.person)),
                  ),
                  title:
                      Text('${list.first['name']} • ${list.first['outlet']}'),
                  subtitle: Text(
                      '${list.length} absensi • terakhir ${fmtDt(list.first['check_in'] as String)}'),
                  children: [for (final e in list) _row(context, e)],
                ),
              ),
          ]);
        },
      ),
    ]);
  }
}

// ===================== KATALOG PRODUK =====================
// Katalog dan harga berlaku untuk semua outlet (tidak dipisah per outlet).
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  Future<void> _cats() async {
    await showDialog(context: context, builder: (_) => const _CatDialog());
    if (mounted) setState(() {});
  }

  Future<void> _delete(Rec p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Hapus "${p['name']}"?'),
        content: const Text(
            'Produk beserta semua kemasannya akan dihapus. Riwayat transaksi tetap tersimpan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              style: _kBtnPutih,
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    final d = await Db.db;
    await d.transaction((t) async {
      await t.delete('variants', where: 'product_id=?', whereArgs: [p['id']]);
      await t.delete('products', where: 'id=?', whereArgs: [p['id']]);
    });
    await ProductImage.remove(p['image_path'] as String?);
    if (mounted) setState(() {});
  }

  Future<void> _edit(Rec? p) async {
    final name = TextEditingController(text: (p?['name'] as String?) ?? '');
    String cat = (p?['category'] as String?) ?? 'utama';
    bool active = (p?['active'] ?? 1) == 1;
    final String? origImg = p?['image_path'] as String?;
    String? img = origImg;
    final List<Rec> vs = p == null
        ? [
            {'id': null, 'kemasan': 'Normal', 'price': 0}
          ]
        : await Db.q('SELECT * FROM variants WHERE product_id=? ORDER BY price',
            [p['id']]);
    final ctls = [
      for (final v in vs)
        TextEditingController(text: moneyText(v['price'] as int))
    ];
    final cats = await Db.categories();
    if (cats.isNotEmpty && !cats.any((k) => k['key'] == cat)) {
      cat = cats.first['key'] as String;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Future<void> pickImg(ImageSource src, StateSetter set) async {
      try {
        final path = await ProductImage.pick(src);
        if (path == null) return;
        // gambar pilihan sebelumnya yang belum disimpan dibuang
        if (img != null && img != origImg) await ProductImage.remove(img);
        set(() => img = path);
      } catch (e) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Gagal mengambil gambar')));
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(p == null ? 'Tambah Produk' : 'Edit Produk'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 120,
                  height: 120,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12)),
                  child: ProductImage.image(img) ??
                      const Icon(Icons.image_outlined,
                          size: 40, color: Colors.grey),
                ),
                Wrap(alignment: WrapAlignment.center, children: [
                  TextButton.icon(
                      onPressed: () => pickImg(ImageSource.gallery, set),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galeri')),
                  TextButton.icon(
                      onPressed: () => pickImg(ImageSource.camera, set),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Kamera')),
                  if (img != null)
                    TextButton.icon(
                        onPressed: () => set(() => img = null),
                        icon: const Icon(Icons.delete_outline,
                            color: Color(0xFF97291F)),
                        label: const Text('Hapus',
                            style: TextStyle(color: Color(0xFF97291F)))),
                ]),
                const SizedBox(height: 8),
                TextField(
                    controller: name,
                    decoration:
                        const InputDecoration(labelText: 'Nama varian')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: cat,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: [
                    for (final k in cats)
                      DropdownMenuItem(
                          value: k['key'] as String,
                          child: Text(k['name'] as String)),
                  ],
                  onChanged: (v) => set(() => cat = v!),
                ),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aktif dijual'),
                    value: active,
                    onChanged: (v) => set(() => active = v)),
                for (var i = 0; i < vs.length; i++)
                  TextField(
                      controller: ctls[i],
                      keyboardType: TextInputType.number,
                      inputFormatters: [MoneyInputFormatter()],
                      decoration: InputDecoration(
                          labelText: p == null
                              ? 'Harga awal'
                              : noKem(vs[i]['kemasan'] as String?)
                                  ? 'Harga'
                                  : 'Harga kemasan ${vs[i]['kemasan']}',
                          prefixText: 'Rp. ')),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                style: _kBtnPutih,
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) {
      // dibatalkan: buang gambar baru yang belum disimpan
      if (img != origImg) await ProductImage.remove(img);
      return;
    }
    final d = await Db.db;
    if (img != origImg) await ProductImage.remove(origImg);
    if (p == null) {
      final pid = await d.insert('products', {
        'name': name.text.trim(),
        'category': cat,
        'active': active ? 1 : 0,
        'image_path': img
      });
      await d.insert('variants', {
        'product_id': pid,
        'kemasan': cat == 'utama' ? 'Normal' : '',
        'price': moneyOf(ctls[0].text),
        'stock': 0
      });
    } else {
      await d.update(
          'products',
          {
            'name': name.text.trim(),
            'category': cat,
            'active': active ? 1 : 0,
            'image_path': img
          },
          where: 'id=?',
          whereArgs: [p['id']]);
      for (var i = 0; i < vs.length; i++) {
        await d.update('variants', {'price': moneyOf(ctls[i].text)},
            where: 'id=?', whereArgs: [vs[i]['id']]);
      }
    }
    if (mounted) setState(() {});
  }

  /// Produk + ringkasan harga. Topping/kresek hanya harga (tanpa kemasan).
  Future<List<Rec>> _catalogRows() async {
    final ps = await Db.q(
        'SELECT p.*, c.name AS cname FROM products p LEFT JOIN categories c ON c.key=p.category ORDER BY p.category, p.name');
    final vs = await Db.q(
        'SELECT product_id, kemasan, price FROM variants ORDER BY price');
    return [
      for (final p in ps)
        {
          ...p,
          'info': vs
              .where((v) => v['product_id'] == p['id'])
              .map((v) =>
                  '${kemPre(v['kemasan'] as String?)}${rp(v['price'] as num)}')
              .join(' • '),
        }
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF97291F),
            shape:
                const StadiumBorder(side: BorderSide(color: Color(0xFF97291F))),
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add),
            label: const Text('Tambah Produk')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _title(context, 'Katalog Produk'),
          _note(
              'Katalog dan harga berlaku sama untuk semua outlet, jadi tidak berubah saat memilih outlet.'),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
                onPressed: _cats,
                icon: const Icon(Icons.category_outlined),
                label: const Text('Kelola Kategori')),
          ),
          const SizedBox(height: 8),
          _Q(
            _catalogRows(),
            (rows) => Column(children: [
              for (final p in rows)
                Card(
                  child: ListTile(
                    leading: ProductImage.thumb(p['image_path'] as String?) ??
                        Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.image_outlined,
                                color: Colors.grey)),
                    title: Text(
                        '${p['name']}${p['active'] == 1 ? '' : '  (nonaktif)'}'),
                    subtitle: Text(
                        '${p['cname'] ?? p['category']} • ${(p['info'] as String?)?.isNotEmpty == true ? p['info'] : '-'}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (a) {
                        if (a == 'edit') _edit(p);
                        if (a == 'hapus') _delete(p);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                            value: 'hapus',
                            child: Text('Hapus',
                                style: TextStyle(color: Color(0xFF97291F)))),
                      ],
                    ),
                    onTap: () => _edit(p),
                  ),
                ),
              const SizedBox(height: 80),
            ]),
          ),
        ]),
      );
}

// ===================== INVENTARIS =====================
// Stok produk ini berlaku untuk semua outlet (tidak dipisah per outlet).
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  Future<void> _delVariant(Rec v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Hapus kemasan ${v['kemasan']}?'),
        content: Text(
            'Kemasan ${v['kemasan']} milik ${v['name']} akan dihapus. Riwayat transaksi tetap tersimpan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              style: _kBtnPutih,
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    await (await Db.db)
        .delete('variants', where: 'id=?', whereArgs: [v['vid']]);
    if (mounted) setState(() {});
  }

  Future<void> _addKemasan(int pid, String pname) async {
    final k = TextEditingController(), pr = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Tambah kemasan • $pname'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: k,
              decoration: const InputDecoration(
                  labelText: 'Nama kemasan (mis. Jumbo)')),
          TextField(
              controller: pr,
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
              decoration: const InputDecoration(
                  labelText: 'Harga', prefixText: 'Rp. ')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              style: _kBtnPutih,
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Simpan'))
        ],
      ),
    );
    if (ok != true || k.text.trim().isEmpty) return;
    await (await Db.db).insert('variants', {
      'product_id': pid,
      'kemasan': k.text.trim(),
      'price': moneyOf(pr.text),
      'stock': 0
    });
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        _title(context, 'Inventaris — Kemasan'),
        _note(
            'Atur kemasan tiap menu di sini. Topping dan plastik cukup nama dan harga (harga diubah di Katalog Produk). Topping dan plastik tidak punya stok, jadi tidak pernah terkunci. Kemasan Kecil/Normal/Besar otomatis terkunci "Stok habis" di menu karyawan kalau stoknya di outlet itu 0. Stok per outlet diatur di menu Target & Stok Kemasan.'),
        _Q(
          Db.q(
              'SELECT v.id vid, v.kemasan, v.price, p.id pid, p.name, p.category, c.name AS cname FROM variants v JOIN products p ON p.id=v.product_id LEFT JOIN categories c ON c.key=p.category ORDER BY p.category, p.name, v.price'),
          (rows) {
            final groups = <int, List<Rec>>{};
            for (final r in rows) {
              groups.putIfAbsent(r['pid'] as int, () => []).add(r);
            }
            final utama = [
              for (final g in groups.values)
                if (g.first['category'] == 'utama') g
            ];
            final lain = [
              for (final g in groups.values)
                if (g.first['category'] != 'utama') g
            ];
            return Column(children: [
              if (lain.isNotEmpty)
                Card(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                              {
                                for (final g in lain)
                                  '${g.first['cname'] ?? g.first['category']}'
                              }.join(' • '),
                              style: Theme.of(context).textTheme.titleSmall),
                        ),
                        for (final g in lain)
                          for (final v in g)
                            ListTile(
                              dense: true,
                              title: Text(
                                  '${g.first['name']}${kemTag(v['kemasan'] as String?)}'),
                              trailing: Text(rp(v['price'] as int),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                        const SizedBox(height: 4),
                      ]),
                ),
              for (final g in utama)
                Card(
                  child: ExpansionTile(
                    title: Text(g.first['name'] as String),
                    subtitle: Text('${g.length} kemasan'),
                    children: [
                      for (final v in g)
                        ListTile(
                          dense: true,
                          title: Text(
                              '${v['kemasan']} • ${rp(v['price'] as int)}'),
                          trailing: IconButton(
                              tooltip: 'Hapus kemasan',
                              icon: const Icon(Icons.delete_outline,
                                  color: Color(0xFF97291F)),
                              onPressed: () => _delVariant(v)),
                        ),
                      TextButton.icon(
                          onPressed: () => _addKemasan(
                              g.first['pid'] as int, g.first['name'] as String),
                          icon: const Icon(Icons.add),
                          label: const Text('Tambah kemasan')),
                    ],
                  ),
                ),
            ]);
          },
        ),
      ]);
}

// ===================== KELOLA PEGAWAI =====================
class StaffPage extends StatefulWidget {
  const StaffPage({super.key});
  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Pilih jenis akun yang ditambah (hanya Develop).
  Future<void> _chooseAdd() async {
    if (!Session.isDevelop) return;
    final r = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.badge),
            title: const Text('Pegawai (kasir outlet)'),
            subtitle: const Text('Bertugas di satu outlet'),
            onTap: () => Navigator.pop(c, 'pegawai'),
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings),
            title: const Text('Admin / Mitra / SPV'),
            subtitle: const Text(
                'Panel lengkap, tanpa kelola akun & outlet. Nama peran bebas.'),
            onTap: () => Navigator.pop(c, 'admin'),
          ),
        ]),
      ),
    );
    if (r == 'pegawai') {
      await _add();
    } else if (r == 'admin') {
      await _addAdmin();
    }
  }

  Future<void> _addAdmin() async {
    if (!Session.isDevelop) return;
    final n = TextEditingController(),
        u = TextEditingController(),
        p = TextEditingController(),
        l = TextEditingController(text: 'Admin');
    bool mitra = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => AlertDialog(
          title: const Text('Tambah Admin'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: n,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nama')),
                TextField(
                    controller: u,
                    decoration: const InputDecoration(labelText: 'Username')),
                TextField(
                    controller: p,
                    decoration: const InputDecoration(labelText: 'Password')),
                const SizedBox(height: 8),
                TextField(
                    controller: l,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Nama peran',
                        helperText: 'Bebas diisi, mis. SPV atau Mitra')),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final x in ['Admin', 'SPV', 'Mitra'])
                    ActionChip(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF97291F)),
                        labelStyle: const TextStyle(
                            color: Color(0xFF97291F),
                            fontWeight: FontWeight.w600),
                        label: Text(x),
                        onPressed: () => ss(() {
                              l.text = x;
                              if (x == 'Mitra') mitra = true;
                            })),
                ]),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Akun mitra'),
                  subtitle: const Text(
                      'Hanya melihat outlet miliknya. Langganan diatur per outlet di menu Outlet'),
                  value: mitra,
                  onChanged: (v) => ss(() => mitra = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                style: _kBtnPutih,
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true || u.text.trim().isEmpty || p.text.isEmpty) return;
    final label = l.text.trim().isEmpty ? 'Admin' : l.text.trim();
    try {
      await (await Db.db).insert('users', {
        'name': n.text.trim().isEmpty ? label : n.text.trim(),
        'username': u.text.trim(),
        'password': hashPw(p.text),
        'pw_plain': p.text,
        'role': 'admin',
        'role_label': label,
        'outlet': '',
        'is_mitra': mitra ? 1 : 0,
      });
      if (mounted) _snack('Akun $label dibuat');
    } catch (_) {
      if (mounted) _snack('Username sudah dipakai');
    }
    if (mounted) setState(() {});
  }

  /// Jadikan akun admin sebagai mitra (atau bukan). Mitra hanya melihat outlet
  /// miliknya; langganannya diatur per outlet di menu Outlet.
  Future<void> _toggleMitra(Rec u) async {
    if (!Session.isDevelop || u['role'] != 'admin') return;
    bool mitra = _isMitra(u);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => AlertDialog(
          title: Text('Akun mitra ${u['name']}'),
          content: SizedBox(
            width: 360,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Akun mitra'),
              subtitle: const Text(
                  'Hanya melihat outlet miliknya. Langganan diatur per outlet di menu Outlet'),
              value: mitra,
              onChanged: (v) => ss(() => mitra = v),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                style: _kBtnPutih,
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await (await Db.db).update('users', {'is_mitra': mitra ? 1 : 0},
        where: 'id=?', whereArgs: [u['id']]);
    if (mounted) {
      _snack(mitra ? 'Dijadikan akun mitra' : 'Bukan akun mitra lagi');
      setState(() {});
    }
  }

  /// Teks status di bawah nama akun admin.
  bool _isMitra(Rec u) =>
      u['role'] == 'admin' && ((u['is_mitra'] ?? 0) as num) == 1;

  String _subText(Rec u) {
    if (u['role'] == 'admin' && !_isMitra(u)) {
      return u['outlet_scope'] == 'custom'
          ? '\nAkses ${((u['n_access'] ?? 0) as num).toInt()} outlet'
          : '\nAkses semua outlet';
    }
    if (!_isMitra(u)) return '';
    return '\nMitra • Membawahi ${((u['n_outlets'] ?? 0) as num).toInt()} outlet';
  }

  /// Atur outlet yang boleh dilihat akun Admin / SPV (hanya Develop):
  /// semua outlet, atau outlet tertentu saja.
  Future<void> _assignAccess(Rec a) async {
    if (!Session.isDevelop) return;
    await Db.ensureV3();
    final names = await Target.outlets();
    final cur = await Db.q(
        'SELECT outlet FROM account_outlets WHERE user_id=?', [a['id']]);
    final sel = <String>{for (final r in cur) r['outlet'] as String};
    bool custom = a['outlet_scope'] == 'custom';
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => AlertDialog(
          title: Text('Akses outlet ${a['name']}'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SegmentedButton<bool>(
                  style: SegmentedButton.styleFrom(
                    foregroundColor: Color(0xFF97291F),
                    selectedForegroundColor: Color(0xFF97291F),
                    backgroundColor: Colors.white,
                    selectedBackgroundColor: const Color(0xFFF6E1DF),
                    side: const BorderSide(color: Color(0xFF97291F)),
                  ),
                  segments: const [
                    ButtonSegment(value: false, label: Text('Semua outlet')),
                    ButtonSegment(value: true, label: Text('Outlet tertentu')),
                  ],
                  selected: {custom},
                  onSelectionChanged: (v) => ss(() => custom = v.first),
                ),
                if (custom) ...[
                  const SizedBox(height: 8),
                  if (names.isEmpty)
                    const Text('Belum ada outlet. Tambah dulu di menu Outlet.')
                  else
                    for (final n in names)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: sel.contains(n),
                        title: Text(n),
                        onChanged: (v) => ss(() {
                          if (v == true) {
                            sel.add(n);
                          } else {
                            sel.remove(n);
                          }
                        }),
                      ),
                  if (sel.isEmpty)
                    const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Pilih minimal satu outlet',
                            style: TextStyle(color: Color(0xFF97291F)))),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                style: _kBtnPutih,
                onPressed: (custom && sel.isEmpty)
                    ? null
                    : () => Navigator.pop(c, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final db = await Db.db;
    await db.transaction((t) async {
      await t.update('users', {'outlet_scope': custom ? 'custom' : 'all'},
          where: 'id=?', whereArgs: [a['id']]);
      await t
          .delete('account_outlets', where: 'user_id=?', whereArgs: [a['id']]);
      if (custom) {
        for (final n in sel) {
          await t.insert('account_outlets', {'user_id': a['id'], 'outlet': n});
        }
      }
    });
    if (mounted) {
      _snack('Akses outlet disimpan');
      setState(() {});
    }
  }

  /// Pilih kelompok mitra yang dikelola seorang akun mitra (hanya Develop).
  /// Semua toko di kelompok itu otomatis menjadi milik akun ini.
  Future<void> _assignGroups(Rec m) async {
    if (!Session.isDevelop) return;
    final rows =
        (await Target.groupRows()).where((g) => g['kind'] == 'mitra').toList();
    final sel = <int>{
      for (final g in rows)
        if (g['owner_id'] == m['id']) g['id'] as int
    };
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => AlertDialog(
          title: Text('Kelompok mitra ${m['name']}'),
          content: SizedBox(
            width: 360,
            child: rows.isEmpty
                ? const Text(
                    'Belum ada kelompok mitra. Buat dulu lewat menu Outlet > Tambah Kelompok.')
                : SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final g in rows)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: sel.contains(g['id'] as int),
                          title: Text(g['name'] as String),
                          subtitle: (g['owner_id'] != null &&
                                  g['owner_id'] != m['id'])
                              ? Text(
                                  'Sekarang akun ${g['owner']} (akan dipindah)')
                              : null,
                          onChanged: (v) => ss(() {
                            if (v == true) {
                              sel.add(g['id'] as int);
                            } else {
                              sel.remove(g['id'] as int);
                            }
                          }),
                        ),
                    ]),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                style: _kBtnPutih,
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final db = await Db.db;
    await db.transaction((t) async {
      for (final g in rows) {
        final id = g['id'] as int;
        if (sel.contains(id)) {
          await Db.setGroupOwner(t, id, m['id'] as int);
        } else if (g['owner_id'] == m['id']) {
          await Db.setGroupOwner(t, id, null);
        }
      }
    });
    AdminScope.reloadOutlets();
    if (mounted) {
      _snack('Kelompok mitra disimpan');
      setState(() {});
    }
  }

  Future<void> _resetPw(Rec u) async {
    if (!Session.isDevelop || u['role'] == 'develop') return;
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Reset password ${u['name']}'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(
                labelText: 'Password baru',
                helperText: 'Username ${u['username']} tidak berubah')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Batal')),
          FilledButton(
              style: _kBtnPutih,
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || c.text.isEmpty) return;
    await (await Db.db).update(
        'users', {'password': hashPw(c.text), 'pw_plain': c.text},
        where: 'id=?', whereArgs: [u['id']]);
    if (mounted) _snack('Password diganti');
  }

  Future<void> _add() async {
    if (!Session.isDevelop) return;
    final n = TextEditingController(),
        u = TextEditingController(),
        p = TextEditingController();
    final outlets = await Target.outlets();
    // Kalau admin sedang memilih satu outlet, pegawai baru langsung ke outlet itu.
    String? sel = outlets.contains(AdminScope.value)
        ? AdminScope.value
        : (outlets.isNotEmpty ? outlets.first : null);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => AlertDialog(
          title: const Text('Tambah Pegawai'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: n,
                    decoration: const InputDecoration(labelText: 'Nama')),
                TextField(
                    controller: u,
                    decoration: const InputDecoration(labelText: 'Username')),
                TextField(
                    controller: p,
                    decoration: const InputDecoration(labelText: 'Password')),
                const SizedBox(height: 8),
                if (outlets.isEmpty)
                  const Text('Belum ada outlet. Tambah dulu di menu Outlet.',
                      style: TextStyle(color: Color(0xFF97291F)))
                else
                  DropdownButtonFormField<String>(
                    initialValue: sel,
                    decoration: const InputDecoration(
                        labelText: 'Ditempatkan di outlet'),
                    items: [
                      for (final x in outlets)
                        DropdownMenuItem(value: x, child: Text(x))
                    ],
                    onChanged: (v) => ss(() => sel = v),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                style: _kBtnPutih,
                onPressed:
                    outlets.isEmpty ? null : () => Navigator.pop(c, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true || u.text.trim().isEmpty || p.text.isEmpty || sel == null) {
      return;
    }
    try {
      await (await Db.db).insert('users', {
        'name': n.text.trim(),
        'username': u.text.trim(),
        'password': hashPw(p.text),
        'pw_plain': p.text,
        'role': 'karyawan',
        'outlet': sel
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Username sudah dipakai')));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _rename(Rec u) async {
    if (!Session.isDevelop) return;
    final isAdm = u['role'] == 'admin';
    final c = TextEditingController(text: (u['name'] ?? '') as String);
    final uc = TextEditingController(text: (u['username'] ?? '') as String);
    final lc = TextEditingController(text: roleOf(u));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Ubah akun'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama'),
            ),
            TextField(
              controller: uc,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: 'Username',
                  helperText: 'Dipakai untuk login. Password tidak berubah'),
            ),
            if (isAdm)
              TextField(
                controller: lc,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Nama peran', helperText: 'mis. SPV atau Mitra'),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Batal')),
          FilledButton(
              style: _kBtnPutih,
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    final n = c.text.trim();
    final newUser = uc.text.trim();
    final newLabel = lc.text.trim().isEmpty ? 'Admin' : lc.text.trim();
    final labelChanged = isAdm && newLabel != roleOf(u);
    final userChanged = newUser.isNotEmpty && newUser != u['username'];
    if (ok != true ||
        n.isEmpty ||
        (n == u['name'] && !labelChanged && !userChanged)) {
      return;
    }
    final db = await Db.db;
    try {
      await db.transaction((t) async {
        await t.update(
            'users',
            {
              'name': n,
              if (userChanged) 'username': newUser,
              if (isAdm) 'role_label': newLabel,
            },
            where: 'id=?',
            whereArgs: [u['id']]);
        // nama di riwayat transaksi pegawai ini ikut diperbarui
        await t.update('transactions', {'user_name': n},
            where: 'user_id=?', whereArgs: [u['id']]);
      });
    } catch (_) {
      if (mounted) _snack('Username sudah dipakai');
      return;
    }
    if (u['id'] == Session.id) {
      Session.user = {
        ...Session.user!,
        'name': n,
        if (userChanged) 'username': newUser,
        if (isAdm) 'role_label': newLabel
      };
    }
    if (mounted) setState(() {});
  }

  Future<void> _delete(Rec u) async {
    if (!Session.isDevelop || u['role'] == 'develop') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Hapus ${u['name']}?'),
        content: Text(
            'Akun ${u['username']} dihapus dan tidak bisa login lagi. Riwayat transaksinya tetap tersimpan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Batal')),
          FilledButton(
              style: _kBtnPutih,
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    // outlet milik akun ini kembali ke pusat
    await Db.ensureV3();
    await (await Db.db)
        .delete('account_outlets', where: 'user_id=?', whereArgs: [u['id']]);
    await (await Db.db).update('outlets', {'owner_id': null},
        where: 'owner_id=?', whereArgs: [u['id']]);
    // akun develop tidak bisa dihapus dari sini
    await (await Db.db).delete('users',
        where: "id=? AND role IN ('karyawan','admin') AND id<>?",
        whereArgs: [u['id'], Session.id]);
    if (!mounted) return;
    _snack('Akun dihapus');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final o = AdminScope.value;
    final dev = Session.isDevelop;
    const sqlUsers =
        'SELECT *, (SELECT COUNT(*) FROM outlets x WHERE x.owner_id=users.id) AS n_outlets, (SELECT COUNT(*) FROM account_outlets y WHERE y.user_id=users.id) AS n_access FROM users';
    const order =
        "CASE role WHEN 'develop' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END";
    return Scaffold(
      floatingActionButton: dev
          ? FloatingActionButton.extended(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF97291F),
              shape: const StadiumBorder(
                  side: BorderSide(color: Color(0xFF97291F))),
              onPressed: _chooseAdd,
              icon: const Icon(Icons.person_add),
              label: const Text('Tambah Akun'))
          : null,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _title(context, 'Akun & Pegawai${o.isEmpty ? '' : ' • $o'}'),
        if (!dev)
          _note(
              'Hanya Develop yang dapat menambah, mengubah, atau menghapus akun.'),
        _Q(
          (() async {
            await Db.ensureV3(); // memastikan tabel outlet & kolom pemilik ada
            return Db.q(
                o.isEmpty
                    ? '$sqlUsers ORDER BY $order, name'
                    : '$sqlUsers WHERE outlet=? ORDER BY $order, name',
                [if (o.isNotEmpty) o]);
          })(),
          (rows) => Column(children: [
            if (rows.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Belum ada pegawai'))),
            for (final u in rows)
              _StaffRow(
                key: ValueKey('staff-${u['id']}'),
                u: u,
                dev: dev,
                subtitle: (u['role'] == 'karyawan'
                        ? 'Karyawan • ${u['outlet']}'
                        : '${roleOf(u)} • semua outlet') +
                    _subText(u),
                actions: [
                  if (_isMitra(u))
                    IconButton(
                        tooltip: 'Atur kelompok mitra',
                        icon: const Icon(Icons.store_mall_directory),
                        onPressed: () => _assignGroups(u))
                  else if (u['role'] == 'admin')
                    IconButton(
                        tooltip: 'Atur akses outlet',
                        icon: const Icon(Icons.storefront),
                        onPressed: () => _assignAccess(u)),
                  if (u['role'] == 'admin')
                    IconButton(
                        tooltip: 'Atur akun mitra',
                        icon: const Icon(Icons.supervisor_account),
                        onPressed: () => _toggleMitra(u)),
                  IconButton(
                      tooltip: 'Ubah nama & username',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _rename(u)),
                  if (u['role'] != 'develop')
                    IconButton(
                        tooltip: 'Reset password',
                        icon: const Icon(Icons.key_outlined),
                        onPressed: () => _resetPw(u)),
                  if (u['role'] != 'develop')
                    IconButton(
                        tooltip: 'Hapus akun',
                        icon: const Icon(Icons.delete_outline,
                            color: Color(0xFF97291F)),
                        onPressed: () => _delete(u)),
                ],
                onSaved: () {
                  if (mounted) setState(() {});
                },
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Baris akun dengan panah kecil ke bawah (hanya Develop) untuk melihat
/// username & password, dan menggantinya langsung di situ.
class _StaffRow extends StatefulWidget {
  final Rec u;
  final bool dev;
  final String subtitle;
  final List<Widget> actions;
  final VoidCallback onSaved;
  const _StaffRow(
      {super.key,
      required this.u,
      required this.dev,
      required this.subtitle,
      required this.actions,
      required this.onSaved});
  @override
  State<_StaffRow> createState() => _StaffRowState();
}

class _StaffRowState extends State<_StaffRow> {
  bool open = false;
  bool showPw = false;
  late final TextEditingController uc;
  late final TextEditingController pc;

  Rec get u => widget.u;

  /// Akun Develop lain tidak boleh dilihat/diubah dari sini (sama seperti reset password).
  bool get canOpen =>
      widget.dev && (u['role'] != 'develop' || u['id'] == Session.id);

  @override
  void initState() {
    super.initState();
    uc = TextEditingController(text: (u['username'] ?? '') as String);
    pc = TextEditingController(text: (u['pw_plain'] ?? '') as String);
  }

  @override
  void dispose() {
    uc.dispose();
    pc.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    final newUser = uc.text.trim();
    final newPw = pc.text;
    if (newUser.isEmpty) return _snack('Username tidak boleh kosong');
    if (newPw.isEmpty) return _snack('Password tidak boleh kosong');
    final userChanged = newUser != u['username'];
    final pwChanged = newPw != ((u['pw_plain'] ?? '') as String);
    if (!userChanged && !pwChanged) return _snack('Tidak ada perubahan');
    try {
      await (await Db.db).update(
          'users',
          {
            if (userChanged) 'username': newUser,
            if (pwChanged) 'password': hashPw(newPw),
            'pw_plain': newPw,
          },
          where: 'id=?',
          whereArgs: [u['id']]);
    } catch (_) {
      return _snack('Username sudah dipakai');
    }
    if (u['id'] == Session.id) {
      Session.user = {
        ...Session.user!,
        if (userChanged) 'username': newUser,
      };
    }
    _snack('Username & password disimpan');
    setState(() => open = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ListTile(
        leading: Icon(u['role'] == 'karyawan'
            ? Icons.person
            : Icons.admin_panel_settings),
        title: Text('${u['name']} (${u['username']})'),
        subtitle: Text(widget.subtitle),
        // Hanya panah di kanan; tombol aksi dipindah ke baris bawah supaya
        // nama & keterangan akun tidak terjepit di layar HP.
        trailing: (!widget.dev || !canOpen)
            ? null
            : IconButton(
                tooltip: open ? 'Tutup' : 'Lihat username & password',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
                onPressed: () => setState(() {
                  open = !open;
                  if (open) {
                    uc.text = (u['username'] ?? '') as String;
                    pc.text = (u['pw_plain'] ?? '') as String;
                    showPw = false;
                  }
                }),
              ),
      ),
      if (widget.dev && widget.actions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 0, runSpacing: 0, children: [
              for (final a in widget.actions)
                IconTheme.merge(data: const IconThemeData(size: 22), child: a)
            ]),
          ),
        ),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: !open
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: uc,
                        autocorrect: false,
                        decoration: const InputDecoration(
                            labelText: 'Username', isDense: true),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: pc,
                        obscureText: !showPw,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          isDense: true,
                          helperText: (u['pw_plain'] == null)
                              ? 'Password lama belum tersimpan. Isi password baru lalu simpan, atau akan terlihat otomatis setelah akun ini login.'
                              : null,
                          helperMaxLines: 3,
                          suffixIcon: IconButton(
                            tooltip: showPw ? 'Sembunyikan' : 'Tampilkan',
                            icon: Icon(showPw
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () => setState(() => showPw = !showPw),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(
                            onPressed: () => setState(() => open = false),
                            child: const Text('Batal')),
                        const SizedBox(width: 8),
                        FilledButton(
                            style: _kBtnPutih,
                            onPressed: _save,
                            child: const Text('Simpan')),
                      ]),
                    ]),
              ),
      ),
    ]);
  }
}

// ===================== LANGGANAN (PER OUTLET) =====================
String _isoDay(DateTime d) => d.toIso8601String().substring(0, 10);

/// Tambah bulan tanpa meloncat (31 Jan + 1 bulan = 28/29 Feb).
DateTime _addMonths(DateTime d, int m) {
  final last = DateTime(d.year, d.month + m + 1, 0).day;
  return DateTime(d.year, d.month + m, d.day < last ? d.day : last);
}

/// Pengaturan langganan: wajib berlangganan + tanggal berakhir.
/// Perpanjangan dihitung dari tanggal berakhir (atau hari ini kalau sudah lewat).
class _SubEditor extends StatefulWidget {
  final bool req;
  final DateTime? until;
  final void Function(bool req, DateTime? until) onChanged;
  const _SubEditor(
      {required this.req, required this.until, required this.onChanged});
  @override
  State<_SubEditor> createState() => _SubEditorState();
}

class _SubEditorState extends State<_SubEditor> {
  late bool req = widget.req;
  late DateTime? until = widget.until;

  void _set(bool r, DateTime? d) {
    setState(() {
      req = r;
      until = d;
    });
    widget.onChanged(r, d);
  }

  void _extend(int months) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final base = (until != null && !until!.isBefore(today)) ? until! : today;
    _set(req, _addMonths(base, months));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expired = until == null || until!.isBefore(today);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Outlet berlangganan'),
        subtitle: const Text(
            'Outlet dan pegawainya terkunci kalau tanggal berakhir lewat atau belum diatur'),
        value: req,
        onChanged: (v) => _set(v, v ? (until ?? _addMonths(today, 1)) : until),
      ),
      if (req) ...[
        Text(
            until == null
                ? 'Aktif sampai: belum diatur (terkunci)'
                : 'Aktif sampai: ${DateFormat('dd MMM yyyy').format(until!)}'
                    '${expired ? '  • SUDAH BERAKHIR' : ''}',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: expired ? Color(0xFF97291F) : null)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final m in const {
            '+1 bulan': 1,
            '+3 bulan': 3,
            '+6 bulan': 6,
            '+1 tahun': 12
          }.entries)
            ActionChip(
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF97291F)),
                labelStyle: const TextStyle(
                    color: Color(0xFF97291F), fontWeight: FontWeight.w600),
                label: Text(m.key,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600)),
                onPressed: () => _extend(m.value)),
        ]),
        const SizedBox(height: 4),
        TextButton.icon(
          icon: const Icon(Icons.calendar_today, size: 18),
          label: const Text('Pilih tanggal sendiri'),
          onPressed: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: until ?? today,
                firstDate: DateTime(2024),
                lastDate: DateTime(today.year + 10));
            if (d != null) _set(req, d);
          },
        ),
      ],
    ]);
  }
}

// ===================== KATEGORI PRODUK =====================
class _CatDialog extends StatefulWidget {
  const _CatDialog();
  @override
  State<_CatDialog> createState() => _CatDialogState();
}

class _CatDialogState extends State<_CatDialog> {
  List<Rec> cats = [];
  String? err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Db.categories();
    if (mounted) setState(() => cats = c);
  }

  Future<void> _name(Rec? k) async {
    final c = TextEditingController(text: (k?['name'] as String?) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(k == null ? 'Tambah Kategori' : 'Ubah Nama Kategori'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nama kategori')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Batal')),
          FilledButton(
              style: _kBtnPutih,
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    final n = c.text.trim();
    if (ok != true || n.isEmpty) return;
    final d = await Db.db;
    if (k == null) {
      await d.insert('categories', {
        'key': 'k${DateTime.now().millisecondsSinceEpoch}',
        'name': n,
        'sort': cats.length + 1
      });
    } else {
      await d.update('categories', {'name': n},
          where: 'id=?', whereArgs: [k['id']]);
    }
    err = null;
    _load();
  }

  Future<void> _del(Rec k) async {
    final d = await Db.db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) n FROM products WHERE category=?', [k['key']]);
    if ((r.first['n'] as int) > 0) {
      setState(() => err =
          'Kategori masih berisi produk. Pindahkan produknya dulu di Katalog.');
      return;
    }
    await d.delete('categories', where: 'id=?', whereArgs: [k['id']]);
    err = null;
    _load();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Kategori Produk'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Kategori tampil sebagai tab di halaman Transaksi.',
                  style: TextStyle(fontSize: 12)),
              if (err != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(err!,
                        style: const TextStyle(color: Color(0xFF97291F)))),
              for (final k in cats)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(k['name'] as String),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _name(k)),
                    if (k['key'] != 'utama' && k['key'] != 'topping')
                      IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _del(k)),
                  ]),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton.icon(
              onPressed: () => _name(null),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Kategori')),
          FilledButton(
              style: _kBtnPutih,
              onPressed: () => Navigator.pop(context),
              child: const Text('Selesai')),
        ],
      );
}

// ===================== TARGET HARIAN PER OUTLET =====================
// Semua outlet: tampil satu kartu per outlet (ketuk kartu untuk masuk ke
// outlet itu). Satu outlet dipilih: hanya kartu outlet itu yang tampil.
class TargetPage extends StatefulWidget {
  const TargetPage({super.key});
  @override
  State<TargetPage> createState() => _TargetPageState();
}

class _TargetPageState extends State<TargetPage> {
  final _tick = ValueNotifier<int>(0);

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  // Belum ada outlet dipilih: tampilkan kotak outlet, ketuk satu untuk masuk.
  Widget _picker(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        _title(context, 'Target & Stok Kemasan'),
        _note(
            'Halaman ini menampilkan satu outlet saja. Pilih outlet di bawah (atau di bilah atas) untuk melihat target, penjualan, dan stok kemasannya.'),
        _Q(
          Target.outletRows(),
          (rows) {
            if (rows.isEmpty) {
              return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('Belum ada outlet. Tambah di menu Outlet.')));
            }
            return LayoutBuilder(builder: (c, cons) {
              final cols = (cons.maxWidth ~/ 240).clamp(1, 4).toInt();
              final w = (cons.maxWidth - 12 * (cols - 1)) / cols;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final r in rows)
                  SizedBox(
                    width: w,
                    child: Card(
                      child: ListTile(
                        onTap: () => AdminScope.pick(r['name'] as String),
                        leading: const Icon(Icons.store),
                        title: Text(r['name'] as String,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${r['staff']} pegawai'),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                  ),
              ]);
            });
          },
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final o = AdminScope.value;
    if (o.isEmpty) return _picker(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _title(context, 'Target & Stok Kemasan • $o'),
      _note(
          'Menampilkan satu outlet. Hitungan terjual kembali ke 0 setiap pukul 00.00, sedangkan stok kemasan berkurang otomatis setiap penjualan. Pilih outlet lain di bilah atas untuk berpindah.'),
      TargetCard(
        outlet: o,
        tick: _tick,
        onEdit: () async {
          await Target.edit(context, o);
          _tick.value++;
        },
        onStock: () async {
          await Target.adjustDialog(context, o);
          _tick.value++;
        },
      ),
    ]);
  }
}

// ===================== OUTLET =====================
// Ketuk satu outlet untuk masuk ke datanya: semua halaman admin lalu
// menampilkan data outlet itu saja.
class OutletPage extends StatefulWidget {
  const OutletPage({super.key});
  @override
  State<OutletPage> createState() => _OutletPageState();
}

class _OutletPageState extends State<OutletPage> {
  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  /// Tambah toko baru; bisa langsung dimasukkan ke sebuah kelompok.
  Future<void> _add() async {
    if (!Session.isDevelop) return;
    final groups = await Target.groupRows();
    if (!mounted) return;
    final c = TextEditingController();
    int gid = 0; // 0 = tanpa kelompok
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, ss) => AlertDialog(
          title: const Text('Tambah Outlet'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: c,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Nama outlet (mis. Outlet Madiun)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: gid,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kelompok'),
                  items: [
                    const DropdownMenuItem(
                        value: 0, child: Text('Tanpa kelompok')),
                    for (final g in groups)
                      DropdownMenuItem(
                          value: g['id'] as int,
                          child: Text(
                              '${g['name']} (${g['kind'] == 'pusat' ? 'Outlet Pusat' : 'Mitra'})',
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => ss(() => gid = v ?? 0),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Batal')),
            FilledButton(
                style: _kBtnPutih,
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    final n = c.text.trim();
    if (ok != true || n.isEmpty) return;
    await Db.ensureV3();
    try {
      final db = await Db.db;
      await db.transaction((t) async {
        await t.insert('outlets', {'name': n});
        if (gid != 0) await Db.moveOutlet(t, n, gid);
      });
    } catch (_) {
      if (mounted) _snack('Nama outlet sudah ada');
    }
    AdminScope.reloadOutlets();
    if (mounted) setState(() {});
  }

  /// Tambah / ubah kelompok (Outlet Pusat atau Mitra). Kelompok mitra boleh
  /// dihubungkan ke satu akun mitra.
  Future<void> _groupDialog({Rec? g}) async {
    if (!Session.isDevelop) return;
    await Db.ensureV3();
    final accounts = await Db.q(
        "SELECT id, name, username FROM users WHERE role='admin' AND is_mitra=1 ORDER BY name");
    final all = await Target.groupRows();
    final nMitra = all.where((x) => x['kind'] == 'mitra').length;
    String kind = g == null ? 'mitra' : g['kind'] as String;
    String auto = 'Mitra ${nMitra + 1}';
    final c =
        TextEditingController(text: g == null ? auto : g['name'] as String);
    int? owner = g?['owner_id'] as int?;
    if (owner != null && !accounts.any((a) => a['id'] == owner)) owner = null;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, ss) => AlertDialog(
          title: Text(g == null ? 'Tambah Kelompok' : 'Ubah Kelompok'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (g == null) ...[
                  SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(
                      foregroundColor: Color(0xFF97291F),
                      selectedForegroundColor: Color(0xFF97291F),
                      backgroundColor: Colors.white,
                      selectedBackgroundColor: const Color(0xFFF6E1DF),
                      side: const BorderSide(color: Color(0xFF97291F)),
                    ),
                    segments: const [
                      ButtonSegment(
                          value: 'pusat', label: Text('Outlet Pusat')),
                      ButtonSegment(value: 'mitra', label: Text('Mitra')),
                    ],
                    selected: {kind},
                    onSelectionChanged: (v) => ss(() {
                      final was = c.text.trim();
                      kind = v.first;
                      if (was.isEmpty || was == auto) {
                        auto = kind == 'pusat'
                            ? 'Outlet Pusat'
                            : 'Mitra ${nMitra + 1}';
                        c.text = auto;
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                    controller: c,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                        labelText: 'Nama kelompok',
                        helperText: kind == 'pusat'
                            ? 'mis. Outlet Pusat'
                            : 'mis. Mitra 1')),
                if (kind == 'mitra') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: owner,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Akun mitra (login)'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Belum ada akun')),
                      for (final a in accounts)
                        DropdownMenuItem<int?>(
                            value: a['id'] as int,
                            child: Text('${a['name']} (${a['username']})',
                                overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => owner = v,
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Batal')),
            FilledButton(
                style: _kBtnPutih,
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    final n = c.text.trim();
    if (ok != true || n.isEmpty) return;
    try {
      final db = await Db.db;
      await db.transaction((t) async {
        if (g == null) {
          await t.insert('outlet_groups', {
            'name': n,
            'kind': kind,
            'owner_id': kind == 'mitra' ? owner : null,
          });
        } else {
          await t.update('outlet_groups', {'name': n},
              where: 'id=?', whereArgs: [g['id']]);
          if (kind == 'mitra') {
            await Db.setGroupOwner(t, g['id'] as int, owner);
          }
        }
      });
    } catch (_) {
      if (mounted) _snack('Nama kelompok sudah ada');
      return;
    }
    AdminScope.reloadOutlets();
    if (mounted) {
      _snack(g == null ? 'Kelompok $n dibuat' : 'Kelompok disimpan');
      setState(() {});
    }
  }

  /// Pilih toko mana saja yang ada di satu kelompok (tambah / keluarkan).
  /// Toko yang masih di kelompok lain otomatis dipindahkan ke sini.
  Future<void> _groupOutlets(Rec g) async {
    if (!Session.isDevelop) return;
    await Db.ensureV3();
    final gid = g['id'] as int;
    final rows = await Db.q(
        'SELECT o.name, o.group_id, (SELECT x.name FROM outlet_groups x WHERE x.id=o.group_id) AS gname FROM outlets o ORDER BY o.name');
    final before = <String>{
      for (final r in rows)
        if (r['group_id'] == gid) r['name'] as String
    };
    final sel = Set<String>.of(before);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => AlertDialog(
          title: Text('Toko di ${g['name']}'),
          content: SizedBox(
            width: 360,
            child: rows.isEmpty
                ? const Text(
                    'Belum ada outlet. Tambah dulu lewat Tambah Outlet.')
                : SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final r in rows)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: sel.contains(r['name'] as String),
                          title: Text(r['name'] as String),
                          subtitle: (r['group_id'] != null &&
                                  r['group_id'] != gid)
                              ? Text(
                                  'Sekarang di ${r['gname']} (akan dipindah)')
                              : null,
                          onChanged: (v) => ss(() {
                            if (v == true) {
                              sel.add(r['name'] as String);
                            } else {
                              sel.remove(r['name'] as String);
                            }
                          }),
                        ),
                    ]),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                style: _kBtnPutih,
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final db = await Db.db;
    await db.transaction((t) async {
      for (final n in sel.difference(before)) {
        await Db.moveOutlet(t, n, gid);
      }
      for (final n in before.difference(sel)) {
        await Db.moveOutlet(t, n, null);
      }
    });
    AdminScope.reloadOutlets();
    if (mounted) {
      _snack('Toko kelompok disimpan');
      setState(() {});
    }
  }

  /// Pindahkan satu toko ke kelompok lain (atau keluarkan dari kelompok).
  Future<void> _moveOutlet(Rec r) async {
    if (!Session.isDevelop) return;
    final groups = await Target.groupRows();
    if (!mounted) return;
    final cur = r['group_id'] as int?;
    final pick = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Pindahkan ${r['name']} ke'),
        children: [
          for (final g in groups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, g['id'] as int),
              child: Row(children: [
                Icon(
                    g['kind'] == 'pusat'
                        ? Icons.home_work_outlined
                        : Icons.groups_outlined,
                    size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(g['name'] as String)),
                if (g['id'] == cur) const Icon(Icons.check, size: 18),
              ]),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, -1),
            child: Row(children: [
              const Icon(Icons.folder_off_outlined, size: 20),
              const SizedBox(width: 12),
              const Expanded(child: Text('Tanpa kelompok')),
              if (cur == null) const Icon(Icons.check, size: 18),
            ]),
          ),
        ],
      ),
    );
    if (pick == null) return;
    final gid = pick == -1 ? null : pick;
    if (gid == cur) return;
    final db = await Db.db;
    await db.transaction((t) => Db.moveOutlet(t, r['name'] as String, gid));
    AdminScope.reloadOutlets();
    if (mounted) {
      _snack('${r['name']} dipindahkan');
      setState(() {});
    }
  }

  /// Hapus kelompok. Tokonya tidak ikut terhapus, hanya menjadi "Tanpa
  /// kelompok" (dan kalau kelompok mitra, mitranya tidak lagi melihat toko itu).
  Future<void> _delGroup(Rec g, int n) async {
    if (!Session.isDevelop) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Hapus kelompok ${g['name']}?'),
        content: Text(n == 0
            ? 'Kelompok ini kosong.'
            : '$n toko di dalamnya tidak ikut dihapus, tetapi menjadi "Tanpa kelompok".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Batal')),
          FilledButton(
              style: _kBtnPutih,
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    final db = await Db.db;
    await db.transaction((t) async {
      await t.update('outlets', {'group_id': null, 'owner_id': null},
          where: 'group_id=?', whereArgs: [g['id']]);
      await t.delete('outlet_groups', where: 'id=?', whereArgs: [g['id']]);
    });
    if (AdminScope.groupId == g['id']) AdminScope.pick('');
    AdminScope.reloadOutlets();
    if (mounted) setState(() {});
  }

  /// Atur langganan satu outlet (hanya Develop): wajib langganan + tanggal
  /// berakhir.
  Future<void> _subscription(Rec r) async {
    if (!Session.isDevelop) return;
    final name = r['name'] as String;
    bool req = ((r['sub_required'] ?? 0) as num) == 1;
    final cur = (r['sub_until'] ?? '') as String;
    DateTime? until = cur.isEmpty ? null : DateTime.parse(cur);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Langganan $name'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: _SubEditor(
                req: req,
                until: until,
                onChanged: (r2, d) {
                  req = r2;
                  until = d;
                }),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              style: _kBtnPutih,
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true) return;
    await (await Db.db).update(
        'outlets',
        {
          'sub_required': req ? 1 : 0,
          'sub_until': req && until != null ? _isoDay(until!) : null,
        },
        where: 'name=?',
        whereArgs: [name]);
    AdminScope.reloadOutlets();
    if (mounted) {
      _snack(req ? 'Langganan $name disimpan' : 'Langganan $name dimatikan');
      setState(() {});
    }
  }

  /// Teks status langganan di bawah nama outlet (kosong = tidak berlangganan).
  String _subLine(Rec r) {
    if (((r['sub_required'] ?? 0) as num) != 1) return '';
    final until = (r['sub_until'] ?? '') as String;
    if (until.isEmpty) return '\nLangganan: belum diatur • TERKUNCI';
    final d = DateTime.parse(until);
    final fmt = DateFormat('dd MMM yyyy').format(d);
    if (outletSubLock(r) != null) return '\nLangganan berakhir $fmt • TERKUNCI';
    final now = DateTime.now();
    final left = d.difference(DateTime(now.year, now.month, now.day)).inDays;
    return '\nLangganan sampai $fmt • sisa $left hari';
  }

  Future<void> _del(String name, int staff) async {
    if (!Session.isDevelop) return;
    if (staff > 0) {
      _snack(
          'Masih ada $staff pegawai di outlet ini. Pindahkan atau hapus dulu pegawainya.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Hapus $name?'),
        content: const Text(
            'Stok kemasan outlet ini ikut dihapus. Riwayat transaksi tetap tersimpan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Batal')),
          FilledButton(
              style: _kBtnPutih,
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    final db = await Db.db;
    await db.delete('outlets', where: 'name=?', whereArgs: [name]);
    await db.delete('kemasan_stock', where: 'outlet=?', whereArgs: [name]);
    await db.delete('account_outlets', where: 'outlet=?', whereArgs: [name]);
    await db.delete('settings',
        where: 'key LIKE ?', whereArgs: ['nota|$name|%']); // pengaturan nota
    // Kalau outlet yang dihapus sedang dipilih, kembali ke "Semua Outlet".
    if (AdminScope.value == name) AdminScope.pick('');
    AdminScope.reloadOutlets();
    if (mounted) setState(() {});
  }

  /// Satu toko: nama, jumlah pegawai, status langganan, dan tombol-tombolnya.
  Widget _outletBlock(Rec r) => Column(children: [
        ListTile(
          selected: AdminScope.value == r['name'],
          onTap: () => AdminScope.pick(r['name'] as String),
          leading: const Icon(Icons.store),
          title: Text(r['name'] as String),
          subtitle: Text('${r['staff']} pegawai${_subLine(r)}'),
          trailing: !Session.isDevelop
              ? null
              : IconButton(
                  tooltip: 'Hapus outlet',
                  icon: const Icon(Icons.delete_outline,
                      color: Color(0xFF97291F)),
                  onPressed: () =>
                      _del(r['name'] as String, (r['staff'] as num).toInt())),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('Pengaturan Nota'),
                onPressed: () async {
                  final n = r['name'] as String;
                  final ok = await NotaCfg.dialog(context, n);
                  if (ok && mounted) {
                    _snack('Pengaturan nota $n tersimpan');
                  }
                },
              ),
              if (Session.isDevelop)
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_repeat, size: 18),
                  label: const Text('Langganan'),
                  onPressed: () => _subscription(r),
                ),
              if (Session.isDevelop)
                OutlinedButton.icon(
                  icon: const Icon(Icons.drive_file_move_outline, size: 18),
                  label: const Text('Pindah Kelompok'),
                  onPressed: () => _moveOutlet(r),
                ),
            ]),
          ),
        ),
      ]);

  /// Satu kelompok: judul (ketuk = lihat data semua toko di dalamnya) + tokonya.
  Widget _groupCard(Rec g, List<Rec> outlets) {
    final pusat = g['kind'] == 'pusat';
    final gid = g['id'] as int;
    final akun = pusat
        ? ''
        : (g['owner'] != null ? ' • Akun: ${g['owner']}' : ' • belum ada akun');
    return Card(
      child: Column(children: [
        ListTile(
          selected: AdminScope.groupId == gid,
          onTap: () => AdminScope.pickGroup(gid),
          leading:
              Icon(pusat ? Icons.home_work_outlined : Icons.groups_outlined),
          title: Text(g['name'] as String,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
              '${pusat ? 'Outlet Pusat' : 'Mitra'} • ${outlets.length} toko$akun'),
          trailing: !Session.isDevelop
              ? null
              : PopupMenuButton<String>(
                  tooltip: 'Menu kelompok',
                  onSelected: (v) {
                    if (v == 'outlets') {
                      _groupOutlets(g);
                    } else if (v == 'edit') {
                      _groupDialog(g: g);
                    } else if (v == 'del') {
                      _delGroup(g, outlets.length);
                    }
                  },
                  itemBuilder: (c) => const [
                    PopupMenuItem(value: 'outlets', child: Text('Atur toko')),
                    PopupMenuItem(
                        value: 'edit', child: Text('Ubah nama / akun')),
                    PopupMenuItem(value: 'del', child: Text('Hapus kelompok')),
                  ],
                ),
        ),
        const Divider(height: 1),
        if (outlets.isEmpty)
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Belum ada toko di kelompok ini'))
        else
          for (final r in outlets) _outletBlock(r),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: Session.isDevelop
            ? FloatingActionButton.extended(
                backgroundColor: Colors.white,
                foregroundColor: Color(0xFF97291F),
                shape: const StadiumBorder(
                    side: BorderSide(color: Color(0xFF97291F))),
                onPressed: _add,
                icon: const Icon(Icons.add_business),
                label: const Text('Tambah Outlet'))
            : null,
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _title(context, 'Outlet'),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
                'Toko dikelompokkan menjadi Outlet Pusat dan kelompok Mitra. Ketuk nama kelompok untuk melihat data semua toko di dalamnya, atau ketuk satu toko untuk melihat datanya saja. Mengatur kelompok, menambah, memindah, dan menghapus outlet hanya bisa dilakukan Develop.',
                style: TextStyle(fontSize: 12)),
          ),
          if (Session.isDevelop)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('Tambah Kelompok'),
                  onPressed: () => _groupDialog(),
                ),
              ),
            ),
          _Q(
            Target.groupRows(),
            (groups) => _Q(
              Target.outletRows(),
              (rows) {
                final byGroup = <int?, List<Rec>>{};
                for (final r in rows) {
                  byGroup.putIfAbsent(r['group_id'] as int?, () => []).add(r);
                }
                // akun terbatas (mitra / akses tertentu): hanya kelompok yang
                // punya toko terlihat
                final shown = [
                  for (final g in groups)
                    if (!Scope.restricted || byGroup.containsKey(g['id'])) g
                ];
                final lepas = byGroup[null] ?? const <Rec>[];
                return Column(children: [
                  if (shown.isEmpty && lepas.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: Text(
                                'Belum ada outlet. Tekan Tambah Outlet.'))),
                  for (final g in shown)
                    _groupCard(g, byGroup[g['id']] ?? const <Rec>[]),
                  if (lepas.isNotEmpty)
                    Card(
                      child: Column(children: [
                        const ListTile(
                          leading: Icon(Icons.folder_off_outlined),
                          title: Text('Tanpa kelompok',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const Divider(height: 1),
                        for (final r in lepas) _outletBlock(r),
                      ]),
                    ),
                  const SizedBox(height: 80),
                ]);
              },
            ),
          ),
        ]),
      );
}
