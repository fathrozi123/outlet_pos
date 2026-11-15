// Setup otomatis: membuat folder android/, menambah izin Bluetooth, dan flutter pub get.
// Dijalankan lewat setup.bat (Windows) / setup.sh (Mac/Linux) atau task VS Code.
import 'dart:io';

Future<int> run(String cmd, List<String> args) async {
  stdout.writeln('> $cmd ${args.join(' ')}');
  final p = await Process.start(cmd, args, runInShell: true, mode: ProcessStartMode.inheritStdio);
  return p.exitCode;
}

Future<void> main() async {
  Directory.current = File(Platform.script.toFilePath()).parent.parent;
  if (!File('pubspec.yaml').existsSync() || !Directory('lib').existsSync()) {
    stderr.writeln('pubspec.yaml / lib tidak ditemukan. Jalankan dari folder proyek.');
    exit(1);
  }

  // Cadangkan kode kita, karena flutter create bisa menimpa file bawaan.
  final pub = File('pubspec.yaml').readAsBytesSync();
  final backup = <String, List<int>>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    backup[f.path] = f.readAsBytesSync();
  }

  if (!Directory('android').existsSync()) {
    final code = await run('flutter', ['create', '--platforms=android', '--project-name=outlet_pos', '--org=com.outlet', '.']);
    if (code != 0) {
      stderr.writeln('\nGagal menjalankan "flutter create". Pastikan Flutter sudah terpasang (cek: flutter doctor).');
      exit(code);
    }
  } else {
    stdout.writeln('Folder android sudah ada, dilewati.');
  }

  // Kembalikan kode kita.
  File('pubspec.yaml').writeAsBytesSync(pub);
  backup.forEach((path, bytes) => File(path).writeAsBytesSync(bytes));
  final test = Directory('test');
  if (test.existsSync()) test.deleteSync(recursive: true); // test bawaan merujuk MyApp yang sudah tidak ada

  // Izin Bluetooth + nama aplikasi.
  final mf = File('android/app/src/main/AndroidManifest.xml');
  var s = mf.readAsStringSync();
  if (!s.contains('BLUETOOTH_CONNECT')) {
    const perms = [
      '<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>',
      '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>',
      '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>',
      '<uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>',
      '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>',
    ];
    s = s.replaceFirst('<application', '${perms.join('\n    ')}\n    <application');
  }
  s = s.replaceFirst('android:label="outlet_pos"', 'android:label="Kasir Outlet"');
  mf.writeAsStringSync(s);
  stdout.writeln('Izin Bluetooth ditambahkan ke AndroidManifest.xml');

  final code = await run('flutter', ['pub', 'get']);
  if (code != 0) exit(code);
  stdout.writeln('\n=== SETUP SELESAI ===\nSambungkan HP/tablet Android (USB debugging aktif), lalu tekan F5 di VS Code.');
}
