import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'target.dart';

/// Halaman pegawai: melihat stok kemasan di outlet sendiri (hanya lihat).
/// Stok berkurang otomatis setiap ada penjualan (lihat Db.saveTrx), jadi
/// angka di sini bergerak bersama hitungan terjual di kartu target.
/// Stok hanya bisa diubah admin lewat menu "Target & Stok Kemasan".
/// Satu-satunya yang bisa diatur pegawai: kemasan Jumat Promo (tombol +),
/// yang langsung mengurangi kemasan Normal.
class StokKemasanPage extends StatefulWidget {
  const StokKemasanPage({super.key});
  @override
  State<StokKemasanPage> createState() => _StokKemasanPageState();
}

class _StokKemasanPageState extends State<StokKemasanPage> {
  Map<String, int> stock = {for (final n in Target.names) n: 0};
  int promo = 0;
  bool loading = true, busy = false;
  DateTime? updated;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    // Muat ulang berkala agar angka mengikuti penjualan terbaru.
    _t = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await Target.stock(Target.myOutlet());
    final p = await Target.promoStock(Target.myOutlet());
    if (!mounted) return;
    setState(() {
      stock = s;
      promo = p;
      loading = false;
      updated = DateTime.now();
    });
  }

  // Jumat Promo diambil dari Normal, jadi ikut dihitung agar total tidak turun.
  int get _total => stock.values.fold<int>(0, (a, b) => a + b) + promo;

  Future<void> _move(int delta) async {
    if (busy) return;
    setState(() => busy = true);
    final err = await Target.movePromo(Target.myOutlet(), delta);
    await _load();
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Widget _promoRow(ColorScheme cs) {
    return Card(
      color: cs.secondaryContainer.withValues(alpha: .5),
      child: ListTile(
        leading: Icon(Icons.local_offer_outlined, color: cs.primary),
        title: const Text('Kemasan Jumat Promo',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('+ mengurangi kemasan Normal'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 44,
              child: Text('$promo',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900))),
          IconButton.filledTonal(
              tooltip: 'Tambah Jumat Promo (kurangi Normal)',
              onPressed:
                  busy || (stock['Normal'] ?? 0) <= 0 ? null : () => _move(1),
              icon: const Icon(Icons.add)),
        ]),
      ),
    );
  }

  Widget _row(String n, ColorScheme cs) {
    final s = stock[n] ?? 0;
    final habis = s <= 0;
    final tipis = !habis && s < 10;
    final color = habis
        ? Colors.red
        : tipis
            ? Colors.orange.shade800
            : cs.onSurface;
    return Card(
      child: ListTile(
        leading: Icon(Icons.inventory_2_outlined, color: color),
        title: Text('Kemasan $n',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: habis
            ? const Text('Habis', style: TextStyle(color: Colors.red))
            : tipis
                ? Text('Menipis',
                    style: TextStyle(color: Colors.orange.shade800))
                : null,
        trailing: Text('$s',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900, color: color)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final outlet = Target.myOutlet();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text('Stok Kemasan${outlet.isEmpty ? '' : ' • $outlet'}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
              updated == null
                  ? 'Memuat...'
                  : 'Diperbarui ${DateFormat('HH:mm:ss').format(updated!)} • tarik ke bawah untuk memuat ulang',
              style: TextStyle(fontSize: 12, color: cs.outline)),
          const SizedBox(height: 12),
          if (loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                const Text('Total Kemasan'),
                Text('$_total',
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(fontWeight: FontWeight.w900)),
              ]),
            ),
            const SizedBox(height: 12),
            for (final n in Target.names) _row(n, cs),
            _promoRow(cs),
            if (_total == 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                    'Stok belum diisi. Minta admin mengisi stok di menu Target & Stok Kemasan.',
                    style: TextStyle(fontSize: 12, color: cs.outline)),
              ),
          ],
        ],
      ),
    );
  }
}
