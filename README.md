# Kasir Outlet (Flutter + SQLite + printer thermal Bluetooth)

## Cara menjalankan di VS Code (3 langkah)
Prasyarat sekali saja: Flutter SDK + Android Studio (Android SDK) + ekstensi Flutter di VS Code. Cek dengan `flutter doctor`.

1. Ekstrak zip, lalu **File > Open Folder** di VS Code, pilih folder `outlet_pos`.
2. Setup otomatis (cukup sekali, butuh internet):
   - Windows: klik dua kali `setup.bat`
   - atau di VS Code: **Terminal > Run Task... > Setup Kasir Outlet**
   - atau di terminal: `dart tool/setup.dart`
3. Sambungkan HP/tablet Android (USB debugging aktif), pilih perangkat di pojok kanan bawah VS Code, tekan **F5**.

Setup otomatis membuat folder `android/`, menambah izin Bluetooth, dan menjalankan `flutter pub get`. Kode di `lib/` tidak diubah.

## Login awal (segera ganti password)
- Admin: `admin` / `admin123`
- Karyawan: `karyawan` / `karyawan123`

## Printer
Pairing printer thermal dulu di Pengaturan Bluetooth Android. Lalu di aplikasi: Pengaturan > Cari printer > pilih > Tes cetak.
Bluetooth tidak jalan di emulator, gunakan perangkat asli.
