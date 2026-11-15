import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db.dart';
import 'login.dart';
import 'prefs.dart';

const kRed = Color(0xFFD32F2F);

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(seedColor: kRed, brightness: Brightness.light)
          .copyWith(
    primary: kRed,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFFFE3E3),
    onPrimaryContainer: const Color(0xFF7F0000),
    secondary: const Color(0xFFB71C1C),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFFFE3E3),
    onSecondaryContainer: const Color(0xFF7F0000),
    surface: Colors.white,
    onSurface: const Color(0xFF2B1B1B),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFFFF6F6),
    surfaceContainer: const Color(0xFFFFF0F0),
    surfaceContainerHigh: Colors.white,
    surfaceContainerHighest: const Color(0xFFFCE8E8),
    outline: const Color(0xFF8D6E6E),
    outlineVariant: const Color(0xFFF0CFCF),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFFBF8F8),
    appBarTheme: const AppBarTheme(
      backgroundColor: kRed,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kRed,
      foregroundColor: Colors.white,
      elevation: 3,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFF3E6E6), width: 1),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
        color: Color(0xFF2B1B1B),
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
      dragHandleColor: Color(0xFFE0C4C4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFFF9F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFF0CFCF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFF0CFCF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kRed, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1.8),
      ),
      hintStyle: const TextStyle(color: Color(0xFFB09898), fontSize: 14),
      labelStyle: const TextStyle(color: Color(0xFF8D6E6E)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kRed,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kRed,
        side: const BorderSide(color: Color(0xFFF0CFCF)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kRed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: Color(0xFFF0CFCF), width: 1),
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFF5E6E6),
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: const Color(0xFF2B1B1B),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await Db.db; // buat database + data awal
  await Prefs.load();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Kasir Outlet',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const LoginPage(),
      );
}
