import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db.dart';
import 'scope.dart';

/// Laporan kinerja pegawai untuk admin.
/// Tiap akun pegawai dirinci per shift (check-in sampai check-out): berapa
/// transaksi dan berapa rupiah yang dihasilkan pada rentang waktu itu.
/// Transaksi yang dibuat saat pegawai tidak sedang check-in ditampilkan
/// terpisah sebagai "Di luar jam absensi" supaya angkanya tetap cocok.
class ReportPegawai extends StatefulWidget {
  const ReportPegawai({super.key});
  @override
  State<ReportPegawai> createState() => _ReportPegawaiState();
}

class _ReportPegawaiState extends State<ReportPegawai> {
  DateTimeRange range =
      DateTimeRange(start: DateTime.now(), end: DateTime.now());
  // Mengikuti outlet yang dipilih di bilah atas ('' = semua outlet)
  final String outlet = AdminScope.value;
  int? uid; // null = semua pegawai
  List<Rec> emps = [];
  late Future<Map<String, List<Rec>>> fut;
  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    fut = _fetch();
    Db.q("SELECT id, name, outlet FROM users WHERE role='karyawan'${Scope.and('outlet')} ORDER BY outlet, name",
            Scope.args)
        .then((r) {
      if (mounted) setState(() => emps = r);
    });
  }

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  void _apply(VoidCallback f) => setState(() {
        f();
        fut = _fetch();
      });

  Future<Map<String, List<Rec>>> _fetch() async {
    final from = _iso(range.start), to = _iso(range.end);
    final nowIso = DateTime.now().toIso8601String();
    final w = StringBuffer();
    final extra = <Object?>[];
    w.write(Scope.and('u.outlet')); // mitra: hanya outlet miliknya
    extra.addAll(Scope.args);
    if (uid != null) {
      w.write(' AND u.id=?');
      extra.add(uid);
    }
    // Ringkasan per pegawai (semua transaksi pegawai itu pada rentang tanggal)
    final sum = await Db.q(
        "SELECT u.id, u.name, u.outlet, COUNT(t.id) n, COALESCE(SUM(t.total),0) tot FROM users u LEFT JOIN transactions t ON t.user_id=u.id AND substr(t.created_at,1,10) BETWEEN ? AND ? WHERE u.role='karyawan'$w GROUP BY u.id ORDER BY tot DESC",
        [from, to, ...extra]);
    // Rincian per shift: transaksi pegawai antara check-in dan check-out.
    // Shift yang belum check-out dihitung sampai sekarang.
    final shifts = await Db.q(
        "SELECT a.id, a.user_id uid, a.check_in, a.check_out, "
        "(SELECT COUNT(*) FROM transactions t WHERE t.user_id=a.user_id AND t.created_at>=a.check_in AND t.created_at<=COALESCE(a.check_out,'$nowIso')) n, "
        "(SELECT COALESCE(SUM(t.total),0) FROM transactions t WHERE t.user_id=a.user_id AND t.created_at>=a.check_in AND t.created_at<=COALESCE(a.check_out,'$nowIso')) tot "
        "FROM attendance a JOIN users u ON u.id=a.user_id "
        "WHERE u.role='karyawan' AND substr(a.check_in,1,10) BETWEEN ? AND ?$w ORDER BY a.check_in DESC",
        [from, to, ...extra]);
    return {'sum': sum, 'shifts': shifts};
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: DateTime.now(),
        initialDateRange: range);
    if (r != null) _apply(() => range = r);
  }

  Duration _dur(Rec r) {
    final a = DateTime.parse(r['check_in'] as String);
    final b = r['check_out'] == null
        ? DateTime.now()
        : DateTime.parse(r['check_out'] as String);
    return b.difference(a);
  }

  String _fmtDur(Duration d) => '${d.inHours}j ${d.inMinutes % 60}m';

  Widget _card(Rec e, List<Rec> sh, num max, bool open) {
    final n = (e['n'] as num).toInt();
    final tot = e['tot'] as num;
    var shN = 0, shTot = 0, mins = 0;
    for (final r in sh) {
      shN += (r['n'] as num).toInt();
      shTot += (r['tot'] as num).toInt();
      mins += _dur(r).inMinutes;
    }
    final outN = (n - shN).clamp(0, n).toInt();
    final outTot = (tot - shTot).clamp(0, tot).toInt();
    return Card(
      child: ExpansionTile(
        initiallyExpanded: open,
        title: Text('${e['name']} • ${e['outlet']}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '$n transaksi • ${rp(tot)} • ${sh.length} shift • ${_fmtDur(Duration(minutes: mins))}'),
          const SizedBox(height: 4),
          LinearProgressIndicator(
              value: max == 0 ? 0 : (tot / max).toDouble(),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3)),
        ]),
        children: [
          if (sh.isEmpty)
            const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Belum ada check-in pada rentang ini')),
          for (final r in sh)
            ListTile(
              dense: true,
              leading: Icon(
                  r['check_out'] == null ? Icons.timer : Icons.check_circle,
                  color: r['check_out'] == null ? Colors.orange : Colors.green),
              title: Text('Masuk ${fmtDt(r['check_in'] as String)}'),
              subtitle: Text(r['check_out'] == null
                  ? 'Belum check out (dihitung sampai sekarang)'
                  : 'Keluar ${fmtDt(r['check_out'] as String)} • ${_fmtDur(_dur(r))}'),
              trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${r['n']} transaksi',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(rp(r['tot'] as num),
                        style: const TextStyle(fontSize: 12)),
                  ]),
            ),
          if (outN > 0)
            ListTile(
              dense: true,
              leading: const Icon(Icons.warning_amber, color: Colors.orange),
              title: const Text('Di luar jam absensi'),
              subtitle: const Text('Transaksi saat tidak sedang check-in'),
              trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$outN transaksi',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(rp(outTot), style: const TextStyle(fontSize: 12)),
                  ]),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final opts = [
      for (final e in emps)
        if (outlet.isEmpty || e['outlet'] == outlet) e
    ];
    final rangeTxt = '${_fmt.format(range.start)} - ${_fmt.format(range.end)}';
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Laporan Pegawai${outlet.isEmpty ? '' : ' • $outlet'}',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
          'Transaksi tiap pegawai dihitung dari check-in sampai check-out (per shift).',
          style: TextStyle(fontSize: 12, color: cs.outline)),
      const SizedBox(height: 12),
      DropdownButtonFormField<int?>(
        initialValue: opts.any((e) => e['id'] == uid) ? uid : null,
        decoration: const InputDecoration(
            border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge)),
        items: [
          const DropdownMenuItem<int?>(
              value: null, child: Text('Semua Pegawai')),
          for (final e in opts)
            DropdownMenuItem<int?>(
                value: e['id'] as int,
                child: Text('${e['name']} • ${e['outlet']}')),
        ],
        onChanged: (v) => _apply(() => uid = v),
      ),
      const SizedBox(height: 12),
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
            label: const Text('Hari ini'),
            onPressed: () =>
                _apply(() => range = DateTimeRange(start: now, end: now))),
        ActionChip(
            label: const Text('7 hari'),
            onPressed: () => _apply(() => range = DateTimeRange(
                start: now.subtract(const Duration(days: 6)), end: now))),
        ActionChip(
            label: const Text('Bulan ini'),
            onPressed: () => _apply(() => range = DateTimeRange(
                start: DateTime(now.year, now.month, 1), end: now))),
      ]),
      const SizedBox(height: 16),
      FutureBuilder<Map<String, List<Rec>>>(
        future: fut,
        builder: (c, s) {
          if (!s.hasData) {
            return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()));
          }
          final sum = s.data!['sum']!;
          final shifts = s.data!['shifts']!;
          if (sum.isEmpty) return const Text('Belum ada pegawai');
          final max = sum.fold<num>(
              0, (a, e) => (e['tot'] as num) > a ? e['tot'] as num : a);
          final byUser = <int, List<Rec>>{};
          for (final r in shifts) {
            byUser.putIfAbsent(r['uid'] as int, () => []).add(r);
          }
          return Column(children: [
            for (final e in sum)
              _card(e, byUser[e['id'] as int] ?? const <Rec>[], max,
                  sum.length == 1),
          ]);
        },
      ),
    ]);
  }
}
