import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart'
    show TextEditingValue, TextInputFormatter, TextSelection;
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

typedef Rec = Map<String, Object?>;

/// Penulisan uang: "Rp. 15.000" (titik sebagai pemisah ribuan, tanpa desimal).
final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp. ', decimalDigits: 0);
String rp(num n) => _rp.format(n);
String num0(num n) => NumberFormat('#,###', 'id_ID').format(n);

/// Angka dari isian uang yang sudah berformat ("213.750" -> 213750).
int moneyOf(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// Topping & kantong kresek tidak punya kemasan: kolom kemasan kosong
/// (data lama berisi "Standar" juga dianggap kosong).
bool noKem(String? k) => k == null || k.trim().isEmpty || k.trim() == 'Standar';

/// " (Normal)" untuk dipasang di belakang nama produk; kosong kalau tanpa kemasan.
String kemTag(String? k) => noKem(k) ? '' : ' (${k!.trim()})';

/// "Normal • " untuk dipasang di depan harga; kosong kalau tanpa kemasan.
String kemPre(String? k) => noKem(k) ? '' : '${k!.trim()} • ';

/// Teks isian uang berformat ribuan; 0 -> kosong.
String moneyText(num n) => n == 0 ? '' : num0(n);

/// Isian uang: tampil dengan pemisah ribuan saat diketik (213.750).
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return const TextEditingValue();
    if (d.length > 12) d = d.substring(0, 12);
    final t = num0(int.parse(d));
    return TextEditingValue(
        text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

String fmtDt(String iso) =>
    DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(iso));

/// Jumat Promo: kemasan gratis. Muncul di keranjang sebagai item berharga 0
/// dan mengurangi stok "Jumat Promo" outlet (diatur di menu Stok Kemasan).
const String kPromoProduct = 'Kemasan Jumat Promo';
const String kPromoKem = 'Gratis';
const String kPromoStockKey = 'Jumat Promo';

/// Jajan pengganti kembalian: tiap satu bernilai Rp 500.
const int kJajanPrice = 500;
int jajanOf(Map t) => ((t['jajan_qty'] ?? 0) as num).toInt();

/// Uang transaksi = total belanja + nilai jajan (jajan menggantikan kembalian,
/// jadi uangnya tetap masuk laci).
int trxMoney(Map t) =>
    ((t['total'] ?? 0) as num).toInt() + jajanOf(t) * kJajanPrice;
String hashPw(String s) => sha256.convert(utf8.encode(s)).toString();

/// Nama peran untuk ditampilkan. Admin bisa diberi nama bebas (SPV, Mitra, dst.)
String roleOf(Rec? u) {
  final r = u?['role'];
  if (r == 'develop') return 'Develop';
  if (r == 'admin') {
    final l = ((u?['role_label'] ?? '') as String).trim();
    return l.isEmpty ? 'Admin' : l;
  }
  return 'Karyawan';
}

/// Cek langganan satu outlet (baris tabel outlets). Mengembalikan null kalau
/// outlet boleh dipakai (tidak wajib berlangganan atau masih aktif), atau
/// pesan alasan terkunci kalau langganannya belum diatur / sudah berakhir.
String? outletSubLock(Map o) {
  if (((o['sub_required'] ?? 0) as num) != 1) return null;
  final until = (o['sub_until'] ?? '') as String;
  if (until.isEmpty) {
    return 'Langganan outlet belum diaktifkan.';
  }
  final today = DateTime.now().toIso8601String().substring(0, 10);
  if (until.compareTo(today) < 0) {
    return 'Langganan outlet berakhir pada ${DateFormat('dd/MM/yyyy').format(DateTime.parse(until))}.';
  }
  return null;
}

/// Sisa hari langganan outlet kalau wajib berlangganan, masih aktif, dan
/// sisanya tinggal 1 bulan atau kurang. Selain itu null (tidak berlangganan,
/// belum diatur, sudah berakhir, atau masih lama).
int? outletSubWarnDays(Map o) {
  if (((o['sub_required'] ?? 0) as num) != 1) return null;
  final until = (o['sub_until'] ?? '') as String;
  if (until.isEmpty) return null;
  final end = DateTime.tryParse(until);
  if (end == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final endDay = DateTime(end.year, end.month, end.day);
  if (endDay.isBefore(today)) return null; // sudah berakhir -> outlet terkunci
  // batas 1 bulan dari hari ini (tanpa meloncat: 31 Jan + 1 bulan = 28/29 Feb)
  final last = DateTime(today.year, today.month + 2, 0).day;
  final limit = DateTime(
      today.year, today.month + 1, today.day < last ? today.day : last);
  if (endDay.isAfter(limit)) return null;
  return endDay.difference(today).inDays;
}

/// Tambah bulan tanpa meloncat (31 Jan + 1 bulan = 28/29 Feb).
DateTime monthsAfter(DateTime d, int m) {
  final last = DateTime(d.year, d.month + m + 1, 0).day;
  return DateTime(d.year, d.month + m, d.day < last ? d.day : last);
}

class Session {
  static Rec? user;

  /// Dinaikkan tiap data akun disegarkan (Shell, tiap 30 detik) supaya
  /// pemberitahuan langganan outlet di Dashboard ikut diperbarui.
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// Pesan untuk layar login (mis. akun terkunci), tampil sekali.
  static String? notice;
  static String get role => (user?['role'] ?? '') as String;

  /// Develop: pemilik sistem. Satu-satunya yang boleh mengatur akun & outlet.
  static bool get isDevelop => role == 'develop';

  /// Panel lengkap: develop dan semua akun admin (Admin / Mitra / SPV, dst.).
  static bool get isAdmin => role == 'admin' || role == 'develop';

  /// Mitra: akun admin yang membawahi outlet. Hanya melihat outlet miliknya
  /// sendiri. Langganan diatur per outlet (bukan per akun mitra).
  static bool get isMitra =>
      role == 'admin' && ((user?['is_mitra'] ?? 0) as num) == 1;
  static String get roleLabel => roleOf(user);
  static int get id => user!['id'] as int;
  static String get name => user!['name'] as String;
  static String get outlet => (user!['outlet'] ?? '') as String;
}

class CartItem {
  final int variantId, price;
  final String product, kemasan;
  int qty;
  String note; // catatan pesanan (kosong = tidak ada catatan)
  CartItem(this.variantId, this.product, this.kemasan, this.price, this.qty,
      {this.note = ''});
  int get sub => price * qty;
}

class Db {
  static Database? _db;
  static Future<Database> get db async => _db ??= await _open();

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'outlet.db');
    final d = await openDatabase(path, version: 2, onUpgrade: _upgrade,
        onOpen: (d) async {
      // closing & pengeluaran: dijamin ada setiap kali database dibuka
      await d.execute(
          'CREATE TABLE IF NOT EXISTS closing(outlet TEXT, day TEXT, modal INTEGER DEFAULT 0, modal_note TEXT, qris_override INTEGER, transfer INTEGER DEFAULT 0, cash_counted INTEGER, note TEXT, updated_by TEXT, updated_at TEXT, PRIMARY KEY(outlet, day))');
      await d.execute(
          'CREATE TABLE IF NOT EXISTS expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, outlet TEXT, day TEXT, amount INTEGER, note TEXT, user_name TEXT, created_at TEXT)');
      await d.execute(
          'CREATE TABLE IF NOT EXISTS sync_log(id INTEGER PRIMARY KEY AUTOINCREMENT, outlet TEXT, day TEXT, created_at TEXT, user_name TEXT, total INTEGER DEFAULT 0, qris INTEGER DEFAULT 0, transfer INTEGER DEFAULT 0, expected INTEGER DEFAULT 0, counted INTEGER DEFAULT 0, diff INTEGER DEFAULT 0, note TEXT, modal INTEGER DEFAULT 0, spent INTEGER DEFAULT 0, jajan INTEGER DEFAULT 0)');
    }, onCreate: (d, v) async {
      await d.execute(
          'CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, username TEXT UNIQUE, password TEXT, role TEXT, outlet TEXT)');
      await d.execute(
          'CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, category TEXT, active INTEGER DEFAULT 1)');
      await d.execute(
          'CREATE TABLE variants(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, kemasan TEXT, price INTEGER, stock INTEGER DEFAULT 0)');
      await d.execute(
          'CREATE TABLE transactions(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT, created_at TEXT, user_id INTEGER, user_name TEXT, outlet TEXT, subtotal INTEGER, discount_pct REAL, discount_amt INTEGER, total INTEGER, cash INTEGER, change_amt INTEGER)');
      await d.execute(
          'CREATE TABLE transaction_items(id INTEGER PRIMARY KEY AUTOINCREMENT, trx_id INTEGER, product_name TEXT, kemasan TEXT, price INTEGER, qty INTEGER, subtotal INTEGER)');
      await d.execute(
          'CREATE TABLE attendance(id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, check_in TEXT, check_out TEXT)');
      await d
          .execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
      // Akun awal (segera ganti password!)
      await d.insert('users', {
        'name': 'Develop',
        'username': 'admin',
        'password': hashPw('admin123'),
        'role': 'develop',
        'outlet': 'Pusat'
      });
      await d.insert('users', {
        'name': 'Karyawan 1',
        'username': 'karyawan',
        'password': hashPw('karyawan123'),
        'role': 'karyawan',
        'outlet': 'Outlet 1'
      });
      // Produk awal (harga hanya contoh, edit di Katalog Produk)
      const utama = [
        'Makaroni Pipa',
        'Makaroni Sepiral',
        'Basreng Stick',
        'Sebring',
        'Kripik Kaca',
        'Mie Crispy',
        'Usus Crispy',
        'Mie Lidi',
        'Kulit Ayam'
      ];
      for (final n in utama) {
        final pid = await d
            .insert('products', {'name': n, 'category': 'utama', 'active': 1});
        for (final v in [
          ['Kecil', 10000],
          ['Normal', 15000],
          ['Besar', 25000]
        ]) {
          await d.insert('variants', {
            'product_id': pid,
            'kemasan': v[0],
            'price': v[1],
            'stock': 100
          });
        }
      }
      final t = await d.insert('products',
          {'name': 'Topping Balado', 'category': 'topping', 'active': 1});
      await d.insert('variants',
          {'product_id': t, 'kemasan': '', 'price': 2000, 'stock': 500});
      final k = await d.insert('products',
          {'name': 'Kantong Kresek', 'category': 'topping', 'active': 1});
      await d.insert('variants',
          {'product_id': k, 'kemasan': '', 'price': 500, 'stock': 500});
      await d.insert(
          'settings', {'key': 'outlet_name', 'value': 'Outlet Makaroni'});
      await d.insert('settings',
          {'key': 'footer', 'value': 'Terima kasih sudah berbelanja'});
      await d.insert('settings', {'key': 'paper', 'value': '58'});
      await _seedCats(d);
    });
    await _ensureCols(d);
    return d;
  }

  /// Tambah kolom baru kalau belum ada. Aman dipanggil berulang.
  static Future<void> _ensureCols(Database d) async {
    // topping & kresek tidak punya kemasan: hapus tulisan "Standar" lama
    await d.update('variants', {'kemasan': ''}, where: "kemasan='Standar'");
    final pc = await d.rawQuery('PRAGMA table_info(products)');
    if (!pc.any((c) => c['name'] == 'image_path')) {
      await d.execute('ALTER TABLE products ADD COLUMN image_path TEXT');
    }
    // peran: nama peran bebas untuk akun admin (SPV, Mitra, dst.)
    final uc = await d.rawQuery('PRAGMA table_info(users)');
    if (!uc.any((c) => c['name'] == 'role_label')) {
      await d.execute('ALTER TABLE users ADD COLUMN role_label TEXT');
    }
    // akses outlet akun admin/spv: 'all' (semua outlet) atau 'custom' (pilihan)
    if (!uc.any((c) => c['name'] == 'outlet_scope')) {
      await d.execute(
          "ALTER TABLE users ADD COLUMN outlet_scope TEXT DEFAULT 'all'");
    }
    // (lama) langganan per akun: tidak dipakai lagi, hanya untuk migrasi ke outlet
    if (!uc.any((c) => c['name'] == 'sub_required')) {
      await d.execute(
          'ALTER TABLE users ADD COLUMN sub_required INTEGER DEFAULT 0');
    }
    if (!uc.any((c) => c['name'] == 'sub_until')) {
      await d.execute('ALTER TABLE users ADD COLUMN sub_until TEXT');
    }
    // penanda akun mitra. Dulu mitra = akun dengan sub_required=1; akun lama
    // itu dijadikan mitra (sekali saja, saat kolom baru dibuat).
    if (!uc.any((c) => c['name'] == 'is_mitra')) {
      await d
          .execute('ALTER TABLE users ADD COLUMN is_mitra INTEGER DEFAULT 0');
      await d.execute(
          "UPDATE users SET is_mitra=1 WHERE role='admin' AND sub_required=1");
    }
    // password yang bisa dilihat Develop di Akun & Pegawai (hash tetap dipakai login)
    if (!uc.any((c) => c['name'] == 'pw_plain')) {
      await d.execute('ALTER TABLE users ADD COLUMN pw_plain TEXT');
    }
    for (final p in ['admin123', 'karyawan123']) {
      await d.update('users', {'pw_plain': p},
          where: 'pw_plain IS NULL AND password=?', whereArgs: [hashPw(p)]);
    }
    // Panel admin lama menjadi panel Develop: kalau belum ada akun develop,
    // semua akun admin yang ada dijadikan develop (sekali saja).
    final dv =
        await d.rawQuery("SELECT COUNT(*) c FROM users WHERE role='develop'");
    if (((dv.first['c'] as num?) ?? 0) == 0) {
      await d.execute("UPDATE users SET role='develop' WHERE role='admin'");
    }
    // foto absensi (diambil dari kamera): path file untuk masuk & keluar
    final ac = await d.rawQuery('PRAGMA table_info(attendance)');
    if (!ac.any((c) => c['name'] == 'photo_in')) {
      await d.execute('ALTER TABLE attendance ADD COLUMN photo_in TEXT');
    }
    if (!ac.any((c) => c['name'] == 'photo_out')) {
      await d.execute('ALTER TABLE attendance ADD COLUMN photo_out TEXT');
    }
    // foto profil akun (path file) dan jajan pengganti kembalian per transaksi
    if (!uc.any((c) => c['name'] == 'photo_path')) {
      await d.execute('ALTER TABLE users ADD COLUMN photo_path TEXT');
    }
    // catatan per item pesanan (tampil di struk hanya kalau diisi)
    final tc = await d.rawQuery('PRAGMA table_info(transaction_items)');
    if (!tc.any((c) => c['name'] == 'note')) {
      await d.execute('ALTER TABLE transaction_items ADD COLUMN note TEXT');
    }
    final jc = await d.rawQuery('PRAGMA table_info(transactions)');
    if (!jc.any((c) => c['name'] == 'jajan_qty')) {
      await d.execute(
          'ALTER TABLE transactions ADD COLUMN jajan_qty INTEGER DEFAULT 0');
    }
    // Modal & closing harian (per outlet per tanggal) + pengeluaran
    await d.execute(
        'CREATE TABLE IF NOT EXISTS closing(outlet TEXT, day TEXT, modal INTEGER DEFAULT 0, modal_note TEXT, qris_override INTEGER, transfer INTEGER DEFAULT 0, cash_counted INTEGER, note TEXT, updated_by TEXT, updated_at TEXT, PRIMARY KEY(outlet, day))');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, outlet TEXT, day TEXT, amount INTEGER, note TEXT, user_name TEXT, created_at TEXT)');
    // metode bayar: 'Tunai' atau 'QRIS' (transaksi lama = kosong = tunai)
    final txCols = await d.rawQuery('PRAGMA table_info(transactions)');
    if (!txCols.any((c) => c['name'] == 'payment')) {
      await d.execute(
          "ALTER TABLE transactions ADD COLUMN payment TEXT DEFAULT 'Tunai'");
    }
    // Riwayat sinkronisasi: catatan permanen (tidak bisa diubah), satu baris
    // per sinkronisasi lengkap dengan jam.
    await d.execute(
        'CREATE TABLE IF NOT EXISTS sync_log(id INTEGER PRIMARY KEY AUTOINCREMENT, outlet TEXT, day TEXT, created_at TEXT, user_name TEXT, total INTEGER DEFAULT 0, qris INTEGER DEFAULT 0, transfer INTEGER DEFAULT 0, expected INTEGER DEFAULT 0, counted INTEGER DEFAULT 0, diff INTEGER DEFAULT 0, note TEXT, modal INTEGER DEFAULT 0, spent INTEGER DEFAULT 0, jajan INTEGER DEFAULT 0)');
    // rincian pengeluaran (jumlah + keterangan) saat sinkronisasi disimpan
    final sl = await d.rawQuery('PRAGMA table_info(sync_log)');
    if (!sl.any((c) => c['name'] == 'spent_detail')) {
      await d.execute('ALTER TABLE sync_log ADD COLUMN spent_detail TEXT');
    }
    // closing lama yang sudah dihitung dipindahkan ke riwayat (sekali saja)
    await d.execute(
        "INSERT INTO sync_log(outlet,day,created_at,user_name,total,qris,transfer,expected,counted,diff,note,modal,spent,jajan) "
        "SELECT outlet,day,COALESCE(updated_at, day||'T00:00:00'),COALESCE(updated_by,''),tot,q,tr,tot-q-tr,cash_counted,cash_counted-(tot-q-tr),note,modal,spent,jaj FROM ("
        "SELECT c.outlet outlet, c.day day, c.updated_at updated_at, c.updated_by updated_by, c.cash_counted cash_counted, c.note note, COALESCE(c.modal,0) modal, COALESCE(c.transfer,0) tr, "
        "(SELECT COALESCE(SUM(total),0) FROM transactions t WHERE t.outlet=c.outlet AND substr(t.created_at,1,10)=c.day) tot, "
        "COALESCE(c.qris_override,(SELECT COALESCE(SUM(total),0) FROM transactions t WHERE t.outlet=c.outlet AND substr(t.created_at,1,10)=c.day AND t.payment='QRIS')) q, "
        "(SELECT COALESCE(SUM(amount),0) FROM expenses e WHERE e.outlet=c.outlet AND e.day=c.day) spent, "
        "(SELECT COALESCE(SUM(jajan_qty),0) FROM transactions t WHERE t.outlet=c.outlet AND substr(t.created_at,1,10)=c.day) jaj "
        "FROM closing c WHERE c.cash_counted IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sync_log s WHERE s.outlet=c.outlet AND s.day=c.day))");
  }

  /// Tabel outlet + stok kemasan per outlet. Aman dipanggil berulang.
  static Future<void> _v3(Database d) async {
    final has = await d.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='outlets'");
    if (has.isEmpty) {
      await d.execute(
          'CREATE TABLE outlets(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
      // outlet yang sudah dipakai pegawai/transaksi dimasukkan otomatis
      await d.execute(
          "INSERT OR IGNORE INTO outlets(name) SELECT DISTINCT outlet FROM users WHERE outlet IS NOT NULL AND outlet<>''");
      await d.execute(
          "INSERT OR IGNORE INTO outlets(name) SELECT DISTINCT outlet FROM transactions WHERE outlet IS NOT NULL AND outlet<>''");
    }
    await d.execute(
        'CREATE TABLE IF NOT EXISTS kemasan_stock(outlet TEXT, kemasan TEXT, qty INTEGER DEFAULT 0, PRIMARY KEY(outlet, kemasan))');
    // akses outlet akun admin/spv yang dibatasi ke outlet tertentu
    await d.execute(
        'CREATE TABLE IF NOT EXISTS account_outlets(user_id INTEGER, outlet TEXT, PRIMARY KEY(user_id, outlet))');
    // pemilik outlet: id akun mitra (kosong = outlet pusat)
    final oc = await d.rawQuery('PRAGMA table_info(outlets)');
    if (!oc.any((c) => c['name'] == 'owner_id')) {
      await d.execute('ALTER TABLE outlets ADD COLUMN owner_id INTEGER');
    }
    // langganan per outlet: wajib langganan + tanggal berakhir (yyyy-MM-dd)
    if (!oc.any((c) => c['name'] == 'sub_required')) {
      await d.execute(
          'ALTER TABLE outlets ADD COLUMN sub_required INTEGER DEFAULT 0');
      await d.execute('ALTER TABLE outlets ADD COLUMN sub_until TEXT');
      // langganan lama milik akun mitra dipindahkan ke outlet-outlet miliknya
      // (sekali saja, saat kolom baru dibuat)
      await d.execute(
          'UPDATE outlets SET sub_required=1, sub_until=(SELECT m.sub_until FROM users m WHERE m.id=outlets.owner_id) '
          'WHERE owner_id IN (SELECT id FROM users WHERE role=\'admin\' AND sub_required=1)');
    }
    // Kelompok outlet: "Outlet Pusat" atau kelompok "Mitra". Satu kelompok bisa
    // berisi banyak toko; kelompok mitra boleh dihubungkan ke satu akun mitra.
    await d.execute(
        'CREATE TABLE IF NOT EXISTS outlet_groups(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, kind TEXT, owner_id INTEGER)');
    final oc2 = await d.rawQuery('PRAGMA table_info(outlets)');
    if (!oc2.any((c) => c['name'] == 'group_id')) {
      await d.execute('ALTER TABLE outlets ADD COLUMN group_id INTEGER');
      // Migrasi sekali: tiap akun mitra yang sudah punya outlet menjadi satu
      // kelompok Mitra; outlet tanpa pemilik masuk kelompok "Outlet Pusat".
      final owners = await d.rawQuery(
          'SELECT DISTINCT owner_id FROM outlets WHERE owner_id IS NOT NULL');
      for (final o in owners) {
        final uid = o['owner_id'];
        final un = await d.rawQuery('SELECT name FROM users WHERE id=?', [uid]);
        var nm = un.isEmpty ? 'Mitra $uid' : 'Mitra ${un.first['name']}';
        final ex = await d
            .rawQuery('SELECT owner_id FROM outlet_groups WHERE name=?', [nm]);
        if (ex.isNotEmpty && ex.first['owner_id'] != uid) nm = '$nm ($uid)';
        final gid = await _ensureGroup(d, nm, 'mitra', uid as int?);
        await d.update('outlets', {'group_id': gid},
            where: 'owner_id=?', whereArgs: [uid]);
      }
      final pg = await _ensureGroup(d, 'Outlet Pusat', 'pusat', null);
      await d.update('outlets', {'group_id': pg},
          where: 'owner_id IS NULL AND group_id IS NULL');
    }
  }

  /// Cari kelompok menurut nama; buat kalau belum ada. Mengembalikan id-nya.
  static Future<int> _ensureGroup(
      DatabaseExecutor d, String name, String kind, int? owner) async {
    final r =
        await d.rawQuery('SELECT id FROM outlet_groups WHERE name=?', [name]);
    if (r.isNotEmpty) return r.first['id'] as int;
    return d.insert(
        'outlet_groups', {'name': name, 'kind': kind, 'owner_id': owner});
  }

  /// Pindahkan satu outlet ke kelompok ([groupId] null = tanpa kelompok).
  /// Akun pemilik outlet ikut akun kelompok barunya, jadi hak lihat mitra
  /// otomatis mengikuti. Outlet yang baru masuk kelompok mitra dan belum pernah
  /// diatur langganannya langsung berlangganan untuk 1 bulan pertama.
  static Future<void> moveOutlet(
      DatabaseExecutor t, String outlet, int? groupId) async {
    int? owner;
    String? kind;
    if (groupId != null) {
      final g = await t.rawQuery(
          'SELECT kind, owner_id FROM outlet_groups WHERE id=?', [groupId]);
      if (g.isEmpty) {
        groupId = null;
      } else {
        kind = g.first['kind'] as String?;
        owner = g.first['owner_id'] as int?;
      }
    }
    final cur =
        await t.rawQuery('SELECT group_id FROM outlets WHERE name=?', [outlet]);
    final was = cur.isEmpty ? null : cur.first['group_id'];
    await t.update('outlets', {'group_id': groupId, 'owner_id': owner},
        where: 'name=?', whereArgs: [outlet]);
    if (kind == 'mitra' && was != groupId) {
      await t.update(
          'outlets',
          {
            'sub_required': 1,
            'sub_until': monthsAfter(DateTime.now(), 1)
                .toIso8601String()
                .substring(0, 10),
          },
          where:
              "name=? AND COALESCE(sub_required,0)<>1 AND (sub_until IS NULL OR sub_until='')",
          whereArgs: [outlet]);
    }
  }

  /// Hubungkan kelompok mitra ke satu akun mitra (null = belum ada akun).
  /// Semua toko di kelompok itu ikut pemiliknya.
  static Future<void> setGroupOwner(
      DatabaseExecutor t, int groupId, int? owner) async {
    await t.update('outlet_groups', {'owner_id': owner},
        where: 'id=?', whereArgs: [groupId]);
    await t.update('outlets', {'owner_id': owner},
        where: 'group_id=?', whereArgs: [groupId]);
  }

  /// Pastikan semua kolom baru ada (aman diulang), supaya tetap benar walau
  /// aplikasi hanya di-hot reload dan database sudah terbuka sebelumnya.
  static Future<void> ensureCols() async => _ensureCols(await db);

  static Future<void> ensureV3() async {
    final d = await db;
    await _ensureCols(d);
    await _v3(d);
  }

  /// Alasan akun terkunci (null = boleh masuk). Langganan diatur per outlet:
  /// - pegawai terkunci kalau langganan outletnya habis,
  /// - mitra terkunci kalau semua outlet miliknya langganannya habis
  ///   (selama masih ada outlet yang aktif, mitra tetap bisa masuk dan
  ///   outlet yang habis tidak ikut tampil).
  static Future<String?> lockReason(Rec? u) async {
    if (u == null) return null;
    if (u['role'] == 'karyawan') {
      final o = (u['outlet'] ?? '') as String;
      if (o.isEmpty) return null;
      await ensureV3();
      final r = await q(
          'SELECT sub_required, sub_until FROM outlets WHERE name=?', [o]);
      if (r.isNotEmpty) {
        final why = outletSubLock(r.first);
        if (why != null) {
          return 'Akses outlet terkunci. $why Hubungi mitra atau Develop untuk memperpanjang.';
        }
      }
    } else if (u['role'] == 'admin' && ((u['is_mitra'] ?? 0) as num) == 1) {
      await ensureV3();
      final r = await q(
          'SELECT sub_required, sub_until FROM outlets WHERE owner_id=?',
          [u['id']]);
      if (r.isNotEmpty && r.every((o) => outletSubLock(o) != null)) {
        return 'Langganan semua outlet Anda sudah berakhir. Hubungi Develop untuk memperpanjang.';
      }
    }
    return null;
  }

  static Future<void> _seedCats(Database d) async {
    await d.execute(
        'CREATE TABLE IF NOT EXISTS categories(id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT UNIQUE, name TEXT, sort INTEGER DEFAULT 0)');
    await d.insert('categories', {'key': 'utama', 'name': 'Menu', 'sort': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await d.insert('categories',
        {'key': 'topping', 'name': 'Topping dan Plastik', 'sort': 2},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _upgrade(Database d, int oldV, int newV) async {
    if (oldV < 2) {
      await _seedCats(d);
      // kategori lama "kresek" digabung ke "Topping dan Plastik"
      await d.update('products', {'category': 'topping'},
          where: "category='kresek'");
    }
  }

  static Future<List<Rec>> categories() async {
    final d = await db;
    await _seedCats(d); // aman dipanggil berulang (buat tabel kalau belum ada)
    await d.update('products', {'category': 'topping'},
        where: "category='kresek'");
    return d.query('categories', orderBy: 'sort, id');
  }

  static Future<List<Rec>> q(String sql, [List<Object?>? args]) async =>
      (await db).rawQuery(sql, args);

  static Future<Rec?> login(String u, String p) async {
    // pastikan akun admin lama sudah menjadi develop (aman diulang), supaya
    // tetap benar walau aplikasi hanya di-hot reload dan belum dibuka ulang
    await _ensureCols(await db);
    final r = await (await db).query('users',
        where: 'username=? AND password=?', whereArgs: [u, hashPw(p)]);
    if (r.isNotEmpty && r.first['pw_plain'] == null) {
      // akun lama: simpan password saat berhasil login agar bisa dilihat Develop
      await (await db).update('users', {'pw_plain': p},
          where: 'id=?', whereArgs: [r.first['id']]);
    }
    return r.isEmpty ? null : r.first;
  }

  static Future<String?> getSetting(String k) async {
    final r =
        await (await db).query('settings', where: 'key=?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  static Future<void> setSetting(String k, String v) async =>
      (await db).insert('settings', {'key': k, 'value': v},
          conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<Rec> saveTrx(List<CartItem> items, double pct, int cash,
      {String method = 'Tunai', int jajan = 0}) async {
    final d = await db;
    await _ensureCols(d);
    await _v3(d);
    final sub = items.fold<int>(0, (a, e) => a + e.sub);
    final disc = (sub * pct / 100).round();
    final total = sub - disc;
    final now = DateTime.now();
    final String outletName = Session.outlet;
    late int id;
    await d.transaction((t) async {
      id = await t.insert('transactions', {
        'code': 'INV${DateFormat('yyMMddHHmmss').format(now)}',
        'created_at': now.toIso8601String(),
        'user_id': Session.id,
        'user_name': Session.name,
        'outlet': Session.outlet,
        'subtotal': sub,
        'discount_pct': pct,
        'discount_amt': disc,
        'total': total,
        'cash': cash,
        'change_amt': cash - total,
        'payment': method,
        'jajan_qty': jajan,
      });
      for (final i in items) {
        await t.insert('transaction_items', {
          'trx_id': id,
          'product_name': i.product,
          'kemasan': i.kemasan,
          'price': i.price,
          'qty': i.qty,
          'subtotal': i.sub,
          'note': i.note.trim().isEmpty ? null : i.note.trim(),
        });
        // Jumat Promo (gratis): stok kemasan promo outlet berkurang
        if (i.product == kPromoProduct) {
          await t.execute(
              'INSERT OR IGNORE INTO kemasan_stock(outlet, kemasan, qty) VALUES(?,?,0)',
              [outletName, kPromoStockKey]);
          await t.execute(
              'UPDATE kemasan_stock SET qty = MAX(qty - ?, 0) WHERE outlet=? AND kemasan=?',
              [i.qty, outletName, kPromoStockKey]);
        }
        // stok kemasan outlet (Kecil/Normal/Besar) berkurang otomatis
        if (const ['Kecil', 'Normal', 'Besar'].contains(i.kemasan)) {
          await t.execute(
              'INSERT OR IGNORE INTO kemasan_stock(outlet, kemasan, qty) VALUES(?,?,0)',
              [outletName, i.kemasan]);
          await t.execute(
              'UPDATE kemasan_stock SET qty = MAX(qty - ?, 0) WHERE outlet=? AND kemasan=?',
              [i.qty, outletName, i.kemasan]);
        }
      }
    });
    return trx(id);
  }

  static Future<Rec> trx(int id) async {
    final d = await db;
    final h =
        (await d.query('transactions', where: 'id=?', whereArgs: [id])).first;
    final its =
        await d.query('transaction_items', where: 'trx_id=?', whereArgs: [id]);
    return {...h, 'items': its};
  }
}
