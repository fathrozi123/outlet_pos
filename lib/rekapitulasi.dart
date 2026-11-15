import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db.dart';
import 'scope.dart';
import 'target.dart';

// ===================== REKAPITULASI: BEBAN & MODAL =====================
// Dipakai oleh Ringkasan Penjualan:
//   Total Pendapatan Bersih = Penjualan Kotor - Diskon - Modal (%) - Beban
//
//   Modal (%) : persen yang diatur per outlet di menu Rekapitulasi. Di
//               Ringkasan Penjualan hasilnya berupa uang:
//               Modal (Rp) = Total Pendapatan Kotor x Modal (%).
//   Beban     : input manual per outlet per bulan. Total Beban bulan itu
//               langsung dipakai di Ringkasan Penjualan, tanpa dibagi per
//               hari. Jika rentang tanggal mencakup beberapa bulan, Total
//               Beban tiap bulan yang tersentuh rentang ikut dipakai.
class Rekap {
  /// [kunci, label] item beban yang diinput manual.
  static const items = [
    ['sewa', 'Sewa'],
    ['gaji', 'Gaji Karyawan'],
    ['wifi', 'Wifi'],
    ['sampah', 'Sampah'],
    ['renovasi', 'Renovasi'],
    ['lain', 'Beban Lain-lain'],
    ['langganan', 'Langganan Aplikasi'],
  ];

  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  static const _bulan = [
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

  /// "November 2026" (tanpa DateFormat, jadi tidak butuh data locale).
  static String monthLabel(DateTime d) => '${_bulan[d.month - 1]} ${d.year}';
  static String _bk(String o, String m, String k) => 'beban|$o|$m|$k';
  static String _mk(String o) => 'modalpct|$o';

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  // ---------- beban ----------
  static Future<Map<String, int>> getBeban(String outlet, String month) async {
    final r = <String, int>{};
    for (final it in items) {
      r[it[0]] =
          int.tryParse(await Db.getSetting(_bk(outlet, month, it[0])) ?? '') ??
              0;
    }
    return r;
  }

  static Future<void> setBeban(
      String outlet, String month, Map<String, int> v) async {
    for (final it in items) {
      await Db.setSetting(_bk(outlet, month, it[0]), '${v[it[0]] ?? 0}');
    }
  }

  // ---------- modal (%) ----------
  static Future<double> getModalPct(String outlet) async =>
      double.tryParse(await Db.getSetting(_mk(outlet)) ?? '') ?? 0;

  static Future<void> setModalPct(String outlet, double v) async =>
      Db.setSetting(_mk(outlet), v.toString());

  static String pctText(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ---------- hitungan untuk Ringkasan Penjualan ----------
  /// Outlet yang ikut dihitung sesuai pilihan outlet di bilah atas.
  static Future<List<String>> _outlets() async {
    final n = Scope.names;
    return n.isNotEmpty ? n : await Target.outlets();
  }

  /// Beban satu outlet untuk rentang [a]..[b]: Total Beban bulan yang
  /// tersentuh rentang, dipakai apa adanya (tidak dibagi per hari).
  static Future<num> bebanFor(String outlet, DateTime a, DateTime b) async {
    a = _day(a);
    b = _day(b);
    num sum = 0;
    var m = DateTime(a.year, a.month);
    while (!m.isAfter(b)) {
      sum += (await getBeban(outlet, monthKey(m)))
          .values
          .fold<int>(0, (x, y) => x + y);
      m = DateTime(m.year, m.month + 1);
    }
    return sum;
  }

  /// Satu baris: {'modal': Rp, 'beban': Rp} untuk rentang [a]..[b].
  /// Modal = persen modal tiap outlet x penjualan bersih (kotor - diskon)
  /// outlet itu.
  static Future<List<Rec>> recap(DateTime a, DateTime b) async {
    String iso(DateTime d) => d.toIso8601String().substring(0, 10);
    final sales = await Db.q(
        'SELECT outlet, COALESCE(SUM(total),0) t FROM transactions WHERE substr(created_at,1,10) BETWEEN ? AND ?${Scope.and('outlet')} GROUP BY outlet',
        [iso(a), iso(b), ...Scope.args]);
    num modal = 0;
    for (final r in sales) {
      final o = (r['outlet'] ?? '') as String;
      modal += (r['t'] as num) * (await getModalPct(o)) / 100;
    }
    num beban = 0;
    for (final o in await _outlets()) {
      beban += await bebanFor(o, a, b);
    }
    return [
      {'modal': modal.round(), 'beban': beban.round()}
    ];
  }
}

Widget _title(BuildContext c, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(t, style: Theme.of(c).textTheme.titleLarge));

Widget _note(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(t, style: const TextStyle(fontSize: 12)));

/// Belum ada outlet dipilih: tampilkan kotak outlet, ketuk satu untuk masuk.
class _OutletPicker extends StatelessWidget {
  final String title, note;
  const _OutletPicker(this.title, this.note);

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        _title(context, title),
        _note(note),
        FutureBuilder<List<Rec>>(
          future: Target.outletRows(),
          builder: (c, s) {
            if (!s.hasData) {
              return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()));
            }
            final rows = s.data!;
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
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                  ),
              ]);
            });
          },
        ),
      ]);
}

// ===================== BEBAN =====================
class BebanPage extends StatefulWidget {
  const BebanPage({super.key});
  @override
  State<BebanPage> createState() => _BebanPageState();
}

class _BebanPageState extends State<BebanPage> {
  final String outlet = AdminScope.value;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  final Map<String, TextEditingController> ctl = {
    for (final it in Rekap.items) it[0]: TextEditingController()
  };
  bool loading = true, saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in ctl.values) {
      c.addListener(() => setState(() {}));
    }
    if (outlet.isNotEmpty) _load();
  }

  @override
  void dispose() {
    for (final c in ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final v = await Rekap.getBeban(outlet, Rekap.monthKey(month));
    if (!mounted) return;
    for (final it in Rekap.items) {
      ctl[it[0]]!.text = moneyText(v[it[0]] ?? 0);
    }
    setState(() => loading = false);
  }

  void _shift(int delta) {
    setState(() => month = DateTime(month.year, month.month + delta));
    _load();
  }

  int get _total => ctl.values.fold<int>(0, (a, c) => a + moneyOf(c.text));

  Future<void> _save() async {
    setState(() => saving = true);
    await Rekap.setBeban(outlet, Rekap.monthKey(month),
        {for (final it in Rekap.items) it[0]: moneyOf(ctl[it[0]]!.text)});
    if (!mounted) return;
    setState(() => saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Beban disimpan')));
  }

  @override
  Widget build(BuildContext context) {
    if (outlet.isEmpty) {
      return const _OutletPicker('Rekapitulasi • Beban',
          'Beban diinput per outlet. Pilih outlet di bawah (atau di bilah atas).');
    }
    final bulan = Rekap.monthLabel(month);
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          _title(context, 'Rekapitulasi • Beban • $outlet'),
          _note(
              'Isi beban bulanan secara manual. Total Beban bulan ini langsung dipakai di Ringkasan Penjualan (tidak dibagi per hari), lalu dikurangkan dari pendapatan.'),
          Row(children: [
            IconButton(
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
                child: Center(
                    child: Text(bulan,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)))),
            IconButton(
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: 8),
          if (loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else ...[
            for (final it in Rekap.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: ctl[it[0]],
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: InputDecoration(
                      labelText: it[1],
                      prefixText: 'Rp. ',
                      border: const OutlineInputBorder()),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Expanded(
                      child: Text('Total Beban',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Text(rp(_total),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: saving ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('Simpan Beban')),
          ],
        ]);
  }
}

// ===================== MODAL (%) =====================
class ModalPage extends StatefulWidget {
  const ModalPage({super.key});
  @override
  State<ModalPage> createState() => _ModalPageState();
}

class _ModalPageState extends State<ModalPage> {
  final String outlet = AdminScope.value;
  final ctl = TextEditingController();
  double pct = 0;
  bool loading = true, saving = false;

  @override
  void initState() {
    super.initState();
    if (outlet.isNotEmpty) _load();
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final v = await Rekap.getModalPct(outlet);
    if (!mounted) return;
    setState(() {
      pct = v;
      ctl.text = v == 0 ? '' : Rekap.pctText(v);
      loading = false;
    });
  }

  void _fromText(String s) {
    final v = double.tryParse(s.replaceAll(',', '.')) ?? 0;
    setState(() => pct = v.clamp(0, 100).toDouble());
  }

  Future<void> _save() async {
    setState(() => saving = true);
    await Rekap.setModalPct(outlet, pct);
    if (!mounted) return;
    setState(() => saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Modal (%) disimpan')));
  }

  @override
  Widget build(BuildContext context) {
    if (outlet.isEmpty) {
      return const _OutletPicker('Rekapitulasi • Modal',
          'Persen modal diatur per outlet. Pilih outlet di bawah (atau di bilah atas).');
    }
    if (loading) return const Center(child: CircularProgressIndicator());
    const contoh = 1000000;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _title(context, 'Rekapitulasi • Modal • $outlet'),
      _note(
          'Modal dihitung sebagai persen dari penjualan bersih (Penjualan Kotor - Diskon), lalu dikurangkan di Ringkasan Penjualan.'),
      TextField(
        controller: ctl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
        ],
        decoration: const InputDecoration(
            labelText: 'Modal (%)',
            suffixText: '%',
            border: OutlineInputBorder()),
        onChanged: _fromText,
      ),
      Slider(
        value: pct,
        min: 0,
        max: 100,
        divisions: 200,
        label: '${Rekap.pctText(pct)}%',
        onChanged: (v) => setState(() {
          pct = v;
          ctl.text = v == 0 ? '' : Rekap.pctText(v);
        }),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
              'Contoh: penjualan bersih ${rp(contoh)} x ${Rekap.pctText(pct)}% = modal ${rp((contoh * pct / 100).round())}'),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
          onPressed: saving ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('Simpan Modal')),
    ]);
  }
}
