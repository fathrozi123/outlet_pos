import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Gambar produk: dipilih dari galeri/kamera, disalin ke folder aplikasi,
/// lalu path-nya disimpan di kolom products.image_path.
class ProductImage {
  static final _picker = ImagePicker();

  /// Pilih gambar dan simpan ke folder aplikasi. Mengembalikan path file baru,
  /// atau null kalau dibatalkan.
  static Future<String?> pick(ImageSource src) async {
    final x = await _picker.pickImage(
        source: src, maxWidth: 900, maxHeight: 900, imageQuality: 85);
    if (x == null) return null;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'product_images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = p.extension(x.path).isEmpty ? '.jpg' : p.extension(x.path);
    final dest =
        p.join(dir.path, 'img_${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(x.path).copy(dest);
    return dest;
  }

  /// Hapus file gambar dari penyimpanan (aman dipanggil dengan null).
  static Future<void> remove(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Widget gambar penuh (BoxFit.cover), atau null kalau tidak ada/hilang.
  static Widget? image(String? path, {BoxFit fit = BoxFit.cover}) {
    if (path == null || path.isEmpty || !File(path).existsSync()) return null;
    return Image.file(File(path),
        fit: fit, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image));
  }

  /// Thumbnail kotak kecil bersudut tumpul, atau null kalau tidak ada gambar.
  static Widget? thumb(String? path, {double size = 48}) {
    final img = image(path);
    if (img == null) return null;
    return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: size, height: size, child: img));
  }
}
