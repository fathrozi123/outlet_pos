import 'package:flutter/material.dart';
import 'db.dart';
import 'product_image.dart';
import 'printer.dart';
import 'prefs.dart';
import 'target.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class PosPage extends StatefulWidget {
  const PosPage({super.key});
  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  String cat = 'utama', q = '';
  List<Rec> cats = [];
  final _search = TextEditingController();
  final _tick = ValueNotifier<int>(0); // memicu kartu target memuat ulang
  static const _pal = [
    Color(0xFF7E57C2),
    Color(0xFFD7898B),
    Color(0xFFE9D95C),
    Color(0xFF7BC8A4),
    Color(0xFF4F83E0),
    Color(0xFFE6A8C0),
    Color(0xFF263238),
    Color(0xFFEF9A5B),
  ];
  final cart = <CartItem>[];
  late Future<List<Rec>> fut;
  Future<List<Rec>>? _topFut; // daftar topping & kresek (per varian)
  StateSetter? _sheetSet; // agar keranjang di bottom sheet ikut ter-update
  int _promoStock = 0; // stok kemasan Jumat Promo outlet ini

  // ---------- Jumat Promo: tiap 2 kemasan Normal/Besar = 1 kemasan gratis ----------
  static const _promoNeeds = {'Normal', 'Besar'};
  static const _promoEvery = 2;
  bool _isPromo(CartItem e) => e.product == kPromoProduct;
  int get _qualifying => cart
      .where((e) => _promoNeeds.contains(e.kemasan))
      .fold<int>(0, (a, e) => a + e.qty);
  int get _promoInCart =>
      cart.where(_isPromo).fold<int>(0, (a, e) => a + e.qty);
  int get _promoEligible => _qualifying ~/ _promoEvery;

  /// Jumat Promo hanya berlaku di hari Jumat.
  bool get _isFriday => DateTime.now().weekday == DateTime.friday;
  int get _promoMax => !_isFriday
      ? 0
      : (_promoEligible < _promoStock ? _promoEligible : _promoStock);

  /// Segarkan keranjang di bottom sheet, aman walau sheet sudah tertutup.
  void _pokeSheet() {
    try {
      _sheetSet?.call(() {});
    } catch (_) {
      _sheetSet = null;
    }
  }

  Future<void> _loadPromo() async {
    final p = await Target.promoStock(Target.myOutlet());
    if (!mounted || p == _promoStock) return;
    setState(() {
      _promoStock = p;
      _fixPromo();
    });
    _pokeSheet();
  }

  /// Jumlah promo di keranjang tidak boleh melebihi yang berhak didapat.
  void _fixPromo() {
    final i = cart.indexWhere(_isPromo);
    if (i < 0) return;
    if (_promoMax <= 0) {
      cart.removeAt(i);
    } else if (cart[i].qty > _promoMax) {
      cart[i].qty = _promoMax;
    }
  }

  void _setPromo(int delta) {
    _mut(() {
      final i = cart.indexWhere(_isPromo);
      if (delta > 0) {
        if (_promoInCart >= _promoMax) return;
        if (i >= 0) {
          cart[i].qty++;
        } else {
          cart.add(CartItem(-1, kPromoProduct, kPromoKem, 0, 1));
        }
      } else if (i >= 0) {
        if (cart[i].qty > 1) {
          cart[i].qty--;
        } else {
          cart.removeAt(i);
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadCats();
    _loadPromo();
  }

  @override
  void dispose() {
    _search.dispose();
    _tick.dispose();
    super.dispose();
  }

  Future<void> _loadCats() async {
    final c = await Db.categories();
    if (!mounted) return;
    setState(() {
      cats = c;
      if (c.isNotEmpty && !c.any((k) => k['key'] == cat)) {
        cat = c.first['key'] as String;
        _load();
      }
    });
  }

  void _load() {
    const sel =
        'SELECT p.*, MIN(v.price) AS minp FROM products p LEFT JOIN variants v ON v.product_id=p.id ';
    final s = q.trim();
    _topFut = null; // dimuat ulang saat kategori/pencarian berubah
    fut = s.isEmpty
        ? Db.q(
            '${sel}WHERE p.active=1 AND p.category=? GROUP BY p.id ORDER BY p.id',
            [
                cat
              ])
        : Db.q(
            '${sel}WHERE p.active=1 AND (p.name LIKE ? OR p.id=?) GROUP BY p.id ORDER BY p.id',
            ['%$s%', int.tryParse(s) ?? -1]);
  }

  void _mut(VoidCallback f) {
    setState(() {
      f();
      _fixPromo();
    });
    _pokeSheet();
    _loadPromo(); // stok promo bisa berubah dari menu Stok Kemasan
  }

  // ---------- kuota kemasan (Kecil habis saat target terpenuhi) ----------
  int _inCart(String kem) =>
      cart.where((e) => e.kemasan == kem).fold<int>(0, (a, e) => a + e.qty);

  Future<int?> _left(String kem) => Target.left(Target.myOutlet(), kem);

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  int get _total => cart.fold<int>(0, (a, e) => a + e.sub);
  int get _count => cart.fold<int>(0, (a, e) => a + e.qty);

  // ---------- pilih kemasan & jumlah ----------
  Future<void> _pick(Rec p) async {
    final vs = await Db.q(
        'SELECT * FROM variants WHERE product_id=? ORDER BY price', [p['id']]);
    if (vs.isEmpty || !mounted) return;
    // sisa kuota tiap kemasan saat dialog dibuka (null = tanpa batas)
    final lim = <int?>[for (final v in vs) await _left(v['kemasan'] as String)];
    if (!mounted) return;
    int? availOf(int i) {
      final l = lim[i];
      if (l == null) return null;
      final r = l - _inCart(vs[i]['kemasan'] as String);
      return r < 0 ? 0 : r;
    }

    int sel = vs.indexWhere((v) => true);
    for (var i = 0; i < vs.length; i++) {
      if (availOf(i) != 0) {
        sel = i;
        break;
      }
    }
    int qty = 1;
    // Catatan disimpan di variabel biasa (bukan TextEditingController) supaya
    // tidak error "used after being disposed" saat dialog menutup.
    String note = '';
    final res = await showDialog<CartItem>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (c, set) {
        final cs = Theme.of(c).colorScheme;
        final v = vs[sel];
        final price = v['price'] as int;
        // topping / kresek: tanpa kemasan, cukup nama dan harga
        final plain = vs.every((x) => noKem(x['kemasan'] as String?));

        Widget opt(int i) {
          final on = sel == i;
          final habis = availOf(i) == 0;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: habis
                ? null
                : () => set(() {
                      sel = i;
                      qty = 1;
                    }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 104,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: on ? cs.primaryContainer : Colors.white,
                border: Border.all(
                    color: on ? cs.primary : cs.outlineVariant,
                    width: on ? 2 : 1),
                borderRadius: BorderRadius.circular(14),
                boxShadow: on
                    ? [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Column(children: [
                Text('${vs[i]['kemasan']}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: habis ? Colors.grey : null)),
                const SizedBox(height: 4),
                Text(rp(vs[i]['price'] as int),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: habis ? Colors.grey : (on ? cs.primary : null))),
                if (habis)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text('Stok habis',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.red,
                            fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          );
        }

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(p['name'] as String,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (plain)
                    Center(
                        child: Text(rp(price),
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: cs.primary)))
                  else ...[
                    const Text('Pilih kemasan',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 10),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [for (var i = 0; i < vs.length; i++) opt(i)]),
                  ],
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton.filledTonal(
                        style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onPressed: qty > 1 ? () => set(() => qty--) : null,
                        icon: const Icon(Icons.remove)),
                    SizedBox(
                        width: 64,
                        child: Text('$qty',
                            textAlign: TextAlign.center,
                            style: Theme.of(c)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800))),
                    IconButton.filledTonal(
                        style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onPressed: (availOf(sel) == null || qty < availOf(sel)!)
                            ? () => set(() => qty++)
                            : null,
                        icon: const Icon(Icons.add)),
                  ]),
                  const SizedBox(height: 8),
                  Center(
                      child: Text('Subtotal ${rp(price * qty)}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: cs.primary))),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: note,
                    onChanged: (val) => note = val,
                    maxLength: 80,
                    maxLines: 2,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Catatan (opsional)',
                      hintText: 'Contoh: level 3, tanpa daun jeruk',
                      prefixIcon: const Icon(Icons.edit_note_rounded),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ]),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            FilledButton.icon(
              onPressed: availOf(sel) == 0
                  ? null
                  : () => Navigator.pop(
                      c,
                      CartItem(v['id'] as int, p['name'] as String,
                          v['kemasan'] as String, price, qty,
                          note: note.trim())),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Tambah'),
            ),
          ],
        );
      }),
    );
    if (res == null) return;
    _mut(() {
      // item sama dengan catatan sama digabung; catatan beda = baris terpisah
      final ex = cart.indexWhere(
          (e) => e.variantId == res.variantId && e.note == res.note);
      if (ex >= 0) {
        cart[ex].qty += res.qty;
      } else {
        cart.add(res);
      }
    });
  }

  // ---------- konfirmasi -> bayar -> berhasil ----------
  Future<void> _confirm() async {
    if (cart.isEmpty) return;
    // pengaman terakhir: kemasan yang kuotanya habis tidak boleh terjual
    for (final k in Target.limited) {
      final l = await _left(k);
      if (l != null && _inCart(k) > l) {
        if (mounted) {
          _snack(l == 0
              ? 'Stok kemasan $k habis, hapus dari keranjang.'
              : 'Stok kemasan $k tinggal $l, kurangi jumlahnya.');
        }
        return;
      }
    }
    // pengaman Jumat Promo: stok promo harus cukup dan jumlahnya masih berhak
    if (_promoInCart > 0) {
      final ps = await Target.promoStock(Target.myOutlet());
      if (!_isFriday || _promoInCart > ps || _promoInCart > _promoEligible) {
        if (mounted) {
          _mut(() {});
          _snack(!_isFriday
              ? 'Jumat Promo hanya berlaku di hari Jumat, hapus dari keranjang.'
              : ps <= 0
                  ? 'Stok Jumat Promo habis, hapus dari keranjang.'
                  : 'Jumat Promo melebihi stok atau hak promo, kurangi jumlahnya.');
        }
        return;
      }
    }
    if (!mounted) return;
    final res = await showDialog<Rec>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PayDialog(items: List.of(cart)));
    if (res == null || !mounted) return;
    _mut(cart.clear);
    setState(_load);
    _tick.value++;
    _loadPromo();
    _success(res);
  }

  void _success(Rec res) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => Dialog.fullscreen(
          child: _SuccessView(
              t: res['trx'] as Rec, printed: res['printed'] == true)),
    );
  }

  /// Kartu target hanya tampil di kategori Menu dan Kemasan (juga saat
  /// mencari produk, karena hasilnya bisa berisi menu).
  bool get _showTarget {
    if (q.trim().isNotEmpty) return true;
    final k = cats.where((c) => c['key'] == cat).firstOrNull;
    final name = ((k?['name'] ?? '') as String).toLowerCase();
    return cat == 'utama' || name.contains('menu') || name.contains('kemasan');
  }

  void _setCat(String k) => setState(() {
        cat = k;
        q = '';
        _search.clear();
        _load();
      });

  Widget _chips() {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Wrap(spacing: 8, runSpacing: 6, children: [
        for (final k in cats)
          ChoiceChip(
            label: Text(k['name'] as String),
            selected: cat == k['key'] && q.isEmpty,
            selectedColor: cs.primaryContainer,
            labelStyle: TextStyle(
              fontWeight: FontWeight.w700,
              color: (cat == k['key'] && q.isEmpty) ? cs.primary : null,
            ),
            onSelected: (_) => _setCat(k['key'] as String),
          ),
      ]),
    );
  }

  Widget _tabs() {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final k = cats[i];
          final on = cat == k['key'] && q.isEmpty;
          return Material(
            color: on ? cs.primary : Colors.white,
            borderRadius: BorderRadius.circular(22),
            elevation: on ? 2 : 0,
            shadowColor: cs.primary.withValues(alpha: 0.35),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _setCat(k['key'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: on
                        ? cs.primary
                        : cs.outlineVariant.withValues(alpha: 0.7),
                    width: 1,
                  ),
                ),
                child: Text(
                  k['name'] as String,
                  style: TextStyle(
                    fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 13,
                    color: on ? Colors.white : const Color(0xFF4A3E3E),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static const _hargaWarna = Color(0xFFE64A19); // oranye-merah, seperti katalog

  /// Tinggi bagian teks kartu (di bawah gambar) menurut lebar kartu.
  static double _teksTinggi(double w) => w < 120 ? 64 : 84;

  /// Kartu menu: gambar persegi di atas (nomor di pojok kiri atas), lalu nama
  /// produk dan "mulai Rp...". Dipakai di grid katalog halaman kasir.
  Widget _tile(Rec p, double w) {
    final cs = Theme.of(context).colorScheme;
    final id = p['id'] as int;
    final name = p['name'] as String;
    final bg = _pal[id % _pal.length];
    final fg = bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final img = ProductImage.image(p['image_path'] as String?);
    final kecil = w < 120;
    final inCart =
        cart.where((e) => e.product == name).fold<int>(0, (a, e) => a + e.qty);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kecil ? 14 : 18),
        border: Border.all(
          color: inCart > 0
              ? cs.primary.withValues(alpha: 0.55)
              : const Color(0xFFF0E4E4),
          width: inCart > 0 ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: inCart > 0
                ? cs.primary.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kecil ? 14 : 18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _pick(p),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                if (img != null)
                  img
                else
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [bg, bg.withValues(alpha: 0.82)],
                      ),
                    ),
                    padding: const EdgeInsets.all(10),
                    alignment: Alignment.center,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.fastfood_rounded,
                          size: kecil ? 34 : 44,
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                        Text(name,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w800,
                                fontSize: kecil ? 12 : 15)),
                      ],
                    ),
                  ),
                Positioned(
                  left: kecil ? 6 : 8,
                  top: kecil ? 6 : 8,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: kecil ? 6 : 8, vertical: kecil ? 2 : 3),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 0.5)),
                    child: Text('#${id.toString().padLeft(2, '0')}',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: kecil ? 9.5 : 11)),
                  ),
                ),
                if (inCart > 0)
                  Positioned(
                    right: kecil ? 6 : 8,
                    top: kecil ? 6 : 8,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: kecil ? 6 : 8, vertical: kecil ? 2 : 3),
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [cs.primary, cs.secondary]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shopping_bag_rounded,
                              size: 10, color: Colors.white),
                          const SizedBox(width: 3),
                          Text('$inCart',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    kecil ? 8 : 12, kecil ? 6 : 8, kecil ? 8 : 12, 6),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: kecil ? 11 : 13.5,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2B1B1B))),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (p['minp'] != null)
                            Expanded(
                              child: Text(
                                'mulai ${rp(p['minp'] as int)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: kecil ? 10 : 12.5,
                                    color: _hargaWarna,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: inCart > 0
                                  ? cs.primary
                                  : cs.primaryContainer.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add,
                              size: kecil ? 12 : 14,
                              color: inCart > 0 ? Colors.white : cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------- Topping & Kantong Kresek (halaman karyawan) ----------
  static int _vid(Rec r) => (r['vid'] as num?)?.toInt() ?? -1;
  static int _hrg(Rec r) => (r['price'] as num?)?.toInt() ?? 0;
  static String _nm(Rec r) => (r['name'] ?? '').toString();

  bool _isKresek(Rec r) => _nm(r).toLowerCase().contains('kresek');

  /// Kategori Topping tampil sebagai dua kartu: Topping dan Kantong Kresek.
  bool get _isToppingCat => q.trim().isEmpty && cat == 'topping';

  int _qtyOfVariant(int vid) =>
      cart.where((e) => e.variantId == vid).fold<int>(0, (a, e) => a + e.qty);

  void _quickAdd(Rec r) {
    final vid = _vid(r);
    _mut(() {
      final i = cart.indexWhere((e) => e.variantId == vid && e.note.isEmpty);
      if (i >= 0) {
        cart[i].qty++;
      } else {
        cart.add(
            CartItem(vid, _nm(r), (r['kemasan'] ?? '').toString(), _hrg(r), 1));
      }
    });
  }

  /// Jendela daftar (judul, tombol tutup, baris nama + harga + "+ Tambah").
  void _openList(String title, List<Rec> items) {
    showDialog<void>(
      context: context,
      builder: (dc) => StatefulBuilder(builder: (dc, set) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700))),
                  Material(
                    color: const Color(0xFFF1F1F1),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.pop(dc),
                      child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.close, size: 18)),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Flexible(
                  child: items.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Belum ada item'))
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final r = items[i];
                            final n = _qtyOfVariant(_vid(r));
                            return Container(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 10, 10),
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: const Color(0xFFE6E6E6)),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_nm(r),
                                            style: const TextStyle(
                                                fontSize: 15,
                                                color: Colors.black87)),
                                        if (n > 0)
                                          Text('Di pesanan: $n',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: _hargaWarna,
                                                  fontWeight: FontWeight.w600)),
                                      ]),
                                ),
                                Text(rp(_hrg(r)),
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(width: 12),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _hargaWarna,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                  onPressed: () {
                                    _quickAdd(r);
                                    if (dc.mounted) set(() {});
                                  },
                                  child: const Text('+ Tambah',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ),
                              ]),
                            );
                          },
                        ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _bigTile(
      IconData icon, String title, String sub, int inCart, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0E4E4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: _hargaWarna.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: _hargaWarna),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(sub,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ]),
              ),
              if (inCart > 0)
                Badge(
                    backgroundColor: _hargaWarna,
                    label: Text('$inCart'),
                    child: const SizedBox(width: 8, height: 8)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<List<Rec>> _loadTop() => Db.q(
      'SELECT p.id AS pid, p.name AS name, v.id AS vid, v.kemasan AS kemasan, v.price AS price FROM products p JOIN variants v ON v.product_id=p.id WHERE p.active=1 AND p.category=? ORDER BY p.id, v.price',
      [cat]);

  Widget _toppingView() => FutureBuilder<List<Rec>>(
        key: const ValueKey('view-topping'),
        future: _topFut ??= _loadTop(),
        builder: (c, s) {
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = s.data!;
          final kresek = all.where(_isKresek).toList();
          final topping = all.where((r) => !_isKresek(r)).toList();
          int cnt(List<Rec> l) =>
              l.fold<int>(0, (a, r) => a + _qtyOfVariant(_vid(r)));
          return ListView(padding: const EdgeInsets.all(12), children: [
            _bigTile(
                Icons.local_fire_department_outlined,
                'Topping',
                'Pilih atau tambah topping',
                cnt(topping),
                () => _openList('Topping', topping)),
            const SizedBox(height: 10),
            _bigTile(
                Icons.shopping_bag_outlined,
                'Kantong Kresek',
                'Tambah kantong kresek',
                cnt(kresek),
                () => _openList('Kantong Kresek', kresek)),
          ]);
        },
      );

  // ---------- produk ----------
  Widget _grid() {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Cari menu atau ketik kode (#01)...',
              prefixIcon:
                  Icon(Icons.search_rounded, size: 22, color: cs.primary),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => _setCat(cat)),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: (v) => setState(() {
              q = v;
              _load();
            }),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Prefs.kategori.value == 'kompak'
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _chips())
            : _tabs(),
      ),
      const Divider(height: 1),
      if (_showTarget)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: TargetCard(outlet: Target.myOutlet(), tick: _tick),
        ),
      if (_isToppingCat)
        Expanded(child: _toppingView())
      else
        Expanded(
          child: FutureBuilder<List<Rec>>(
            key: const ValueKey('view-grid'),
            future: fut,
            builder: (c, s) {
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final ps = s.data!;
              if (ps.isEmpty) {
                return const Center(child: Text('Belum ada produk'));
              }
              if (Prefs.katalog.value == 'daftar') {
                return ListView(padding: const EdgeInsets.all(12), children: [
                  for (final p in ps)
                    Builder(builder: (_) {
                      final name = p['name'] as String;
                      final inCart = cart
                          .where((e) => e.product == name)
                          .fold<int>(0, (a, e) => a + e.qty);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: inCart > 0
                                ? cs.primary.withValues(alpha: 0.5)
                                : const Color(0xFFF0E4E4),
                            width: inCart > 0 ? 1.5 : 1,
                          ),
                        ),
                        child: ListTile(
                          onTap: () => _pick(p),
                          leading: ProductImage.thumb(
                                  p['image_path'] as String?,
                                  size: 46) ??
                              CircleAvatar(
                                  radius: 23,
                                  backgroundColor:
                                      _pal[(p['id'] as int) % _pal.length],
                                  child: Text(
                                      name.isEmpty
                                          ? '?'
                                          : name[0].toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold))),
                          title: Text(
                              '[#${(p['id'] as int).toString().padLeft(2, '0')}] $name',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: p['minp'] == null
                              ? null
                              : Text('Mulai ${rp(p['minp'] as int)}',
                                  style: const TextStyle(
                                      color: _hargaWarna,
                                      fontWeight: FontWeight.w700)),
                          trailing: inCart > 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('$inCart di keranjang',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                )
                              : Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer
                                        .withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.add,
                                      size: 16, color: cs.primary),
                                ),
                        ),
                      );
                    }),
                ]);
              }
              return LayoutBuilder(builder: (c, box) {
                final cols = Prefs.kolom.value;
                const pad = 12.0, gap = 12.0;
                final w = (box.maxWidth - pad * 2 - gap * (cols - 1)) / cols;
                return GridView.builder(
                  padding: const EdgeInsets.all(pad),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: gap,
                      crossAxisSpacing: gap,
                      // gambar persegi (setinggi lebar kartu) + bagian teks
                      mainAxisExtent: w + _teksTinggi(w)),
                  itemCount: ps.length,
                  itemBuilder: (_, i) => _tile(ps[i], w),
                );
              });
            },
          ),
        ),
    ]);
  }

  // ---------- keranjang ----------
  Widget _cartPanel({BuildContext? sheetCtx}) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(Icons.shopping_bag_rounded, color: cs.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Keranjang',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text('$_count item dipilih',
                    style: TextStyle(fontSize: 11, color: cs.outline)),
              ])),
          if (cart.isNotEmpty)
            TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                onPressed: () => _mut(cart.clear),
                label: const Text('Kosongkan', style: TextStyle(fontSize: 13))),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: cart.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.shopping_basket_outlined,
                          size: 32, color: cs.primary),
                    ),
                    const SizedBox(height: 14),
                    const Text('Belum ada pesanan',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Color(0xFF2B1B1B))),
                    const SizedBox(height: 4),
                    Text('Pilih produk dari menu untuk menambahkan',
                        style: TextStyle(fontSize: 13, color: cs.outline)),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: cart.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (_, i) {
                  final e = cart[i];
                  if (_isPromo(e)) {
                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.local_offer_rounded,
                            size: 18, color: cs.primary),
                      ),
                      title: Text(e.product,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('GRATIS',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w800,
                              fontSize: 11)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${e.qty}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: cs.primary)),
                      ),
                    );
                  }
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBFA),
                        border: Border.all(color: const Color(0xFFF3E4E2)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(e.product,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                            ),
                            const SizedBox(width: 6),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(32, 32),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.remove, size: 16),
                                onPressed: () => _mut(() {
                                  if (e.qty > 1) {
                                    e.qty--;
                                  } else {
                                    cart.removeAt(i);
                                  }
                                }),
                              ),
                              SizedBox(
                                width: 32,
                                child: Text('${e.qty}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14)),
                              ),
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(32, 32),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                onPressed: () async {
                                  final item = e;
                                  final kemasan = item.kemasan;
                                  final l = await _left(kemasan);
                                  if (!mounted || !cart.contains(item)) return;
                                  if (l != null && _inCart(kemasan) >= l) {
                                    _snack('Stok kemasan $kemasan habis');
                                    return;
                                  }
                                  _mut(() => item.qty++);
                                },
                              ),
                            ]),
                          ]),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 3, children: [
                            if (e.kemasan.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer
                                      .withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(e.kemasan,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: cs.primary)),
                              ),
                            Text('${rp(e.price)} × ${e.qty} = ${rp(e.sub)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.outline,
                                    fontWeight: FontWeight.w600)),
                          ]),
                          if (e.note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text('Catatan: ${e.note}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: Color(0xFF6B5555))),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if ((_isFriday && _promoEligible > 0) || _promoInCart > 0)
            _promoBar(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: .12),
                  cs.primaryContainer.withValues(alpha: .38)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
            ),
            child: Row(children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Tagihan',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onPrimaryContainer)),
                  const SizedBox(height: 2),
                  Text(rp(_total),
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          color: cs.primary)),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: 22),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                elevation: 2,
                shadowColor: cs.primary.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: cart.isEmpty
                  ? null
                  : () {
                      if (sheetCtx != null) {
                        _sheetSet = null;
                        Navigator.pop(sheetCtx);
                      }
                      _confirm();
                    },
              icon: const Icon(Icons.payments_rounded, size: 20),
              label: Text(
                cart.isEmpty ? 'Pilih Menu' : 'Bayar Sekarang',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }

  /// Tombol + / - Jumat Promo di atas subtotal (gratis, tanpa harga).
  Widget _promoBar() {
    final cs = Theme.of(context).colorScheme;
    final inCart = _promoInCart;
    final note = _promoStock <= 0
        ? 'Stok Jumat Promo habis'
        : 'Gratis • berhak $_promoEligible • stok $_promoStock';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
          color: cs.secondaryContainer.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.local_offer_outlined, size: 18, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Jumat Promo',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(note,
                style: TextStyle(
                    fontSize: 11,
                    color: _promoStock <= 0 ? Colors.red : cs.outline)),
          ]),
        ),
        IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Kurangi Jumat Promo',
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: inCart > 0 ? () => _setPromo(-1) : null),
        Text('$inCart',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Tambah Jumat Promo (gratis)',
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: inCart < _promoMax ? () => _setPromo(1) : null),
      ]),
    );
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => StatefulBuilder(builder: (c, set) {
        _sheetSet = set;
        return SizedBox(
            height: MediaQuery.of(c).size.height * 0.75,
            child: _cartPanel(sheetCtx: c));
      }),
    ).whenComplete(() => _sheetSet = null);
  }

  Widget _bottomBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, cs.secondary],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _openCart,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shopping_bag_outlined,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 6),
                    Text('$_count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Total Tagihan',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500)),
                    Text(rp(_total),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Lihat & Bayar',
                        style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded,
                        size: 16, color: cs.primary),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, box) {
        if (box.maxWidth >= 560) {
          return Row(children: [
            Expanded(child: _grid()),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 340,
              child: Material(
                color: Colors.white,
                child: _cartPanel(),
              ),
            ),
          ]);
        }
        return Column(children: [
          Expanded(child: _grid()),
          if (cart.isNotEmpty) _bottomBar(),
        ]);
      });
}

// =====================================================================
// Pembayaran: langkah 1 pilih Cash / QRIS (QRIS: pilih potongan 0-100%),
// langkah 2 bayar.
// Tombol "Uang Pas" langsung memproses pembayaran + cetak nota.
// =====================================================================
class PayDialog extends StatefulWidget {
  final List<CartItem> items;
  const PayDialog({super.key, required this.items});
  @override
  State<PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<PayDialog> {
  int step = 0;
  bool disc = false, askPct = false, busy = false, qris = false;
  int jajan = 0; // jumlah jajan Rp 500 yang menggantikan sebagian kembalian
  final pct = TextEditingController(), cash = TextEditingController();

  @override
  void dispose() {
    pct.dispose();
    cash.dispose();
    super.dispose();
  }

  int get sub => widget.items.fold<int>(0, (a, e) => a + e.sub);
  double get p => disc || askPct
      ? (double.tryParse(pct.text.replaceAll(',', '.')) ?? 0)
          .clamp(0, 100)
          .toDouble()
      : 0;
  double get _rawPct => double.tryParse(pct.text.replaceAll(',', '.')) ?? 0;
  int get total => sub - (sub * (disc ? p : 0) / 100).round();
  int get received => moneyOf(cash.text);
  int get change => received - total;
  int get maxJajan => change > 0 ? change ~/ kJajanPrice : 0;
  int get jj => jajan.clamp(0, maxJajan).toInt();
  String get pctStr => p % 1 == 0 ? p.toInt().toString() : p.toString();

  List<int> get _suggest {
    int up(int u) => ((total + u - 1) ~/ u) * u;
    final s = <int>{up(5000), up(10000), up(20000), up(50000), up(100000)}
      ..remove(total);
    final l = s.toList()..sort();
    return l.take(3).toList();
  }

  Future<void> _pay(int paid, {String method = 'Tunai', int jajan = 0}) async {
    if (busy || paid < total) return; // cegah klik ganda
    setState(() => busy = true);
    final t = await Db.saveTrx(widget.items, disc ? p : 0, paid,
        method: method, jajan: jajan);
    bool ok = false;
    try {
      ok = await Printer.printTrx(t); // langsung cetak, tanpa PDF
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context, <String, Object?>{'trx': t, 'printed': ok});
  }

  Widget _big(IconData icon, String label, VoidCallback onTap,
      {bool on = false}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: on ? cs.primaryContainer : null,
          border: Border.all(
              color: on ? cs.primary : cs.outlineVariant, width: on ? 2 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Icon(icon, size: 30, color: cs.primary),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _head(String title, {VoidCallback? back}) => Row(children: [
        if (back != null)
          IconButton(
              onPressed: busy ? null : back,
              icon: const Icon(Icons.arrow_back)),
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        IconButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close)),
      ]);

  Widget _stepDiskon() {
    final potongan = (sub * p / 100).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head('Konfirmasi Pesanan'),
      const SizedBox(height: 4),
      for (final e in widget.items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(
                child: Text(
                    '${e.qty}x ${e.product}${kemTag(e.kemasan)}${e.note.isEmpty ? '' : '\nCatatan: ${e.note}'}')),
            Text(rp(e.sub))
          ]),
        ),
      const Divider(height: 24),
      Row(children: [
        const Text('Subtotal', style: TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(rp(sub),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))
      ]),
      const SizedBox(height: 20),
      const Text('Pilih jenis pembayaran',
          style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _big(
              Icons.payments_outlined,
              'Cash',
              () => setState(() {
                    disc = false;
                    qris = false;
                    askPct = false;
                    step = 1;
                  })),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: _big(
                Icons.qr_code_2,
                'QRIS',
                () => setState(() {
                      askPct = true;
                      if (pct.text.isEmpty) pct.text = '5';
                    }),
                on: askPct)),
      ]),
      if (askPct) ...[
        const SizedBox(height: 16),
        TextField(
          controller: pct,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: 'Potongan QRIS (0–100)',
              suffixText: '%',
              errorText: _rawPct > 100 ? 'Maksimal 100%' : null,
              border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final n in [0, 5, 10, 15, 20, 25])
            ActionChip(
                label: Text('$n%'),
                onPressed: () => setState(() => pct.text = '$n')),
        ]),
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(p > 0
                ? 'Potongan ${rp(potongan)} → total ${rp(sub - potongan)}'
                : 'Tanpa potongan → total ${rp(sub)}')),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _rawPct <= 100
              ? () => setState(() {
                    qris = true;
                    disc = true;
                    step = 2;
                  })
              : null,
          child: const Text('Lanjut ke Pembayaran QRIS'),
        ),
      ],
    ]);
  }

  Widget _stepBayar() {
    final cs = Theme.of(context).colorScheme;
    final enough = received >= total;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head('Pembayaran', back: () => setState(() => step = 0)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          const Text('Total Bayar'),
          Text(rp(total),
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (disc)
            Text('Subtotal ${rp(sub)} − diskon $pctStr% (${rp(sub - total)})',
                style: const TextStyle(fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 60,
        child: FilledButton.icon(
          onPressed: busy
              ? null
              : () => _pay(total), // uang pas -> langsung bayar & cetak
          icon: const Icon(Icons.bolt),
          label: Text('UANG PAS  •  ${rp(total)}',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
      ),
      const SizedBox(height: 14),
      Row(children: [
        const Expanded(child: Divider()),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('atau uang diterima',
                style: TextStyle(color: cs.outline))),
        const Expanded(child: Divider())
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final n in _suggest)
          ActionChip(
              label: Text(rp(n)),
              onPressed:
                  busy ? null : () => setState(() => cash.text = moneyText(n))),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: cash,
        keyboardType: TextInputType.number,
        inputFormatters: [MoneyInputFormatter()],
        enabled: !busy,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
            labelText: 'Uang diterima',
            prefixText: 'Rp. ',
            border: OutlineInputBorder()),
      ),
      if (received > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              enough
                  ? 'Kembalian: ${rp(received - total)}'
                  : 'Kurang: ${rp(total - received)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: enough ? Colors.green.shade700 : Colors.red)),
        ),
      if (enough && maxJajan > 0)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.fastfood_outlined, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Jajan ${rp(kJajanPrice)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Tukar kembalian dengan jajan (maks $maxJajan)',
                        style: TextStyle(fontSize: 12, color: cs.outline)),
                  ])),
              IconButton(
                  onPressed: busy || jj == 0
                      ? null
                      : () => setState(() => jajan = jj - 1),
                  icon: const Icon(Icons.remove_circle_outline)),
              SizedBox(
                  width: 26,
                  child: Text('$jj',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 17))),
              IconButton(
                  onPressed: busy || jj >= maxJajan
                      ? null
                      : () => setState(() => jajan = jj + 1),
                  icon: const Icon(Icons.add_circle_outline)),
            ]),
            if (jj > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, right: 8),
                child: Text(
                    'Jajan $jj × ${rp(kJajanPrice)} = ${rp(jj * kJajanPrice)}  •  Kembalian uang: ${rp(change - jj * kJajanPrice)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700)),
              ),
          ]),
        ),
      const SizedBox(height: 12),
      SizedBox(
        height: 48,
        child: FilledButton.tonalIcon(
          onPressed: busy || !enough ? null : () => _pay(received, jajan: jj),
          icon: const Icon(Icons.print),
          label: const Text('Bayar & Cetak Nota'),
        ),
      ),
      if (busy)
        const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator()),
    ]);
  }

  Widget _stepQris() {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head('Pembayaran QRIS',
          back: () => setState(() {
                step = 0;
                qris = false;
                disc = false;
                askPct = true; // potongan tetap terisi, bisa diubah
              })),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          const Text('Total Bayar'),
          Text(rp(total),
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (sub - total > 0)
            Text(
                'Subtotal ${rp(sub)} − potongan QRIS $pctStr% (${rp(sub - total)})',
                style: const TextStyle(fontSize: 12))
          else
            Text('Subtotal ${rp(sub)} • tanpa potongan',
                style: const TextStyle(fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 16),
      Text(
          'Minta pelanggan scan QRIS dan membayar sesuai total. Tekan tombol di bawah setelah pembayaran berhasil.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.outline)),
      const SizedBox(height: 16),
      SizedBox(
        height: 60,
        child: FilledButton.icon(
          onPressed: busy ? null : () => _pay(total, method: 'QRIS'),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Konfirmasi Pembayaran Berhasil',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
      if (busy)
        const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator()),
    ]);
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: step == 0
                  ? _stepDiskon()
                  : step == 1
                      ? _stepBayar()
                      : _stepQris()),
        ),
      );
}

// ===================== LAYAR TRANSAKSI BERHASIL =====================
class _SuccessView extends StatelessWidget {
  final Rec t;
  final bool printed;
  const _SuccessView({required this.t, required this.printed});

  void _snack(BuildContext c, String s) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));

  Widget _box(BuildContext c, String label, String value, double w,
      {Color? color}) {
    final cs = Theme.of(c).colorScheme;
    return Container(
      width: w,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFFFFFDFC),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 12, color: cs.outline, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 17, color: color)),
        ),
      ]),
    );
  }

  Widget _btn(BuildContext c, String label, Future<void> Function() f) =>
      Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              side: BorderSide(color: Theme.of(c).colorScheme.outlineVariant)),
          onPressed: f,
          child: Text(label,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      );

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final date = DateFormat('dd-MMM-yyyy, HH:mm')
        .format(DateTime.parse(t['created_at'] as String));
    final isQris = t['payment'] == 'QRIS';
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE8F5E9),
                    border:
                        Border.all(color: const Color(0xFF81C784), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Color(0xFF2E7D32), size: 44),
                ),
                const SizedBox(height: 16),
                const Text('Transaksi Berhasil',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(date, style: TextStyle(fontSize: 13, color: cs.outline)),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (printed ? Colors.green : Colors.red)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    printed
                        ? '✓ Struk sudah dicetak'
                        : '! Struk belum tercetak, cek printer',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: printed
                            ? Colors.green.shade800
                            : Colors.red.shade800),
                  ),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(builder: (c2, cons) {
                  final cols = cons.maxWidth >= 560 ? 4 : 2;
                  final w = (cons.maxWidth - 10 * (cols - 1)) / cols;
                  return Wrap(spacing: 10, runSpacing: 10, children: [
                    _box(c, 'Pembayaran', isQris ? 'QRIS' : 'Tunai', w),
                    _box(c, 'Total Tagihan', rp(t['total'] as int), w),
                    if (isQris) ...[
                      _box(c, 'Potongan QRIS ${t['discount_pct']}%',
                          rp(t['discount_amt'] as int), w),
                      _box(c, 'Status', 'Lunas', w, color: Colors.green),
                    ] else ...[
                      _box(c, 'Diterima', rp(t['cash'] as int), w),
                      _box(c, 'Kembalian', rp(t['change_amt'] as int), w,
                          color: Colors.red),
                      if (jajanOf(t) > 0) ...[
                        _box(
                            c,
                            'Jajan ${rp(kJajanPrice)}',
                            '${jajanOf(t)} pcs • ${rp(jajanOf(t) * kJajanPrice)}',
                            w),
                        _box(
                            c,
                            'Kembalian uang',
                            rp((t['change_amt'] as int) -
                                jajanOf(t) * kJajanPrice),
                            w),
                      ],
                    ],
                  ]);
                }),
                const SizedBox(height: 16),
                Row(children: [
                  _btn(c, 'Cetak Struk', () async {
                    final ok = await Printer.printTrx(t);
                    if (c.mounted) {
                      _snack(
                          c,
                          ok
                              ? 'Struk dicetak'
                              : 'Gagal mencetak, cek koneksi printer');
                    }
                  }),
                  const SizedBox(width: 10),
                  _btn(c, 'Kirim Struk', () async {
                    await Clipboard.setData(
                        ClipboardData(text: await Printer.receiptText(t)));
                    if (c.mounted) {
                      _snack(
                          c, 'Struk disalin. Tempel di WhatsApp atau pesan.');
                    }
                  }),
                  const SizedBox(width: 10),
                  _btn(c, 'Cetak Pesanan', () async {
                    final ok = await Printer.printOrder(t);
                    if (c.mounted) {
                      _snack(
                          c,
                          ok
                              ? 'Pesanan dicetak'
                              : 'Gagal mencetak, cek koneksi printer');
                    }
                  }),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2EBD6B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 2),
                    onPressed: () => Navigator.pop(c),
                    icon:
                        const Icon(Icons.add_circle_outline_rounded, size: 20),
                    label: const Text('Transaksi Baru',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
