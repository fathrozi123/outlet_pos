import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Membuat berkas Excel asli (.xlsx) lalu membuka menu berbagi perangkat.
Future<void> shareExcel({
  BuildContext? context,
  required String title,
  required String fileName,
  required Map<String, List<List<Object?>>> sheets,
}) async {
  final workbook = Excel.createExcel();
  final names = sheets.keys.toList();
  if (names.isEmpty) return;
  workbook.rename(workbook.getDefaultSheet()!, names.first);

  for (final name in names) {
    final sheet = workbook[name];
    final rows = sheets[name]!;
    for (var r = 0; r < rows.length; r++) {
      final values = rows[r]
          .map<CellValue>((value) => switch (value) {
                null => TextCellValue(''),
                int n => IntCellValue(n),
                num n => DoubleCellValue(n.toDouble()),
                bool b => BoolCellValue(b),
                _ => TextCellValue(value.toString()),
              })
          .toList();
      sheet.appendRow(values);
      if (r == 0) {
        for (var c = 0; c < values.length; c++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
              .cellStyle = CellStyle(bold: true);
        }
      }
    }
  }

  final bytes = workbook.encode();
  if (bytes == null) throw StateError('Berkas Excel gagal dibuat');
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$fileName.xlsx');
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
