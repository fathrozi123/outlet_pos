import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db.dart';

/// Pesanan yang disimpan (belum dibayar), per outlet. Disimpan di SQLite
/// sehingga tetap ada walau aplikasi ditutup.
class HeldOrders {
  /// Jumlah pesanan tersimpan outlet ini (untuk lencana di tombol).
  static final count = ValueNotifier<int>(0);

  /// Pesanan yang dipilih untuk dilanjutkan; didengar oleh halaman Transaksi.
  static final resume = ValueNotifier<Rec?>(null);

  /// Buka daftar pesanan tersimpan (dipanggil langsung oleh tombol).
  static Future<void> open(BuildContext context) async {
    final o = await showModalBottomSheet<Rec>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const HeldSheet(),
    );
    if (o != null) resume.value = o;
  }

  static Future<void> _ensure() async {
    final d = await Db.db;
    await d.execute(
        'CREATE TABLE IF NOT EXISTS held_orders(id INTEGER PRIMARY KEY AUTOINCREMENT, outlet TEXT, label TEXT, items TEXT, qty INTEGER DEFAULT 0, total INTEGER DEFAULT 0, user_name TEXT, created_at TEXT)');
  }

  static Future<void> refresh() async {
    await _ensure();
    final r = await Db.q('SELECT COUNT(*) AS n FROM held_orders WHERE outlet=?',
        [Session.outlet]);
    count.value = (r.first['n'] as int?) ?? 0;
  }

  static Future<List<Rec>> list() async {
    await _ensure();
    return Db.q('SELECT * FROM held_orders WHERE outlet=? ORDER BY id DESC',
        [Session.outlet]);
  }

  static Future<void> save(List<CartItem> items, String label) async {
    await _ensure();
    final d = await Db.db;
    await d.insert('held_orders', {
      'outlet': Session.outlet,
      'label': label,
      'items': jsonEncode([
        for (final e in items)
          {
            'v': e.variantId,
            'p': e.product,
            'k': e.kemasan,
            'pr': e.price,
            'q': e.qty,
            'n': e.note,
          }
      ]),
      'qty': items.fold<int>(0, (a, e) => a + e.qty),
      'total': items.fold<int>(0, (a, e) => a + e.sub),
      'user_name': Session.name,
      'created_at': DateTime.now().toIso8601String(),
    });
    await refresh();
  }

  static Future<void> delete(int id) async {
    final d = await Db.db;
    await d.delete('held_orders', where: 'id=?', whereArgs: [id]);
    await refresh();
  }

  static List<CartItem> decode(String json) {
    try {
      final l = jsonDecode(json) as List;
      return [
        for (final m in l)
          CartItem(
            (m['v'] as num).toInt(),
            m['p'] as String,
            (m['k'] ?? '') as String,
            (m['pr'] as num).toInt(),
            (m['q'] as num).toInt(),
            note: (m['n'] ?? '') as String,
          )
      ];
    } catch (_) {
      return [];
    }
  }
}

/// Tombol pojok atas: buka daftar pesanan tersimpan (dengan lencana jumlah).
class HeldButton extends StatelessWidget {
  final Color? color;
  const HeldButton({super.key, this.color});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: HeldOrders.count,
        builder: (_, n, __) => IconButton(
          tooltip: 'Pesanan tersimpan',
          color: color,
          onPressed: () => HeldOrders.open(context),
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text('$n'),
            child: const Icon(Icons.bookmarks_rounded),
          ),
        ),
      );
}

/// Daftar pesanan tersimpan. Menutup dengan pesanan yang dipilih untuk
/// dilanjutkan (null bila hanya ditutup).
class HeldSheet extends StatefulWidget {
  const HeldSheet({super.key});
  @override
  State<HeldSheet> createState() => _HeldSheetState();
}

class _HeldSheetState extends State<HeldSheet> {
  late Future<List<Rec>> fut = HeldOrders.list();

  String _ringkas(List<CartItem> its) => its
      .map((e) =>
          '${e.qty}× ${e.product}${e.kemasan.isEmpty ? '' : ' (${e.kemasan})'}')
      .join(', ');

  Future<void> _hapus(Rec o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus pesanan tersimpan?'),
        content:
            const Text('Pesanan ini akan dihapus dan tidak bisa dikembalikan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Color(0xFF97291F)),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    await HeldOrders.delete(o['id'] as int);
    if (mounted) setState(() => fut = HeldOrders.list());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(children: [
            Icon(Icons.bookmarks_rounded, color: cs.primary),
            const SizedBox(width: 10),
            Text('Pesanan Tersimpan',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<Rec>>(
            future: fut,
            builder: (c, s) {
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = s.data!;
              if (rows.isEmpty) {
                return Center(
                    child: Text('Belum ada pesanan tersimpan.',
                        style: TextStyle(color: cs.outline)));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final o = rows[i];
                  final its = HeldOrders.decode((o['items'] ?? '[]') as String);
                  final label = ((o['label'] ?? '') as String).trim();
                  final t =
                      DateTime.tryParse((o['created_at'] ?? '') as String);
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(
                                  label.isEmpty ? 'Pesanan #${o['id']}' : label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                            ),
                            if (t != null)
                              Text(DateFormat('HH:mm • dd/MM').format(t),
                                  style: TextStyle(
                                      fontSize: 11, color: cs.outline)),
                          ]),
                          const SizedBox(height: 6),
                          Text(_ringkas(its),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5)),
                          const SizedBox(height: 8),
                          Row(children: [
                            Text(rp((o['total'] ?? 0) as num),
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: cs.primary)),
                            const Spacer(),
                            IconButton(
                                tooltip: 'Hapus',
                                color: Color(0xFF97291F),
                                onPressed: () => _hapus(o),
                                icon: const Icon(Icons.delete_outline)),
                            FilledButton.icon(
                              onPressed: its.isEmpty
                                  ? null
                                  : () => Navigator.pop(context, o),
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 20),
                              label: const Text('Lanjutkan'),
                            ),
                          ]),
                        ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
