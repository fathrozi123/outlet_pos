import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'db.dart';
import 'scope.dart';

/// Halaman "Modal dan Sinkronisasi" (menu di sidebar), per outlet per tanggal.
///
/// Kartu Modal        : modal awal + keterangan. Sisa modal = modal - pengeluaran,
///                      jadi otomatis berkurang saat ada pengeluaran.
/// Kartu Sinkronisasi : Total Pendapatan (otomatis dari riwayat) - QRIS -
///                      Transfer = Cash seharusnya. Cash dihitung manual ->
///                      Plus / Balance / Minus. Tombol Sinkronkan menyimpan satu
///                      catatan baru ke riwayat (lengkap dengan jam).
/// Kartu Riwayat      : semua sinkronisasi yang pernah disimpan. Catatan ini
///                      permanen: hanya bisa dilihat, tidak bisa diubah/dihapus.
String _isoDay(DateTime d) => d.toIso8601String().substring(0, 10);
String _dmy(String iso) => DateFormat('dd/MM/yyyy').format(DateTime.parse(iso));

/// (teks, warna) hasil closing. counted null = belum closing.
(String, Color) _statusOf(int? counted, int expected) {
  if (counted == null) return ('Belum closing', Colors.grey);
  final diff = counted - expected;
  if (diff > 0) return ('PLUS ${rp(diff)}', Colors.green.shade700);
  if (diff == 0) return ('BALANCE', Colors.blue.shade700);
  return ('MINUS ${rp(-diff)}', Colors.red);
}

class ClosingPage extends StatefulWidget {
  const ClosingPage({super.key});
  @override
  State<ClosingPage> createState() => _ClosingPageState();
}

class _ClosingPageState extends State<ClosingPage> {
  DateTime day = DateTime.now();
  bool loading = true, qrisCustom = false;
  bool dirtyModal = false, savingModal = false, savingSync = false;
  int total = 0, qrisAuto = 0, jajan = 0;
  List<Rec> expenses = [], history = [];
  final modal = TextEditingController(),
      qris = TextEditingController(),
      transfer = TextEditingController(),
      counted = TextEditingController(),
      note = TextEditingController();

  /// Karyawan = outlet sendiri; admin = outlet yang dipilih di bilah atas.
  String? get outlet {
    final o = Session.isAdmin
        ? (AdminScope.isAll ? null : AdminScope.value)
        : Session.outlet;
    return (o == null || o.isEmpty) ? null : o;
  }

  bool get readOnly => Session.isAdmin; // admin hanya melihat
  String get dayIso => _isoDay(day);
  bool get isToday => dayIso == _isoDay(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [modal, qris, transfer, counted, note]) {
      c.dispose();
    }
    super.dispose();
  }

  int _v(TextEditingController c) => moneyOf(c.text);
  String _n(Object? v) => v == null ? '' : moneyText(v as num);

  int get qrisVal => _v(qris);
  int get transferVal => _v(transfer);
  int get expectedCash => total - qrisVal - transferVal;
  bool get hasCounted => counted.text.trim().isNotEmpty;
  int get spent => expenses.fold<int>(0, (a, e) => a + (e['amount'] as int));
  int get modalLeft => _v(modal) - spent;

  /// keepEdits: true = hanya segarkan angka, isian form tidak diganti.
  Future<void> _load({bool keepEdits = false}) async {
    final o = outlet;
    if (o == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    await Db.ensureCols();
    final d = await Db.db;
    final agg = (await d.rawQuery(
            "SELECT COALESCE(SUM(total + COALESCE(jajan_qty,0)*$kJajanPrice),0) tot, COALESCE(SUM(CASE WHEN payment='QRIS' THEN total ELSE 0 END),0) qris, COALESCE(SUM(jajan_qty),0) jaj FROM transactions WHERE outlet=? AND substr(created_at,1,10)=?",
            [o, dayIso]))
        .first;
    final cl = await d
        .query('closing', where: 'outlet=? AND day=?', whereArgs: [o, dayIso]);
    final ex = await d.query('expenses',
        where: 'outlet=? AND day=?', whereArgs: [o, dayIso], orderBy: 'id');
    final hist = await d.query('sync_log',
        where: 'outlet=?',
        whereArgs: [o],
        orderBy: 'created_at DESC, id DESC',
        limit: 100);
    if (!mounted) return;
    setState(() {
      total = (agg['tot'] as num).toInt();
      qrisAuto = (agg['qris'] as num).toInt();
      jajan = (agg['jaj'] as num).toInt();
      expenses = ex;
      history = hist;
      if (!keepEdits) {
        final c = cl.isEmpty ? null : cl.first;
        modal.text = _n(c?['modal']);
        _resetSyncForm();
        dirtyModal = false;
      } else if (!qrisCustom) {
        qris.text = moneyText(qrisAuto);
      }
      loading = false;
    });
  }

  /// Pastikan baris closing untuk outlet+tanggal ini ada, lalu isi kolomnya.
  /// Modal dan closing disimpan terpisah dan tidak saling menimpa.
  Future<void> _upsert(Map<String, Object?> vals) async {
    final o = outlet!;
    final d = await Db.db;
    await d.insert('closing', {'outlet': o, 'day': dayIso},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await d.update(
        'closing',
        {
          ...vals,
          'updated_by': Session.name,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'outlet=? AND day=?',
        whereArgs: [o, dayIso]);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _saveModal() async {
    if (savingModal || outlet == null) return;
    setState(() => savingModal = true);
    await _upsert({'modal': _v(modal)});
    if (!mounted) return;
    setState(() {
      savingModal = false;
      dirtyModal = false;
    });
    await _load(keepEdits: true);
    _snack('Modal disimpan');
  }

  /// Form sinkronisasi baru dikosongkan (QRIS kembali otomatis).
  void _resetSyncForm() {
    qrisCustom = false;
    qris.text = moneyText(qrisAuto);
    transfer.clear();
    counted.clear();
    note.clear();
  }

  /// Simpan satu sinkronisasi baru ke riwayat. Catatan bersifat permanen.
  Future<void> _sync() async {
    final o = outlet;
    if (savingSync || o == null || !hasCounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Simpan sinkronisasi?'),
        content: Text(
            '${_statusOf(_v(counted), expectedCash).$1}\n\nSetelah disimpan, sinkronisasi masuk riwayat dan tidak bisa diubah.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Sinkronkan')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => savingSync = true);
    final cnt = _v(counted);
    await (await Db.db).insert('sync_log', {
      'outlet': o,
      'day': dayIso,
      'created_at': DateTime.now().toIso8601String(),
      'user_name': Session.name,
      'total': total,
      'qris': qrisVal,
      'transfer': transferVal,
      'expected': expectedCash,
      'counted': cnt,
      'diff': cnt - expectedCash,
      'note': note.text.trim(),
      'modal': _v(modal),
      'spent': spent,
      'jajan': jajan,
      'spent_detail': jsonEncode([
        for (final e in expenses)
          {'amount': e['amount'], 'note': e['note'] ?? ''}
      ]),
    });
    if (!mounted) return;
    setState(() {
      savingSync = false;
      _resetSyncForm();
    });
    await _load(keepEdits: true);
    _snack('Sinkronisasi disimpan ke riwayat');
  }

  Future<void> _addExpense() async {
    final a = TextEditingController(), n = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tambah Pengeluaran'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: a,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
              decoration: const InputDecoration(
                  labelText: 'Jumlah', prefixText: 'Rp. ')),
          TextField(
              controller: n,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Keterangan', hintText: 'mis. beli payung')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    final amt = moneyOf(a.text);
    if (ok != true || amt <= 0 || outlet == null) return;
    final d = await Db.db;
    await d.insert('expenses', {
      'outlet': outlet!,
      'day': dayIso,
      'amount': amt,
      'note': n.text.trim(),
      'user_name': Session.name,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _load(keepEdits: true);
  }

  Future<void> _delExpense(Rec e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus pengeluaran?'),
        content: Text(
            '${rp(e['amount'] as int)}${(e['note'] ?? '') == '' ? '' : ' • ${e['note']}'}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    await (await Db.db).delete('expenses', where: 'id=?', whereArgs: [e['id']]);
    await _load(keepEdits: true);
  }

  void _setDay(DateTime d) {
    setState(() {
      day = d;
      loading = true;
    });
    _load();
  }

  // ---------- komponen ----------
  Widget _field(TextEditingController c,
      {required String label,
      required VoidCallback mark,
      bool money = true,
      String? helper,
      Widget? suffix,
      ValueChanged<String>? onChanged}) {
    return TextField(
      controller: c,
      enabled: !readOnly,
      keyboardType: money ? TextInputType.number : TextInputType.multiline,
      inputFormatters: money ? [MoneyInputFormatter()] : null,
      minLines: money ? 1 : 2,
      maxLines: money ? 1 : 3,
      textCapitalization:
          money ? TextCapitalization.none : TextCapitalization.sentences,
      onChanged: (v) {
        onChanged?.call(v);
        setState(mark);
      },
      decoration: InputDecoration(
        labelText: label,
        prefixText: money ? 'Rp. ' : null,
        helperText: helper,
        helperMaxLines: 2,
        suffixIcon: suffix,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _ro(String label, String value,
      {Color? color, bool bold = false, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
        ],
        Expanded(child: Text(label)),
        Text(value,
            style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                fontSize: bold ? 16 : 14,
                color: color)),
      ]),
    );
  }

  Widget _card(String title, IconData icon, List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16))),
          ]),
          const Divider(height: 20),
          ...children,
        ]),
      ),
    );
  }

  Widget _saveBtn(bool dirty, bool saving, VoidCallback onTap, String label) {
    if (readOnly) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 46,
        child: FilledButton.icon(
          onPressed: dirty && !saving ? onTap : null,
          icon: const Icon(Icons.save_outlined),
          label: Text(dirty ? label : 'Tersimpan'),
        ),
      ),
    );
  }

  Widget _statusRow() {
    final st = _statusOf(hasCounted ? _v(counted) : null, expectedCash).$1;
    Widget chip(String t, Color c, bool on) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.withValues(alpha: .15) : null,
              border: Border.all(
                  color: on ? c : Colors.grey.shade400, width: on ? 2 : 1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(t,
                style: TextStyle(
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                    color: on ? c : Colors.grey)),
          ),
        );
    return Row(children: [
      chip('Plus', Colors.green.shade700, st.startsWith('PLUS')),
      chip('Balance', Colors.blue.shade700, st == 'BALANCE'),
      chip('Minus', Colors.red, st.startsWith('MINUS')),
    ]);
  }

  // ---------- kartu ----------
  Widget _modalCard() {
    final left = modalLeft;
    return _card('Modal', Icons.account_balance_wallet_outlined, [
      _field(modal, label: 'Modal', mark: () => dirtyModal = true),
      const Divider(height: 20),
      Row(children: [
        const Expanded(
            child: Text('Pengeluaran',
                style: TextStyle(fontWeight: FontWeight.w600))),
        Text(rp(spent), style: const TextStyle(fontWeight: FontWeight.w700)),
        if (!readOnly)
          TextButton.icon(
              onPressed: _addExpense,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tambah')),
      ]),
      if (expenses.isEmpty)
        const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('Belum ada pengeluaran',
                style: TextStyle(fontSize: 12, color: Colors.grey))),
      for (final e in expenses)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Row(children: [
            Expanded(
                child: Text(
                    '${rp(e['amount'] as int)}${(e['note'] ?? '') == '' ? '' : '  (${e['note']})'}',
                    style: const TextStyle(fontSize: 13))),
            if (!readOnly)
              IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: 'Hapus',
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _delExpense(e)),
          ]),
        ),
      const Divider(height: 12),
      _ro('Modal', rp(_v(modal))),
      _ro('Pengeluaran', spent == 0 ? rp(0) : '- ${rp(spent)}',
          color: spent > 0 ? Colors.red : null),
      const Divider(height: 12),
      _ro('Sisa modal', rp(left),
          bold: true, color: left < 0 ? Colors.red : Colors.green.shade700),
      const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text('Sisa modal berkurang otomatis saat ada pengeluaran.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ),
      _saveBtn(dirtyModal, savingModal, _saveModal, 'Simpan Modal'),
    ]);
  }

  Widget _syncCard() {
    final h = hasCounted;
    final st = _statusOf(h ? _v(counted) : null, expectedCash);
    return _card('Sinkronisasi', Icons.sync, [
      _ro('Tanggal', _dmy(dayIso)),
      _ro('Total Pendapatan', rp(total), bold: true, icon: Icons.lock_outline),
      const SizedBox(height: 4),
      _field(qris,
          label: 'QRIS',
          mark: () {},
          helper: qrisCustom
              ? 'Diubah manual. Otomatis dari riwayat: ${rp(qrisAuto)}'
              : 'Otomatis dari riwayat QRIS, boleh diubah',
          suffix: qrisCustom && !readOnly
              ? IconButton(
                  tooltip: 'Kembalikan ke otomatis',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: () => setState(() {
                        qris.text = moneyText(qrisAuto);
                        qrisCustom = false;
                      }))
              : null,
          onChanged: (v) => qrisCustom = moneyOf(v) != qrisAuto),
      const SizedBox(height: 10),
      _field(transfer, label: 'Transfer', mark: () {}),
      const Divider(height: 20),
      _ro('Cash seharusnya', rp(expectedCash), bold: true),
      const SizedBox(height: 6),
      _field(counted,
          label: 'Cash dihitung (manual)',
          mark: () {},
          helper: 'Hitung uang cash di laci, lalu isi di sini'),
      const SizedBox(height: 10),
      _statusRow(),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(h ? st.$1 : 'Isi cash yang dihitung untuk melihat hasilnya',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, color: st.$2)),
      ),
      const Divider(height: 20),
      _ro('Keluar Jajan', '$jajan pcs • ${rp(jajan * kJajanPrice)}'),
      const SizedBox(height: 8),
      _field(note, label: 'Keterangan', money: false, mark: () {}),
      if (!readOnly)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            height: 46,
            child: FilledButton.icon(
              onPressed: h && !savingSync ? _sync : null,
              icon: const Icon(Icons.sync),
              label: const Text('Sinkronkan'),
            ),
          ),
        ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
            'Tiap sinkronisasi menjadi catatan baru di riwayat dan tidak bisa diubah.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ),
    ]);
  }

  /// Detail satu sinkronisasi (hanya lihat, tanpa tombol ubah/hapus).
  Future<void> _detail(Rec r) async {
    final at = DateTime.parse(r['created_at'] as String);
    final cnt = (r['counted'] as num).toInt();
    final exp = (r['expected'] as num).toInt();
    final st = _statusOf(cnt, exp);
    final md = ((r['modal'] ?? 0) as num).toInt();
    final sp = ((r['spent'] ?? 0) as num).toInt();
    final nt = ((r['note'] ?? '') as String).trim();
    // rincian pengeluaran: snapshot saat sinkronisasi; data lama diambil dari tabel pengeluaran
    List<Map> items = [];
    final sd = r['spent_detail'];
    if (sd is String && sd.isNotEmpty) {
      try {
        items = [for (final x in jsonDecode(sd) as List) Map.from(x as Map)];
      } catch (_) {}
    } else {
      final rows = await (await Db.db).query('expenses',
          where: 'outlet=? AND day=?',
          whereArgs: [r['outlet'], r['day']],
          orderBy: 'id');
      items = [for (final e in rows) Map.from(e)];
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.lock_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(DateFormat('dd/MM/yyyy HH:mm').format(at),
                  style: const TextStyle(fontSize: 17))),
        ]),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _ro('Tanggal data', _dmy(r['day'] as String)),
              _ro('Disimpan oleh', '${r['user_name'] ?? ''}'),
              const Divider(height: 16),
              _ro('Total Pendapatan', rp((r['total'] as num).toInt()),
                  bold: true),
              _ro('QRIS', rp((r['qris'] as num).toInt())),
              _ro('Transfer', rp((r['transfer'] as num).toInt())),
              _ro('Cash seharusnya', rp(exp)),
              _ro('Cash dihitung', rp(cnt)),
              _ro('Hasil', st.$1, bold: true, color: st.$2),
              const Divider(height: 16),
              _ro('Keluar Jajan',
                  '${r['jajan'] ?? 0} pcs • ${rp(((r['jajan'] ?? 0) as num).toInt() * kJajanPrice)}'),
              if (nt.isNotEmpty)
                Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Keterangan: $nt'))),
              const Divider(height: 16),
              _ro('Modal', rp(md)),
              _ro('Pengeluaran', rp(sp)),
              for (final e in items)
                Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 2),
                        child: Text(
                            '• ${rp(((e['amount'] ?? 0) as num).toInt())}${(e['note'] ?? '').toString().isEmpty ? '' : ' (${e['note']})'}',
                            style: const TextStyle(
                                fontSize: 12.5, color: Colors.grey)))),
              _ro('Sisa modal', rp(md - sp), bold: true),
            ]),
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(c), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Widget _historyCard() {
    final cs = Theme.of(context).colorScheme;
    return _card('Riwayat Sinkronisasi', Icons.history, [
      if (history.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Belum ada sinkronisasi yang tersimpan',
                style: TextStyle(color: Colors.grey))),
      for (final r in history)
        Builder(builder: (_) {
          final at = DateTime.parse(r['created_at'] as String);
          final st = _statusOf(
              (r['counted'] as num).toInt(), (r['expected'] as num).toInt());
          final md = ((r['modal'] ?? 0) as num).toInt();
          final sp = ((r['spent'] ?? 0) as num).toInt();
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              dense: true,
              onTap: () => _detail(r),
              leading: const Icon(Icons.lock_outline, size: 18),
              title: Text(DateFormat('dd/MM/yyyy • HH:mm').format(at),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${r['user_name'] ?? ''} • Pendapatan ${rp((r['total'] as num).toInt())} • Sisa modal ${rp(md - sp)}'),
              trailing: Text(st.$1,
                  style: TextStyle(fontWeight: FontWeight.w800, color: st.$2)),
            ),
          );
        }),
    ]);
  }

  // ---------- halaman ----------
  @override
  Widget build(BuildContext context) {
    final o = outlet;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
              child: Text('Modal dan Sinkronisasi${o == null ? '' : ' • $o'}',
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis)),
          if (!isToday)
            TextButton(
                onPressed: () => _setDay(DateTime.now()),
                child: const Text('Hari ini')),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(isToday ? 'Hari ini' : dayIso),
            onPressed: o == null
                ? null
                : () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: day,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now());
                    if (d != null) _setDay(d);
                  },
          ),
          IconButton(
              tooltip: 'Segarkan total',
              icon: const Icon(Icons.refresh),
              onPressed: o == null ? null : () => _load(keepEdits: true)),
        ]),
      ),
      Expanded(
        child: o == null
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Pilih satu outlet di bilah atas untuk melihat modal dan sinkronisasi.',
                        textAlign: TextAlign.center)))
            : loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    children: [
                      LayoutBuilder(builder: (c, box) {
                        if (box.maxWidth >= 700) {
                          return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _modalCard()),
                                const SizedBox(width: 12),
                                Expanded(child: _syncCard()),
                              ]);
                        }
                        return Column(children: [
                          _modalCard(),
                          const SizedBox(height: 12),
                          _syncCard(),
                        ]);
                      }),
                      const SizedBox(height: 12),
                      _historyCard(),
                    ],
                  ),
      ),
    ]);
  }
}
