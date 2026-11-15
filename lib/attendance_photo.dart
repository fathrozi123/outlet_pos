import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Foto absensi: diambil LANGSUNG dari kamera (tanpa pilih galeri),
/// disimpan di folder aplikasi, path-nya masuk ke tabel attendance
/// (photo_in / photo_out).
class AttendancePhoto {
  static final _picker = ImagePicker();

  /// Buka kamera (kamera depan lebih dulu). Mengembalikan path foto,
  /// atau null kalau dibatalkan.
  static Future<String?> capture() async {
    final x = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70);
    if (x == null) return null;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'attendance_photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest =
        p.join(dir.path, 'abs_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(x.path).copy(dest);
    return dest;
  }

  static bool exists(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();

  /// Foto kecil + label di bawahnya; diketuk untuk memperbesar.
  /// Kalau fotonya tidak ada (absen lama), tampil kotak abu-abu.
  ///
  /// Ukuran foto menyesuaikan perangkat: sedikit lebih besar di tablet, dan
  /// otomatis mengecil kalau tinggi yang tersedia kurang (tidak overflow).
  static Widget chip(
      BuildContext context, String? path, String label, String caption,
      {double size = 44}) {
    final ok = exists(path);
    final wide = MediaQuery.of(context).size.shortestSide >= 600;
    final want = wide ? size * 1.25 : size;
    return LayoutBuilder(builder: (context, box) {
      // ruang untuk teks label di bawah foto (sudah termasuk skala font)
      final scale = MediaQuery.textScalerOf(context).scale(10);
      final labelH = scale * 1.3 + 2;
      var img = want;
      if (box.maxHeight.isFinite) {
        img = (box.maxHeight - labelH).clamp(20.0, want).toDouble();
      }
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: ok ? () => show(context, path!, caption) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: img,
                height: img,
                child: ok
                    ? Image.file(File(path!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image))
                    : Container(
                        color: Colors.grey.withValues(alpha: .2),
                        child: const Icon(Icons.no_photography_outlined,
                            size: 20, color: Colors.grey)),
              ),
            ),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, height: 1.3)),
          ]),
        ),
      );
    });
  }

  /// Tampilkan foto ukuran besar (bisa di-zoom). Lebar dibatasi di tablet,
  /// dan isi bisa di-scroll kalau layar pendek (mis. HP landscape).
  static Future<void> show(BuildContext context, String path, String caption) {
    final h = MediaQuery.of(context).size.height;
    return showDialog(
      context: context,
      builder: (d) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(caption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: h * .6),
                child: InteractiveViewer(
                  child: Image.file(File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Icon(Icons.broken_image, size: 48))),
                ),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(d),
                  child: const Text('Tutup')),
            ]),
          ),
        ),
      ),
    );
  }
}
