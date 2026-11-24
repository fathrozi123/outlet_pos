import 'dart:io';
import 'dart:math' as math;

import 'package:excel/excel.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'db.dart';

/// Jenis isi kolom: menentukan perataan dan format angka di Excel.
enum ExcelKind { text, number, money }

/// Satu kolom tabel laporan.
class ExcelCol {
  final String label;
  final ExcelKind kind;

  /// Lebar kolom (satuan karakter Excel). Kosong = dihitung otomatis.
  final double? width;
  const ExcelCol(this.label, {this.kind = ExcelKind.text, this.width});
  const ExcelCol.number(this.label, {this.width}) : kind = ExcelKind.number;
  const ExcelCol.money(this.label, {this.width}) : kind = ExcelKind.money;
}

/// Satu sheet laporan dengan tata letak seragam (mengikuti contoh laporan
/// "Penjualan per Produk"):
///
///   baris 1  nama usaha        (digabung, tengah, tebal)
///   baris 2  outlet            (digabung, tengah, tebal)
///   baris 3  judul laporan     (digabung, tengah, tebal, lebih tinggi)
///   baris 4  periode           (digabung, tengah, tebal)
///   baris 5  kosong
///   baris 6  header kolom      (tebal, latar warna, bergaris)
///   baris 7+ data              (bergaris, angka rata kanan "#,##0")
///   akhir    baris Total       (tebal) — bila [total] diisi
class ExcelSheet {
  /// Nama tab sheet (maks. 31 karakter).
  final String name;
  final String title;
  final String outlet;
  final String period;
  final List<ExcelCol> columns;
  final List<List<Object?>> rows;

  /// Nilai baris Total, sejajar dengan [columns]. Sel pertama biasanya 'Total'.
  final List<Object?>? total;
  const ExcelSheet({
    required this.name,
    required this.title,
    required this.outlet,
    required this.period,
    required this.columns,
    required this.rows,
    this.total,
  });
}

/// Label outlet seragam untuk semua laporan ('' = semua outlet).
String excelOutlet(String outlet) =>
    outlet.trim().isEmpty ? 'Semua Outlet' : outlet.trim();

final _kBrand = ExcelColor.fromHexString('#FF97291F');
final _kHeadFg = ExcelColor.fromHexString('#FFFFFFFF');
final _kTotalBg = ExcelColor.fromHexString('#FFF6E3E1');
final _kZebra = ExcelColor.fromHexString('#FFFAFAFA');
final _kLine = ExcelColor.fromHexString('#FFBFBFBF');

Border get _thin => Border(borderStyle: BorderStyle.Thin, borderColorHex: _kLine);

CellStyle _style({
  bool bold = false,
  int fontSize = 11,
  ExcelColor? fg,
  ExcelColor? bg,
  HorizontalAlign h = HorizontalAlign.Left,
  bool border = false,
  bool money = false,
}) =>
    CellStyle(
      bold: bold,
      fontSize: fontSize,
      fontFamily: 'Calibri',
      fontColorHex: fg ?? ExcelColor.black,
      backgroundColorHex: bg ?? ExcelColor.none,
      horizontalAlign: h,
      verticalAlign: VerticalAlign.Center,
      leftBorder: border ? _thin : null,
      rightBorder: border ? _thin : null,
      topBorder: border ? _thin : null,
      bottomBorder: border ? _thin : null,
      numberFormat: money ? NumFormat.standard_3 : NumFormat.standard_0,
    );

CellValue _value(Object? v) => switch (v) {
      null => TextCellValue(''),
      int n => IntCellValue(n),
      num n when n == n.roundToDouble() && n.abs() < 9e15 =>
        IntCellValue(n.toInt()),
      num n => DoubleCellValue(n.toDouble()),
      bool b => TextCellValue(b ? 'Ya' : 'Tidak'),
      _ => TextCellValue(v.toString()),
    };

String _shown(Object? v) {
  if (v == null) return '';
  if (v is num) {
    // perkiraan panjang setelah diberi pemisah ribuan
    final s = v.round().abs().toString();
    return '${v < 0 ? '-' : ''}$s${'.' * ((s.length - 1) ~/ 3)}';
  }
  return v.toString();
}

void _writeSheet(Sheet sheet, ExcelSheet s, String brand) {
  final cols = math.max(1, s.columns.length);
  final last = cols - 1;

  // ---- Judul (4 baris digabung) ----
  final heads = [brand, s.outlet, s.title, s.period];
  for (var r = 0; r < heads.length; r++) {
    final big = r == 2;
    final st = _style(
        bold: true, fontSize: big ? 14 : 12, h: HorizontalAlign.Center);
    final a = CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r);
    final b = CellIndex.indexByColumnRow(columnIndex: last, rowIndex: r);
    sheet.cell(a)
      ..value = TextCellValue(heads[r])
      ..cellStyle = st;
    if (last > 0) {
      sheet.merge(a, b);
      // gaya juga diberikan ke sel lain agar gabungan tetap rata tengah
      for (var c = 1; c <= last; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
            .cellStyle = st;
      }
    }
    sheet.setRowHeight(r, big ? 30 : 20);
  }

  // ---- Header kolom ----
  const headRow = 5;
  final headSt = _style(
      bold: true,
      fontSize: 12,
      fg: _kHeadFg,
      bg: _kBrand,
      h: HorizontalAlign.Center,
      border: true);
  for (var c = 0; c < s.columns.length; c++) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headRow))
      ..value = TextCellValue(s.columns[c].label)
      ..cellStyle = headSt;
  }
  sheet.setRowHeight(headRow, 22);

  // ---- Data ----
  CellStyle dataSt(ExcelCol col, {required bool zebra, bool total = false}) {
    final isNum = col.kind != ExcelKind.text;
    return _style(
      bold: total,
      fontSize: total ? 12 : 11,
      bg: total ? _kTotalBg : (zebra ? _kZebra : null),
      h: isNum ? HorizontalAlign.Right : HorizontalAlign.Left,
      border: true,
      money: isNum,
    );
  }

  final plain = [for (final c in s.columns) dataSt(c, zebra: false)];
  final zebra = [for (final c in s.columns) dataSt(c, zebra: true)];
  var r = headRow + 1;
  for (var i = 0; i < s.rows.length; i++, r++) {
    final row = s.rows[i];
    final styles = i.isOdd ? zebra : plain;
    for (var c = 0; c < s.columns.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
        ..value = _value(c < row.length ? row[c] : null)
        ..cellStyle = styles[c];
    }
  }

  // ---- Baris Total ----
  final total = s.total;
  if (total != null) {
    for (var c = 0; c < s.columns.length; c++) {
      final st = dataSt(s.columns[c], zebra: false, total: true);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
        ..value = _value(c < total.length ? total[c] : null)
        ..cellStyle = st;
    }
    sheet.setRowHeight(r, 20);
  }

  // ---- Lebar kolom ----
  for (var c = 0; c < s.columns.length; c++) {
    final col = s.columns[c];
    var w = col.width;
    if (w == null) {
      var len = col.label.length + 2; // header tebal sedikit lebih lebar
      for (final row in [...s.rows, if (total != null) total]) {
        if (c < row.length) len = math.max(len, _shown(row[c]).length);
      }
      w = (len * 1.15 + 3).clamp(10, 60).toDouble();
    }
    sheet.setColumnWidth(c, w);
  }
}

/// Menyusun workbook .xlsx (tanpa menyimpan/berbagi) — dipakai juga oleh test.
List<int> buildExcelBytes(List<ExcelSheet> sheets, String brand) {
  final workbook = Excel.createExcel();
  final def = workbook.getDefaultSheet()!;
  final used = <String>{};
  for (var i = 0; i < sheets.length; i++) {
    var name = sheets[i]
        .name
        .replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ')
        .trim();
    if (name.isEmpty) name = 'Sheet${i + 1}';
    if (name.length > 31) name = name.substring(0, 31);
    while (!used.add(name)) {
      name = '${name.length > 28 ? name.substring(0, 28) : name}_${i + 1}';
    }
    if (i == 0) workbook.rename(def, name);
    _writeSheet(workbook[name], sheets[i], brand);
  }
  workbook.setDefaultSheet(used.first);
  final bytes = workbook.encode();
  if (bytes == null) throw StateError('Berkas Excel gagal dibuat');
  return bytes;
}

/// Membuat berkas Excel asli (.xlsx) yang rapi lalu membuka menu berbagi.
Future<void> shareExcel({
  BuildContext? context,
  required String title,
  required String fileName,
  required List<ExcelSheet> sheets,
}) async {
  if (sheets.isEmpty) return;
  final brand = ((await Db.getSetting('outlet_name')) ?? '').trim();
  final bytes =
      buildExcelBytes(sheets, brand.isEmpty ? 'Outlet Makaroni' : brand);
  final dir = await getTemporaryDirectory();
  final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
  final file = File('${dir.path}${Platform.pathSeparator}$safe.xlsx');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [
      XFile(file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    ],
    subject: title,
    text: title,
  );
}
