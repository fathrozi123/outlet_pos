import 'package:flutter/foundation.dart';
import 'db.dart';

/// Preferensi tampilan (disimpan di tabel settings).
class Prefs {
  static final kategori = ValueNotifier<String>('reguler'); // reguler | kompak
  static final katalog = ValueNotifier<String>('grid'); // grid | daftar
  static final kolom = ValueNotifier<int>(4); // 2..6

  static Future<void> load() async {
    kategori.value = await Db.getSetting('ui_kategori') ?? 'reguler';
    katalog.value = await Db.getSetting('ui_katalog') ?? 'grid';
    kolom.value =
        (int.tryParse(await Db.getSetting('ui_kolom') ?? '') ?? 4).clamp(2, 6);
  }

  static Future<void> setKategori(String v) async {
    kategori.value = v;
    await Db.setSetting('ui_kategori', v);
  }

  static Future<void> setKatalog(String v) async {
    katalog.value = v;
    await Db.setSetting('ui_katalog', v);
  }

  static Future<void> setKolom(int v) async {
    kolom.value = v;
    await Db.setSetting('ui_kolom', '$v');
  }
}
