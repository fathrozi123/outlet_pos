import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'attendance_photo.dart';
import 'db.dart';
import 'prefs.dart';
import 'product_image.dart';
import 'printer.dart';
import 'scope.dart';

// ===================== RIWAYAT TRANSAKSI =====================
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  // Bawaan: riwayat HARI INI. Tampilan otomatis pindah ke hari baru saat
  // lewat tengah malam (00.00), kecuali kasir sedang memilih tanggal lain.
  DateTimeRange? range = _today();
  bool follow = true;
  late Future<List<Rec>> fut;
  Timer? _midnight;
  late String _lastDate = _iso(DateTime.now());
  final _search = TextEditingController();
  String _q = '';
  int _pcs = 0, _jajanTotal = 0; // ringkasan hasil pencarian
  int _seq = 0; // pencarian terbaru yang boleh mengisi ringkasan

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  static DateTimeRange _today() {
    final n = DateTime.now();
    return DateTimeRange(start: n, end: n);
  }

  static String _dm(DateTime d) =>
      _iso(d).substring(5).split('-').reversed.join('/');

  String get _rangeLabel => range == null
      ? 'Semua tanggal'
      : _iso(range!.start) == _iso(range!.end)
          ? _iso(range!.start)
          : '${_dm(range!.start)} - ${_dm(range!.end)}';

  @override
  void initState() {
    super.initState();
    _load();
    _midnight = Timer.periodic(const Duration(seconds: 20), (_) {
      final n = _iso(DateTime.now());
      if (n == _lastDate) return;
      _lastDate = n; // tanggal berganti
      if (follow && mounted) {
        setState(() {
          range = _today();
          _load();
        });
      } else if (mounted) {
        setState(_load); // tanggal berganti: segarkan (batas tanggal 3)
      }
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _load() {
    final w = <String>[];
    final a = <Object?>[];
    if (!Session.isAdmin) {
      // Riwayat dibagi satu outlet: semua akun di toko yang sama melihat
      // transaksi yang sama (kasirnya tetap tertulis di tiap baris).
      w.add('outlet=?');
      a.add(Session.outlet);
      // Akun karyawan: riwayat "hilang" tiap tanggal 3 jam 00:00 (hanya
      // disembunyikan; data tetap utuh untuk admin, laporan, dan closing).
      final now = DateTime.now();
      final cutoff = now.day >= 3
          ? DateTime(now.year, now.month, 3)
          : DateTime(now.year, now.month - 1, 3);
      w.add('created_at >= ?');
      a.add(cutoff.toIso8601String());
    } else if (Scope.restricted ||
        !AdminScope.isAll ||
        AdminScope.groupId != 0) {
      // Admin: transaksi outlet yang dipilih di bilah atas. Mitra: hanya
      // outlet miliknya (semua outlet miliknya kalau tidak memilih satu).
      w.add(Scope.cond('outlet'));
      a.addAll(Scope.args);
    }
    if (range != null) {
      w.add('substr(created_at,1,10) BETWEEN ? AND ?');
      a.add(_iso(range!.start));
      a.add(_iso(range!.end));
    }
    final q = _q.trim().toLowerCase();
    // "jajan" dianggap cocok kalau kata yang dicari bagian dari kata jajan
    final jajanHit = q.isNotEmpty && 'jajan'.contains(q);
    if (q.isNotEmpty) {
      w.add(
          "(code LIKE ? OR user_name LIKE ? OR id IN (SELECT trx_id FROM transaction_items WHERE product_name LIKE ? OR kemasan LIKE ?)${jajanHit ? ' OR jajan_qty>0' : ''})");
      a.addAll(List.filled(4, '%$q%'));
    }
    final sql =
        'SELECT * FROM transactions ${w.isEmpty ? '' : 'WHERE ${w.join(' AND ')}'} ORDER BY created_at DESC LIMIT 1000';
    final args = List<Object?>.of(a);
    final my = ++_seq;
    fut = (() async {
      await Db.ensureCols(); // kolom jajan_qty harus ada sebelum dicari
      final rows = await Db.q(sql, args);
      int pcs = 0, jaj = 0;
      if (q.isNotEmpty && rows.isNotEmpty) {
        final ids = rows.map((e) => e['id'] as int).join(',');
        final r = await Db.q(
            'SELECT COALESCE(SUM(qty),0) n FROM transaction_items WHERE trx_id IN ($ids) AND (product_name LIKE ? OR kemasan LIKE ?)',
            ['%$q%', '%$q%']);
        pcs = ((r.first['n'] ?? 0) as num).toInt();
        if (jajanHit) {
          jaj = rows.fold<int>(0, (x, e) => x + jajanOf(e));
        }
      }
      if (my == _seq) {
        _pcs = pcs;
        _jajanTotal = jaj;
      }
      return rows;
    })();
  }

  Future<void> _detail(Rec h) async {
    final t = await Db.trx(h['id'] as int);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t['code'] as String),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${fmtDt(t['created_at'] as String)} • ${t['user_name']} • ${t['outlet']}'),
              const Divider(),
              for (final i in t['items'] as List)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                            '${(i as Map)['product_name']}${kemTag(i['kemasan'] as String?)} x${i['qty']}${(i['note'] ?? '').toString().trim().isEmpty ? '' : '\nCatatan: ${i['note']}'}')),
                    Text(rp(i['subtotal'] as int)),
                  ]),
                ),
              const Divider(),
              Text('Subtotal: ${rp(t['subtotal'] as int)}'),
              if ((t['discount_amt'] as int) > 0)
                Text(
                    'Diskon ${t['discount_pct']}%: -${rp(t['discount_amt'] as int)}'),
              Text('Total: ${rp(t['total'] as int)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (t['payment'] == 'QRIS')
                const Text('Pembayaran: QRIS (lunas)')
              else
                Text(
                    'Tunai: ${rp(t['cash'] as int)}  •  Kembali: ${rp(t['change_amt'] as int)}'),
              if (jajanOf(t) > 0)
                Text(
                    'Jajan ${rp(kJajanPrice)} × ${jajanOf(t)} = ${rp(jajanOf(t) * kJajanPrice)}  •  Kembali uang: ${rp((t['change_amt'] as int) - jajanOf(t) * kJajanPrice)}'),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final ok = await Printer.printTrx(t);
              if (!c.mounted) return;
              ScaffoldMessenger.of(c).showSnackBar(SnackBar(
                  content: Text(
                      ok ? 'Nota dicetak' : 'Gagal mencetak, cek printer')));
            },
            child: const Text('Cetak ulang'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(c), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Widget _column(String title, IconData icon, List<Rec> rows,
      {bool showMethod = false}) {
    final cs = Theme.of(context).colorScheme;
    final sum = rows.fold<int>(0, (a, e) => a + trxMoney(e));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                Text('${rows.length} transaksi • ${rp(sum)}',
                    style: TextStyle(fontSize: 12, color: cs.outline)),
              ])),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: rows.isEmpty
            ? const Center(child: Text('Belum ada transaksi'))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final h = rows[i];
                  final isQ = h['payment'] == 'QRIS';
                  return ListTile(
                    dense: true,
                    isThreeLine: true,
                    title: Text(rp(trxMoney(h)),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${h['code']}\n${fmtDt(h['created_at'] as String)} • ${h['user_name']}${Session.isAdmin ? ' • ${h['outlet']}' : ''}${(h['discount_amt'] as int) > 0 ? ' • diskon ${h['discount_pct']}%' : ''}${showMethod && isQ ? ' • QRIS' : ''}${jajanOf(h) > 0 ? ' • termasuk jajan ×${jajanOf(h)} (${rp(jajanOf(h) * kJajanPrice)})' : ''}'),
                    onTap: () => _detail(h),
                  );
                },
              ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
                child: Text(
                    'Riwayat Transaksi${Session.isAdmin && !AdminScope.isAll ? ' • ${AdminScope.value}' : ''}',
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis)),
            if (!follow)
              TextButton(
                  onPressed: () => setState(() {
                        follow = true;
                        range = _today();
                        _load();
                      }),
                  child: const Text('Hari ini')),
            if (!(range == null && !follow))
              TextButton(
                  onPressed: () => setState(() {
                        follow = false;
                        range = null;
                        _load();
                      }),
                  child: const Text('Semua')),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(follow ? 'Hari ini' : _rangeLabel),
              onPressed: () async {
                final now = DateTime.now();
                final r = await showDateRangePicker(
                    context: context,
                    initialDateRange: range ?? _today(),
                    firstDate: DateTime(2024),
                    lastDate: now,
                    helpText: 'Pilih rentang tanggal',
                    saveText: 'Terapkan');
                if (r != null) {
                  setState(() {
                    range = r;
                    follow =
                        _iso(r.start) == _iso(now) && _iso(r.end) == _iso(now);
                    _load();
                  });
                }
              },
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() {
              _q = v;
              _load();
            }),
            decoration: InputDecoration(
              hintText: 'Cari produk, jajan, kode, atau kasir',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                            _search.clear();
                            _q = '';
                            _load();
                          })),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Rec>>(
            future: fut,
            builder: (c, s) {
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = s.data!;
              final qr = all.where((e) => e['payment'] == 'QRIS').toList();
              final cs = Theme.of(c).colorScheme;
              final searching = _q.trim().isNotEmpty;
              // kiri: transaksi QRIS, kanan: total semua transaksi
              return Column(children: [
                if (searching)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: cs.secondaryContainer.withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        'Hasil "${_q.trim()}": ${all.length} transaksi'
                        '${_pcs > 0 ? ' • $_pcs item terjual' : ''}'
                        '${_jajanTotal > 0 ? ' • $_jajanTotal jajan (${rp(_jajanTotal * kJajanPrice)})' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                Expanded(
                  child: LayoutBuilder(builder: (c, box) {
                    if (box.maxWidth >= 600) {
                      return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                                child: Card(
                              margin: const EdgeInsets.fromLTRB(12, 0, 6, 12),
                              clipBehavior: Clip.antiAlias,
                              child: _column(
                                  'Transaksi QRIS', Icons.qr_code_2, qr),
                            )),
                            Expanded(
                                child: Card(
                              margin: const EdgeInsets.fromLTRB(6, 0, 12, 12),
                              clipBehavior: Clip.antiAlias,
                              child: _column(
                                  'Total Transaksi', Icons.receipt_long, all,
                                  showMethod: true),
                            )),
                          ]);
                    }
                    return DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: TabBar(
                                indicatorSize: TabBarIndicatorSize.tab,
                                indicator: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                labelColor: Colors.white,
                                unselectedLabelColor: const Color(0xFF5A4444),
                                labelStyle: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                                tabs: [
                                  Tab(text: 'Semua (${all.length})'),
                                  Tab(text: 'QRIS (${qr.length})'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Card(
                              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              clipBehavior: Clip.antiAlias,
                              child: TabBarView(
                                children: [
                                  _column('Total Transaksi', Icons.receipt_long,
                                      all,
                                      showMethod: true),
                                  _column(
                                      'Transaksi QRIS', Icons.qr_code_2, qr),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ]);
            },
          ),
        ),
      ]);
}

// ===================== AKUN: CHECK IN / OUT =====================
class AccountPage extends StatefulWidget {
  final VoidCallback onLogout;
  const AccountPage({super.key, required this.onLogout});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Rec? openRec;
  List<Rec> recent = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Db.ensureCols();
    final r = await Db.q(
        'SELECT * FROM attendance WHERE user_id=? ORDER BY check_in DESC LIMIT 30',
        [Session.id]);
    if (!mounted) return;
    setState(() {
      recent = r;
      openRec = r.where((e) => e['check_out'] == null).firstOrNull;
    });
  }

  bool busy = false;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Ambil foto langsung dari kamera. null = dibatalkan / kamera gagal.
  Future<String?> _photo(String what) async {
    try {
      final path = await AttendancePhoto.capture();
      if (path == null && mounted) {
        _snack('$what dibatalkan. Foto dari kamera wajib untuk absen');
      }
      return path;
    } catch (_) {
      if (mounted) {
        _snack(
            'Kamera tidak bisa dibuka. Izinkan akses kamera untuk aplikasi ini lalu coba lagi');
      }
      return null;
    }
  }

  Future<void> _checkIn() async {
    if (busy) return;
    await Db.ensureCols();
    setState(() => busy = true);
    final path = await _photo('Check in');
    if (path != null) {
      await (await Db.db).insert('attendance', {
        'user_id': Session.id,
        'check_in': DateTime.now().toIso8601String(),
        'photo_in': path,
      });
    }
    if (mounted) setState(() => busy = false);
    _load();
  }

  Future<void> _checkOut() async {
    if (busy) return;
    await Db.ensureCols();
    setState(() => busy = true);
    final path = await _photo('Check out');
    if (path != null) {
      await (await Db.db).update('attendance',
          {'check_out': DateTime.now().toIso8601String(), 'photo_out': path},
          where: 'id=?', whereArgs: [openRec!['id']]);
    }
    if (mounted) setState(() => busy = false);
    _load();
  }

  String? get _profilePath => Session.user?['photo_path'] as String?;
  bool get _hasPhoto =>
      _profilePath != null &&
      _profilePath!.isNotEmpty &&
      File(_profilePath!).existsSync();

  Future<void> _savePhoto(String? path) async {
    await Db.ensureCols();
    await (await Db.db).update('users', {'photo_path': path},
        where: 'id=?', whereArgs: [Session.id]);
    Session.user = {...Session.user!, 'photo_path': path};
    if (mounted) setState(() {});
  }

  /// Tambah / ganti / hapus foto profil akun.
  Future<void> _photoMenu() async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Ambil foto'),
              onTap: () => Navigator.pop(c, 'cam')),
          ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pilih dari galeri'),
              onTap: () => Navigator.pop(c, 'gal')),
          if (_hasPhoto)
            ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Hapus foto profil'),
                onTap: () => Navigator.pop(c, 'del')),
        ]),
      ),
    );
    if (act == null) return;
    try {
      if (act == 'del') {
        final old = _profilePath;
        await _savePhoto(null);
        await ProductImage.remove(old);
        _snack('Foto profil dihapus');
        return;
      }
      final path = await ProductImage.pick(
          act == 'cam' ? ImageSource.camera : ImageSource.gallery);
      if (path == null) return;
      final old = _profilePath;
      await _savePhoto(path);
      await ProductImage.remove(old);
      _snack('Foto profil disimpan');
    } catch (_) {
      _snack('Foto tidak bisa diambil. Cek izin kamera/galeri lalu coba lagi');
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        Text('Akun', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: GestureDetector(
              onTap: _photoMenu,
              child: Stack(clipBehavior: Clip.none, children: [
                CircleAvatar(
                  radius: 26,
                  backgroundImage:
                      _hasPhoto ? FileImage(File(_profilePath!)) : null,
                  child: _hasPhoto ? null : const Icon(Icons.person),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.camera_alt,
                        size: 12, color: Colors.white),
                  ),
                ),
              ]),
            ),
            trailing: TextButton(
                onPressed: _photoMenu,
                child: Text(_hasPhoto ? 'Ubah foto' : 'Tambah foto')),
            title: Text(Session.name),
            subtitle: Text(Session.isAdmin
                ? Session.roleLabel
                : 'Karyawan • ${Session.outlet}'),
          ),
        ),
        if (!Session.isAdmin) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(
                    openRec == null
                        ? 'Belum check in'
                        : 'Check in sejak ${fmtDt(openRec!['check_in'] as String)}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FilledButton.icon(
                      onPressed: openRec == null && !busy ? _checkIn : null,
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Check In')),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                      onPressed: openRec != null && !busy ? _checkOut : null,
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Check Out')),
                ]),
                const SizedBox(height: 8),
                const Text('Absen memakai foto langsung dari kamera',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text('Riwayat absensi',
              style: Theme.of(context).textTheme.titleMedium),
          for (final r in recent)
            ListTile(
              dense: true,
              leading: const Icon(Icons.access_time),
              title: Text('Masuk ${fmtDt(r['check_in'] as String)}'),
              subtitle: Text(r['check_out'] == null
                  ? 'Belum check out'
                  : 'Keluar ${fmtDt(r['check_out'] as String)}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                AttendancePhoto.chip(context, r['photo_in'] as String?, 'Masuk',
                    'Masuk ${fmtDt(r['check_in'] as String)}',
                    size: 36),
                if (r['check_out'] != null)
                  AttendancePhoto.chip(context, r['photo_out'] as String?,
                      'Keluar', 'Keluar ${fmtDt(r['check_out'] as String)}',
                      size: 36),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Keluar')),
      ]);
}

// ===================== PENGATURAN =====================

class SettingsPage extends StatefulWidget {
  final VoidCallback onLogout;
  const SettingsPage({super.key, required this.onLogout});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String paper = '58';
  String printerName = '', printerMac = '';
  bool connected = false;
  List<BluetoothInfo> devices = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    paper = await Db.getSetting('paper') ?? '58';
    printerName = await Db.getSetting('printer_name') ?? '';
    printerMac = await Db.getSetting('printer_mac') ?? '';
    connected = await Printer.isConnected();
    if (mounted) setState(() {});
  }

  void _msg(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  // ---------- printer ----------
  Future<void> _scan() async {
    final d = await Printer.paired();
    if (!mounted) return;
    setState(() => devices = d);
    if (d.isEmpty) {
      _msg(
          'Tidak ada printer. Pairing dulu lewat Pengaturan Bluetooth HP/tablet.');
    }
  }

  Future<void> _connect(BluetoothInfo b) async {
    final ok = await Printer.connect(b.macAdress);
    if (ok) {
      await Db.setSetting('printer_mac', b.macAdress);
      await Db.setSetting('printer_name', b.name);
      printerMac = b.macAdress;
      printerName = b.name;
    }
    if (!mounted) return;
    setState(() => connected = ok);
    _msg(ok
        ? 'Terhubung ke ${b.name}'
        : 'Gagal terhubung, pastikan printer menyala');
  }

  // ---------- dialog ----------
  Future<String?> _choose(String title, Map<String, String> opts, String cur) =>
      showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800))),
            for (final e in opts.entries)
              ListTile(
                title: Text(e.value),
                trailing: e.key == cur
                    ? Icon(Icons.check, color: Theme.of(c).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(c, e.key),
              ),
          ]),
        ),
      );

  Future<void> _pwDialog() async {
    final o = TextEditingController(), n = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Ganti Password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: o,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password lama')),
          TextField(
              controller: n,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Password baru (min. 4 karakter)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await Db.login(Session.user!['username'] as String, o.text);
    if (!mounted) return;
    if (r == null) return _msg('Password lama salah');
    if (n.text.length < 4) return _msg('Password baru minimal 4 karakter');
    await (await Db.db).update(
        'users', {'password': hashPw(n.text), 'pw_plain': n.text},
        where: 'id=?', whereArgs: [Session.id]);
    if (mounted) _msg('Password diganti');
  }

  // ---------- komponen tampilan ----------
  Widget _sec(String t) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 4),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _row(String label,
      {String? value, String? sub, VoidCallback? onTap, Widget? trailing}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant))),
        child: Row(children: [
          Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label),
              if (sub != null)
                Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub,
                        style: TextStyle(fontSize: 12, color: cs.outline))),
            ]),
          ),
          if (trailing != null)
            trailing
          else ...[
            if (value != null)
              Flexible(
                flex: 2,
                child: Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: onTap == null ? cs.outline : cs.primary)),
              ),
            if (onTap != null) Icon(Icons.chevron_right, color: cs.outline),
          ],
        ]),
      ),
    );
  }

  List<Widget> _left() {
    final cs = Theme.of(context).colorScheme;
    return [
      _sec('Printer Thermal Bluetooth'),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hubungkan printer untuk mencetak nota',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
              const SizedBox(height: 10),
              Text(connected ? 'Terhubung' : 'Belum terhubung',
                  style:
                      TextStyle(color: connected ? Colors.green : cs.outline)),
              Text(
                  printerName.isEmpty
                      ? 'Belum ada printer dipilih'
                      : printerName,
                  style: const TextStyle(fontSize: 12)),
            ]),
          ),
          Column(children: [
            FilledButton(onPressed: _scan, child: const Text('Cari Printer')),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: () async {
                final ok = await Printer.printTest();
                _msg(
                    ok ? 'Tes cetak dikirim' : 'Gagal, hubungkan printer dulu');
              },
              child: const Text('Tes Cetak'),
            ),
          ]),
        ]),
      ),
      for (final d in devices)
        ListTile(
          dense: true,
          leading: const Icon(Icons.bluetooth),
          title: Text(d.name),
          subtitle: Text(d.macAdress),
          onTap: () => _connect(d),
        ),
      _row('Ukuran Kertas', value: '$paper mm', onTap: () async {
        final v = await _choose(
            'Ukuran Kertas', {'58': '58 mm', '80': '80 mm'}, paper);
        if (v == null) return;
        await Db.setSetting('paper', v);
        setState(() => paper = v);
      }),
      _sec('Halaman Transaksi'),
      _row('Tampilan Kategori',
          value: Prefs.kategori.value == 'kompak' ? 'Kompak' : 'Reguler',
          onTap: () async {
        final v = await _choose('Tampilan Kategori',
            {'reguler': 'Reguler', 'kompak': 'Kompak'}, Prefs.kategori.value);
        if (v == null) return;
        await Prefs.setKategori(v);
        setState(() {});
      }),
      _row('Tampilan Katalog',
          value: Prefs.katalog.value == 'daftar' ? 'Daftar' : 'Grid',
          onTap: () async {
        final v = await _choose('Tampilan Katalog',
            {'grid': 'Grid', 'daftar': 'Daftar'}, Prefs.katalog.value);
        if (v == null) return;
        await Prefs.setKatalog(v);
        setState(() {});
      }),
      _row('Ukuran Grid Katalog', value: '${Prefs.kolom.value} Kolom',
          onTap: () async {
        final v = await _choose(
            'Ukuran Grid Katalog',
            {
              for (final k in [2, 3, 4, 5, 6]) '$k': '$k Kolom'
            },
            '${Prefs.kolom.value}');
        if (v == null) return;
        await Prefs.setKolom(int.parse(v));
        setState(() {});
      }),
      _row('Tambah Multi Varian',
          sub:
              'Kamu bisa menambahkan multi varian langsung ke dalam keranjang. (Segera hadir)',
          trailing: const Switch(value: false, onChanged: null)),
    ];
  }

  List<Widget> _right() => [
        _sec('Umum'),
        _row('Bahasa', value: 'Indonesia'),
        _sec('Halaman Pembayaran'),
        _row('Pajak', value: 'Belum tersedia'),
        _sec('Akun'),
        _row('Ganti Password', onTap: _pwDialog),
      ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700;
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(children: [
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _left())),
            const SizedBox(width: 32),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _right())),
          ])
        else
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [..._left(), ..._right()]),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: cs.outlineVariant),
            ),
            onPressed: widget.onLogout,
            child: const Text('Keluar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}
