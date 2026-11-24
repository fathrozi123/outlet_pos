import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outlet_pos/excel_export.dart';

void main() {
  test('laporan Excel mengikuti format: 4 baris judul, header, data, Total',
      () {
    final bytes = buildExcelBytes([
      const ExcelSheet(
        name: 'Tren Produk',
        title: 'Penjualan per Produk',
        outlet: 'Semua Outlet',
        period: 'Bulan ini (November 2026)',
        columns: [
          ExcelCol('Nama Produk'),
          ExcelCol('Kemasan'),
          ExcelCol.number('Jumlah Terjual (Pcs)'),
        ],
        rows: [
          ['Makaroni Pipa', 'Normal', 365],
          ['Usus Crispy', 'Besar', 1266],
        ],
        total: ['Total', null, 1631],
      ),
      const ExcelSheet(
        name: 'Ringkasan',
        title: 'Ringkasan Penjualan',
        outlet: 'Outlet A',
        period: '01/11/2026 - 23/11/2026',
        columns: [ExcelCol('Keterangan'), ExcelCol.money('Nilai (Rp)')],
        rows: [
          ['Penjualan Kotor', 1500000],
          ['Diskon', -25000.0],
        ],
      ),
    ], 'Outlet Makaroni');

    final out = Platform.environment['EXCEL_TEST_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);

    final x = Excel.decodeBytes(bytes);
    expect(x.tables.keys, ['Tren Produk', 'Ringkasan']);
    final s = x['Tren Produk'];
    String v(int c, int r) =>
        '${s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value ?? ''}';
    expect(v(0, 0), 'Outlet Makaroni');
    expect(v(0, 1), 'Semua Outlet');
    expect(v(0, 2), 'Penjualan per Produk');
    expect(v(0, 3), 'Bulan ini (November 2026)');
    expect(v(0, 5), 'Nama Produk');
    expect(v(2, 5), 'Jumlah Terjual (Pcs)');
    expect(v(0, 6), 'Makaroni Pipa');
    expect(v(2, 7), '1266');
    expect(v(0, 8), 'Total');
    expect(v(2, 8), '1631');
    expect(s.spannedItems, contains('A1:C1'));
  });
}
