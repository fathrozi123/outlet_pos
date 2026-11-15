import 'package:flutter/material.dart';
import 'db.dart';

/// Pengaturan nota (nama outlet, alamat/kontak, pesan footer) PER OUTLET.
/// Diatur dari menu Outlet lewat tombol "Pengaturan Nota".
/// Outlet yang belum pernah diatur memakai pengaturan lama (global) supaya
/// nota yang sudah berjalan tidak berubah.
class NotaCfg {
  static String _k(String outlet, String f) => 'nota|$outlet|$f';

  static Future<String> _one(String outlet, String f, String legacy) async =>
      await Db.getSetting(_k(outlet, f)) ?? await Db.getSetting(legacy) ?? '';

  /// Kunci: 'name', 'addr', 'footer'.
  static Future<Map<String, String>> get(String outlet) async => {
        'name': await _one(outlet, 'name', 'outlet_name'),
        'addr': await _one(outlet, 'addr', 'outlet_addr'),
        'footer': await _one(outlet, 'footer', 'footer'),
      };

  static Future<void> set(String outlet, Map<String, String> v) async {
    for (final f in const ['name', 'addr', 'footer']) {
      await Db.setSetting(_k(outlet, f), (v[f] ?? '').trim());
    }
  }

  /// Dialog pengaturan nota satu outlet. true = tersimpan.
  static Future<bool> dialog(BuildContext context, String outlet) async {
    final cur = await get(outlet);
    final name = TextEditingController(text: cur['name']);
    final addr = TextEditingController(text: cur['addr']);
    final foot = TextEditingController(text: cur['footer']);
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Pengaturan Nota • $outlet'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Nama Outlet (judul nota)')),
              const SizedBox(height: 8),
              TextField(
                  controller: addr,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Alamat / Kontak')),
              const SizedBox(height: 8),
              TextField(
                  controller: foot,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Pesan Footer')),
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
    );
    if (ok != true) return false;
    await set(outlet, {
      'name': name.text,
      'addr': addr.text,
      'footer': foot.text,
    });
    return true;
  }
}
