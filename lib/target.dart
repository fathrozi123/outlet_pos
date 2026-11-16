import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db.dart';
import 'scope.dart';

/// Target penjualan kemasan harian, terpisah untuk tiap outlet.
class Target {
  static const names = ['Kecil', 'Normal', 'Besar'];
  static const defaults = [15, 39, 39]; // target bawaan outlet baru

  /// Kemasan yang TIDAK bisa dijual lagi saat target hari ini terpenuhi
  /// (tampil "Stok habis"). Normal dan Besar tetap bisa dijual.
  static const limited = {'Kecil'};

  /// Sisa kemasan yang masih boleh dijual untuk satu kemasan. null = tanpa batas
  /// (topping, kresek, dan item tanpa kemasan).
  /// Untuk Kecil/Normal/Besar batasnya adalah STOK KEMASAN outlet: stok 0 =
  /// tidak bisa dijual. Khusus Kecil, batas juga dipotong sisa target harian
  /// (kuota kembali penuh otomatis saat tanggal berganti 00.00 atau kalau
  /// admin menaikkan target).
  static Future<int?> left(String outlet, String kemasan) async {
    if (!names.contains(kemasan)) return null;
    if (outlet.isEmpty) return null; // akun tanpa outlet tidak dibatasi stok
    var r = (await stock(outlet))[kemasan] ?? 0;
    if (limited.contains(kemasan)) {
      final t = (await get(outlet))[kemasan] ?? 0;
      if (t > 0) {
        final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final s = (await sold(outlet, day))[kemasan] ?? 0;
        final q = (t - s).clamp(0, t).toInt();
        if (q < r) r = q;
      }
    }
    return r < 0 ? 0 : r;
  }

  static String key(String outlet, String n) =>
      'target|$outlet|${n.toLowerCase()}';

  static String myOutlet() {
    return Session.outlet;
  }

  static Future<Map<String, int>> get(String outlet) async {
    final r = <String, int>{};
    for (var i = 0; i < 3; i++) {
      r[names[i]] =
          int.tryParse(await Db.getSetting(key(outlet, names[i])) ?? '') ??
              defaults[i];
    }
    return r;
  }

  static Future<void> set(String outlet, Map<String, int> v) async {
    for (final n in names) {
      await Db.setSetting(key(outlet, n), '${v[n] ?? 0}');
    }
  }

  /// Jumlah terjual pada tanggal [day] (yyyy-MM-dd) untuk satu outlet.
  static Future<Map<String, int>> sold(String outlet, String day) async {
    final byOutlet = outlet.isNotEmpty;
    final rows = await Db.q(
        "SELECT kemasan, COALESCE(SUM(qty),0) q FROM transaction_items WHERE kemasan IN ('Kecil','Normal','Besar') AND trx_id IN (SELECT id FROM transactions WHERE substr(created_at,1,10)=?${byOutlet ? ' AND outlet=?' : ''}) GROUP BY kemasan",
        [day, if (byOutlet) outlet]);
    return {
      for (final r in rows) r['kemasan'] as String: (r['q'] as num).toInt()
    };
  }

  static Future<List<String>> outlets() async {
    await Db.ensureV3();
    final r = await Db.q('SELECT name FROM outlets ORDER BY name');
    final all = [for (final o in r) o['name'] as String];
    final m = Scope.mine; // mitra hanya melihat outlet miliknya
    return m == null
        ? all
        : [
            for (final o in all)
              if (m.contains(o)) o
          ];
  }

  static Future<List<Rec>> outletRows() async {
    await Db.ensureV3();
    final rows = await Db.q(
        'SELECT o.name, o.group_id, o.sub_required, o.sub_until, (SELECT COUNT(*) FROM users u WHERE u.outlet=o.name) AS staff, (SELECT m.name FROM users m WHERE m.id=o.owner_id) AS owner FROM outlets o ORDER BY o.name');
    final m = Scope.mine;
    return m == null
        ? rows
        : [
            for (final r in rows)
              if (m.contains(r['name'])) r
          ];
  }

  /// Semua kelompok outlet (Outlet Pusat dulu, lalu Mitra), lengkap dengan
  /// nama akun mitra yang terhubung.
  static Future<List<Rec>> groupRows() async {
    await Db.ensureV3();
    return Db.q(
        "SELECT g.id, g.name, g.kind, g.owner_id, (SELECT u.name FROM users u WHERE u.id=g.owner_id) AS owner FROM outlet_groups g ORDER BY CASE g.kind WHEN 'pusat' THEN 0 ELSE 1 END, g.name");
  }

  // ---------- stok kemasan per outlet ----------
  static Future<Map<String, int>> stock(String outlet) async {
    await Db.ensureV3();
    final rows = await Db.q(
        'SELECT kemasan, qty FROM kemasan_stock WHERE outlet=?', [outlet]);
    final m = {for (final n in names) n: 0};
    for (final r in rows) {
      final k = r['kemasan'] as String;
      if (m.containsKey(k)) m[k] = (r['qty'] as num).toInt();
    }
    return m;
  }

  static Future<void> adjustStock(
      String outlet, String kemasan, int delta) async {
    await Db.ensureV3();
    final d = await Db.db;
    await d.execute(
        'INSERT OR IGNORE INTO kemasan_stock(outlet, kemasan, qty) VALUES(?,?,0)',
        [outlet, kemasan]);
    await d.execute(
        'UPDATE kemasan_stock SET qty = MAX(qty + ?, 0) WHERE outlet=? AND kemasan=?',
        [delta, outlet, kemasan]);
  }

  static Future<void> setStock(String outlet, String kemasan, int qty) async {
    await Db.ensureV3();
    final d = await Db.db;
    await d.execute(
        'INSERT OR IGNORE INTO kemasan_stock(outlet, kemasan, qty) VALUES(?,?,0)',
        [outlet, kemasan]);
    await d.execute(
        'UPDATE kemasan_stock SET qty=? WHERE outlet=? AND kemasan=?',
        [qty, outlet, kemasan]);
  }

  // ---------- kemasan Jumat Promo (diambil dari kemasan Normal) ----------
  static const promoKey = 'Jumat Promo';

  static Future<int> promoStock(String outlet) async {
    await Db.ensureV3();
    final r = await Db.q(
        'SELECT qty FROM kemasan_stock WHERE outlet=? AND kemasan=?',
        [outlet, promoKey]);
    return r.isEmpty ? 0 : (r.first['qty'] as num).toInt();
  }

  /// Stok kemasan Jumat Promo (yang ditambahkan karyawan) dan jumlah yang
  /// sudah dibagikan gratis pada tanggal [day] (yyyy-MM-dd).
  /// Outlet kosong = semua outlet dijumlahkan.
  static Future<Map<String, int>> promoInfo(String outlet, String day) async {
    await Db.ensureV3();
    final byOutlet = outlet.isNotEmpty;
    final st = await Db.q(
        'SELECT COALESCE(SUM(qty),0) q FROM kemasan_stock WHERE kemasan=?${byOutlet ? ' AND outlet=?' : ''}',
        [promoKey, if (byOutlet) outlet]);
    final us = await Db.q(
        "SELECT COALESCE(SUM(qty),0) q FROM transaction_items WHERE product_name=? AND trx_id IN (SELECT id FROM transactions WHERE substr(created_at,1,10)=?${byOutlet ? ' AND outlet=?' : ''})",
        [kPromoProduct, day, if (byOutlet) outlet]);
    return {
      'stock': st.isEmpty ? 0 : (st.first['q'] as num).toInt(),
      'used': us.isEmpty ? 0 : (us.first['q'] as num).toInt(),
    };
  }

  /// delta +1: satu kemasan Normal dialihkan menjadi Jumat Promo (Normal
  /// langsung berkurang). delta -1: dikembalikan ke Normal.
  /// Mengembalikan pesan kesalahan, atau null kalau berhasil.
  static Future<String?> movePromo(String outlet, int delta) async {
    await Db.ensureV3();
    final d = await Db.db;
    String? err;
    await d.transaction((t) async {
      for (final k in ['Normal', promoKey]) {
        await t.execute(
            'INSERT OR IGNORE INTO kemasan_stock(outlet, kemasan, qty) VALUES(?,?,0)',
            [outlet, k]);
      }
      final rows = await t.rawQuery(
          'SELECT kemasan, qty FROM kemasan_stock WHERE outlet=? AND kemasan IN (?,?)',
          [outlet, 'Normal', promoKey]);
      int normal = 0, promo = 0;
      for (final r in rows) {
        final q = (r['qty'] as num).toInt();
        if (r['kemasan'] == 'Normal') normal = q;
        if (r['kemasan'] == promoKey) promo = q;
      }
      if (delta > 0 && normal < delta) {
        err = 'Stok kemasan Normal habis';
        return;
      }
      if (delta < 0 && promo < -delta) {
        err = 'Kemasan Jumat Promo sudah 0';
        return;
      }
      await t.execute(
          'UPDATE kemasan_stock SET qty = qty - ? WHERE outlet=? AND kemasan=?',
          [delta, outlet, 'Normal']);
      await t.execute(
          'UPDATE kemasan_stock SET qty = qty + ? WHERE outlet=? AND kemasan=?',
          [delta, outlet, promoKey]);
    });
    return err;
  }

  /// Dialog admin: tambah / kurangi / atur jumlah stok kemasan satu outlet.
  static Future<void> adjustDialog(BuildContext context, String outlet) async {
    final cur = await stock(outlet);
    final ctl = {for (final n in names) n: TextEditingController()};
    String mode = 'add';
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, ss) => AlertDialog(
          title: Text('Stok Kemasan${outlet.isEmpty ? '' : ' • $outlet'}'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    foregroundColor: Color(0xFF97291F),
                    selectedForegroundColor: Color(0xFF97291F),
                    backgroundColor: Colors.white,
                    selectedBackgroundColor: const Color(0xFFF6E1DF),
                    side: const BorderSide(color: Color(0xFF97291F)),
                  ),
                  segments: const [
                    ButtonSegment(value: 'add', label: Text('Tambah')),
                    ButtonSegment(value: 'sub', label: Text('Kurangi')),
                    ButtonSegment(value: 'set', label: Text('Atur')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (v) => ss(() => mode = v.first),
                ),
                const SizedBox(height: 8),
                for (final n in names)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      controller: ctl[n],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: '$n  (stok sekarang: ${cur[n]})'),
                    ),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    for (final n in names) {
      final v = int.tryParse(ctl[n]!.text.trim());
      if (v == null || v < 0) continue;
      if (mode == 'set') {
        await setStock(outlet, n, v);
      } else {
        await adjustStock(outlet, n, mode == 'add' ? v : -v);
      }
    }
  }

  static Future<void> edit(BuildContext context, String outlet) async {
    final cur = await get(outlet);
    final ctl = {
      for (final n in names) n: TextEditingController(text: '${cur[n]}')
    };
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Target Harian${outlet.isEmpty ? '' : ' • $outlet'}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final n in names)
            TextField(
              controller: ctl[n],
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Target $n (per hari)'),
            ),
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
    await set(outlet, {
      for (final n in names)
        n: (int.tryParse(ctl[n]!.text.trim()) ?? cur[n]!).abs()
    });
  }
}

/// Kartu target harian untuk SATU outlet. Hitungan diambil dari transaksi
/// hari ini, jadi otomatis mulai dari 0 saat tanggal berganti (00.00).
/// Stok Kecil/Normal/Besar TIDAK ditampilkan di kartu (dilihat pegawai di
/// menu "Stok Kemasan", diatur admin lewat tombol "Atur stok kemasan").
/// Pengecualian: kotak "Jumat Promo" menampilkan stok promo yang ditambahkan
/// karyawan beserta jumlah yang sudah dibagikan hari ini.
class TargetCard extends StatefulWidget {
  final String outlet;
  final ValueNotifier<int>? tick; // dinaikkan untuk memuat ulang
  final bool big;
  final VoidCallback? onEdit; // kalau diisi: tampil tombol ubah target (admin)
  final VoidCallback?
      onStock; // kalau diisi: tampil tombol atur stok kemasan (admin)
  const TargetCard(
      {super.key,
      required this.outlet,
      this.tick,
      this.big = false,
      this.onEdit,
      this.onStock});
  @override
  State<TargetCard> createState() => _TargetCardState();
}

class _TargetCardState extends State<TargetCard> {
  final sold = <String, int>{};
  final target = <String, int>{};
  int promoStock = 0; // stok kemasan Jumat Promo yang ditambah karyawan
  int promoUsed = 0; // Jumat Promo yang sudah dibagikan hari ini
  Timer? _t;

  @override
  void initState() {
    super.initState();
    widget.tick?.addListener(_load);
    // Muat ulang tiap 30 detik: angka ikut ter-reset saat tanggal berganti,
    // dan kartu di admin ikut menampilkan penjualan terbaru.
    _t = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    _load();
  }

  @override
  void dispose() {
    widget.tick?.removeListener(_load);
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final s = await Target.sold(widget.outlet, day);
    final t = await Target.get(widget.outlet);
    final p = await Target.promoInfo(widget.outlet, day);
    if (!mounted) return;
    setState(() {
      promoStock = p['stock'] ?? 0;
      promoUsed = p['used'] ?? 0;
      sold
        ..clear()
        ..addAll(s);
      target
        ..clear()
        ..addAll(t);
    });
  }

  /// Isi kartu menyesuaikan ruang yang tersedia pada tampilan besar/layar sempit.
  /// FittedBox mencegah Column melampaui tinggi kartu.
  Widget _fit(bool scaleDown, Widget c) => scaleDown
      ? LayoutBuilder(
          builder: (_, bc) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: SizedBox(width: bc.maxWidth, child: c)))
      : c;

  Widget _seg(String n, ColorScheme cs, bool big, {bool narrow = false}) {
    final s = sold[n] ?? 0;
    final t = target[n] ?? 0;
    final done = t > 0 && s >= t;
    final left = (t - s).clamp(0, t).toInt();
    final pct = t == 0 ? 0.0 : (s / t).clamp(0.0, 1.0).toDouble();
    // Kecil: kuota habis = stok habis (merah). Normal/Besar tetap "tercapai".
    final habis = done && Target.limited.contains(n);
    final color =
        habis ? Color(0xFF97291F) : (done ? Colors.green : cs.primary);
    // Layar sempit (HP) pada tampilan besar: kartu ditumpuk ke bawah, ukuran diperkecil.
    final pad = narrow ? 16.0 : (big ? 24.0 : 10.0);
    final nameSz = narrow ? 24.0 : (big ? 28.0 : 13.0);
    final numSz = narrow ? 56.0 : (big ? 84.0 : 22.0);
    final barH = narrow ? 14.0 : (big ? 16.0 : 6.0);
    final statSz = narrow ? 18.0 : (big ? 22.0 : 11.0);
    final g1 = narrow ? 4.0 : (big ? 12.0 : 2.0);
    final g2 = narrow ? 6.0 : (big ? 16.0 : 6.0);
    final g3 = narrow ? 6.0 : (big ? 12.0 : 4.0);
    final marg = narrow
        ? const EdgeInsets.symmetric(vertical: 6)
        : EdgeInsets.symmetric(horizontal: big ? 8 : 4);
    return Container(
      margin: marg,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: _fit(
          big,
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(n,
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: nameSz)),
              SizedBox(height: g1),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$s / $t',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: numSz,
                        color: color)),
              ),
              SizedBox(height: g2),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: pct,
                    minHeight: barH,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15)),
              ),
              SizedBox(height: g3),
              Text(
                  habis
                      ? 'Stok habis'
                      : (done ? 'Target tercapai' : 'Sisa $left'),
                  style: TextStyle(
                      fontSize: statSz,
                      fontWeight: FontWeight.w600,
                      color: habis
                          ? Color(0xFF97291F)
                          : (done ? Colors.green : cs.outline))),
            ],
          )),
    );
  }

  /// Kotak Jumat Promo: stok promo outlet (ditambah karyawan) + terpakai hari ini.
  Widget _promoSeg(ColorScheme cs, bool big, {bool narrow = false}) {
    final color = promoStock <= 0 ? Color(0xFF97291F) : Colors.deepOrange;
    // Layar sempit (HP) pada tampilan besar: kartu ditumpuk ke bawah, ukuran diperkecil.
    final pad = narrow ? 16.0 : (big ? 24.0 : 10.0);
    final nameSz = narrow ? 24.0 : (big ? 28.0 : 13.0);
    final numSz = narrow ? 56.0 : (big ? 84.0 : 22.0);
    final statSz = narrow ? 18.0 : (big ? 22.0 : 11.0);
    final g1 = narrow ? 4.0 : (big ? 12.0 : 2.0);
    final g2 = narrow ? 6.0 : (big ? 16.0 : 6.0);
    final g3 = narrow ? 6.0 : (big ? 12.0 : 4.0);
    final marg = narrow
        ? const EdgeInsets.symmetric(vertical: 6)
        : EdgeInsets.symmetric(horizontal: big ? 8 : 4);
    return Container(
      margin: marg,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: _fit(
          big,
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Jumat Promo',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: nameSz)),
              ),
              SizedBox(height: g1),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$promoStock',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: numSz,
                        color: color)),
              ),
              SizedBox(height: g2),
              Icon(Icons.card_giftcard,
                  size: narrow ? 14 : (big ? 16 : 6), color: color),
              SizedBox(height: g3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                    promoStock <= 0
                        ? 'Stok habis • terpakai $promoUsed'
                        : 'Stok • terpakai $promoUsed',
                    style: TextStyle(
                        fontSize: statSz,
                        fontWeight: FontWeight.w600,
                        color:
                            promoStock <= 0 ? Color(0xFF97291F) : cs.outline)),
              ),
            ],
          )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final big = widget.big;
    final narrow = big && MediaQuery.of(context).size.width < 600;
    final cards = [
      for (final n in Target.names) _seg(n, cs, big, narrow: narrow),
      // Jumat Promo: pegawai hanya melihatnya di hari Jumat (admin selalu)
      if (Session.isAdmin || DateTime.now().weekday == DateTime.friday)
        _promoSeg(cs, big, narrow: narrow),
    ];
    final segs = [for (final c in cards) Expanded(child: c)];
    final title = widget.outlet.isEmpty
        ? 'Target Kemasan Hari Ini'
        : 'Target Hari Ini • ${widget.outlet}';
    final header = Row(children: [
      Icon(Icons.flag_outlined, size: big ? 28 : 18, color: cs.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: big ? 24 : 14)),
      ),
      Text(DateFormat('dd MMM yyyy').format(DateTime.now()),
          style: TextStyle(fontSize: big ? 16 : 11, color: cs.outline)),
      if (widget.onStock != null)
        IconButton(
            tooltip: 'Atur stok kemasan',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: widget.onStock),
      if (widget.onEdit != null)
        IconButton(
            tooltip: 'Ubah target',
            icon: const Icon(Icons.edit_outlined),
            onPressed: widget.onEdit)
      else
        IconButton(
          tooltip: big ? 'Tutup' : 'Perbesar',
          icon: Icon(big ? Icons.close : Icons.fullscreen),
          onPressed: big
              ? () => Navigator.pop(context)
              : () => showDialog(
                    context: context,
                    builder: (_) => Dialog.fullscreen(
                      child: Scaffold(
                        body: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: TargetCard(
                                outlet: widget.outlet,
                                tick: widget.tick,
                                big: true),
                          ),
                        ),
                      ),
                    ),
                  ),
        ),
    ]);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(big ? 20 : 12),
      decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]),
      child: big
          ? Column(children: [
              header,
              const SizedBox(height: 20),
              Expanded(
                child: narrow
                    ? ListView(children: [
                        for (final c in cards) SizedBox(height: 176, child: c)
                      ])
                    : Row(children: segs),
              ),
            ])
          : Column(mainAxisSize: MainAxisSize.min, children: [
              header,
              const SizedBox(height: 4),
              Row(children: segs),
            ]),
    );
  }
}
