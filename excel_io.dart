import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'db.dart';
import 'util.dart';

class XlsxIo {
  static final _dt = DateFormat('yyyy-MM-dd HH:mm');
  static String _when(Object? ms) =>
      _dt.format(DateTime.fromMillisecondsSinceEpoch(intv(ms)));

  static CellValue _t(Object? v) => TextCellValue(v == null ? '' : v.toString());
  static CellValue _n(num v) => DoubleCellValue(v.toDouble());

  static void _head(Sheet s, List<String> h) =>
      s.appendRow(h.map<CellValue>((e) => TextCellValue(e)).toList());

  static Future<void> _share(Excel x, String name) async {
    final bytes = x.encode();
    if (bytes == null) throw Exception('Could not build the Excel file');
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [
        XFile(f.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      ],
      subject: name,
    );
  }

  // ------------------------------------------------------------ export all
  static Future<void> exportAll() async {
    final db = Db.i.d;
    final x = Excel.createExcel();

    final m = x['Materials'];
    _head(m, ['Name', 'Unit', 'Cost per unit', 'Stock', 'Low stock alert']);
    for (final r in await db.query('materials', orderBy: 'name COLLATE NOCASE')) {
      m.appendRow([_t(r['name']), _t(r['unit']), _n(dbl(r['cost'])), _n(dbl(r['stock'])), _n(dbl(r['low']))]);
    }

    final s = x['Packages'];
    _head(s, ['Name', 'Price', 'Machine', 'Active', 'Material cost (info)']);
    for (final r in await Db.i.servicesWithCost()) {
      s.appendRow([_t(r['name']), _n(dbl(r['price'])), _t(r['machine']), _t(intv(r['active']) == 1 ? 'Yes' : 'No'), _n(dbl(r['cost']))]);
    }

    final rc = x['Recipes'];
    _head(rc, ['Package', 'Material', 'Qty per wash']);
    for (final r in await db.rawQuery('''
      SELECT s.name sname, m.name mname, r.qty FROM recipe r
      JOIN services s ON s.id=r.service_id JOIN materials m ON m.id=r.material_id
      ORDER BY s.name COLLATE NOCASE, m.name COLLATE NOCASE''')) {
      rc.appendRow([_t(r['sname']), _t(r['mname']), _n(dbl(r['qty']))]);
    }

    final c = x['Customers'];
    _head(c, ['Name', 'Plate', 'Phone', 'Notes']);
    for (final r in await db.query('customers', orderBy: 'name COLLATE NOCASE')) {
      c.appendRow([_t(r['name']), _t(r['plate']), _t(r['phone']), _t(r['notes'])]);
    }

    final e = x['Expenses'];
    _head(e, ['Date', 'Category', 'Amount', 'Note']);
    for (final r in await db.query('expenses', orderBy: 'ts')) {
      e.appendRow([_t(_when(r['ts'])), _t(r['category']), _n(dbl(r['amount'])), _t(r['note'])]);
    }

    _salesSheet(x, await db.query('sales', orderBy: 'ts'), await db.query('sale_items'));

    x.delete('Sheet1');
    await _share(x, 'carwash_data_${stamp()}.xlsx');
  }

  static void _salesSheet(Excel x, List<Rec> sales, List<Rec> items) {
    final byId = <int, List<String>>{};
    for (final i in items) {
      byId.putIfAbsent(intv(i['sale_id']), () => []).add('${i['qty']}x ${i['name']}');
    }
    final sh = x['Sales'];
    _head(sh, ['ID', 'Date', 'Machine', 'Plate', 'Customer', 'Payment', 'Items', 'Discount', 'Total', 'Material cost', 'Profit', 'Status']);
    for (final r in sales) {
      final total = dbl(r['total']), cost = dbl(r['cost']);
      sh.appendRow([
        _n(intv(r['id'])),
        _t(_when(r['ts'])),
        _t(r['machine']),
        _t(r['plate']),
        _t(r['customer']),
        _t(r['payment']),
        _t((byId[intv(r['id'])] ?? []).join(', ')),
        _n(dbl(r['discount'])),
        _n(total),
        _n(cost),
        _n(total - cost),
        _t(intv(r['void']) == 1 ? 'VOID' : 'OK'),
      ]);
    }
  }

  // ------------------------------------------------------------ export report
  static Future<void> exportReport(DateSpan span, Report r) async {
    final db = Db.i.d;
    final a = span.from.millisecondsSinceEpoch, b = span.to.millisecondsSinceEpoch;
    final x = Excel.createExcel();

    final sm = x['Summary'];
    _head(sm, ['Metric', 'Value']);
    sm.appendRow([_t('Period'), _t(span.text)]);
    sm.appendRow([_t('Cars washed'), _n(r.cars)]);
    sm.appendRow([_t('Sales'), _n(r.sales)]);
    sm.appendRow([_t('Material cost'), _n(r.cogs)]);
    sm.appendRow([_t('Gross profit'), _n(r.gross)]);
    sm.appendRow([_t('Expenses (excl. restock)'), _n(r.expenses)]);
    sm.appendRow([_t('Net profit'), _n(r.net)]);
    sm.appendRow([_t('Restock purchases (info)'), _n(r.restock)]);
    sm.appendRow([_t('Discounts given'), _n(r.discount)]);

    final pk = x['By package'];
    _head(pk, ['Package', 'Qty', 'Revenue']);
    for (final e in r.packages) {
      pk.appendRow([_t(e['name']), _n(dbl(e['q'])), _n(dbl(e['rev']))]);
    }

    final us = x['Materials used'];
    _head(us, ['Material', 'Unit', 'Qty used', 'Cost']);
    for (final e in r.usage) {
      us.appendRow([_t(e['name']), _t(e['unit']), _n(dbl(e['q'])), _n(dbl(e['cost']))]);
    }

    final ex = x['Expenses'];
    _head(ex, ['Date', 'Category', 'Amount', 'Note']);
    for (final e in await db.query('expenses', where: 'ts>=? AND ts<?', whereArgs: [a, b], orderBy: 'ts')) {
      ex.appendRow([_t(_when(e['ts'])), _t(e['category']), _n(dbl(e['amount'])), _t(e['note'])]);
    }

    final sales = await db.query('sales', where: 'ts>=? AND ts<?', whereArgs: [a, b], orderBy: 'ts');
    final ids = sales.map((e) => intv(e['id'])).toList();
    final items = ids.isEmpty
        ? <Rec>[]
        : await db.query('sale_items', where: 'sale_id IN (${ids.map((_) => '?').join(',')})', whereArgs: ids);
    _salesSheet(x, sales, items);

    x.delete('Sheet1');
    await _share(x, 'carwash_report_${stamp()}.xlsx');
  }

  // ------------------------------------------------------------ import
  static List<List<String>> _rows(Excel x, String name) {
    String? key;
    for (final k in x.tables.keys) {
      if (k.toLowerCase() == name.toLowerCase()) key = k;
    }
    if (key == null) return [];
    final t = x.tables[key]!;
    final out = <List<String>>[];
    for (var i = 1; i < t.rows.length; i++) {
      out.add(t.rows[i].map((c) => c?.value?.toString().trim() ?? '').toList());
    }
    return out.where((r) => r.any((c) => c.isNotEmpty)).toList();
  }

  static String _g(List<String> r, int i) => i < r.length ? r[i] : '';

  /// Returns a summary message, or null if the user cancelled.
  static Future<String?> importFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final file = res.files.single;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    final x = Excel.decodeBytes(bytes);
    final db = Db.i.d;

    int mAdd = 0, mUpd = 0, sAdd = 0, sUpd = 0, rAdd = 0, rSkip = 0, cAdd = 0, eAdd = 0;

    await db.transaction((t) async {
      for (final r in _rows(x, 'Materials')) {
        final name = _g(r, 0);
        if (name.isEmpty) continue;
        final vals = <String, Object?>{
          'name': name,
          'unit': _g(r, 1).isEmpty ? 'unit' : _g(r, 1),
          'cost': parseNum(_g(r, 2)),
          'stock': parseNum(_g(r, 3)),
          'low': parseNum(_g(r, 4)),
        };
        final ex = await t.rawQuery('SELECT id FROM materials WHERE name = ? COLLATE NOCASE', [name]);
        if (ex.isEmpty) {
          await t.insert('materials', vals);
          mAdd++;
        } else {
          await t.update('materials', vals, where: 'id=?', whereArgs: [ex.first['id']]);
          mUpd++;
        }
      }

      for (final r in _rows(x, 'Packages')) {
        final name = _g(r, 0);
        if (name.isEmpty) continue;
        final active = _g(r, 3).toLowerCase();
        final vals = <String, Object?>{
          'name': name,
          'price': parseNum(_g(r, 1)),
          'machine': _g(r, 2).isEmpty ? 'Any' : _g(r, 2),
          'active': (active == 'no' || active == '0' || active == 'false') ? 0 : 1,
        };
        final ex = await t.rawQuery('SELECT id FROM services WHERE name = ? COLLATE NOCASE', [name]);
        if (ex.isEmpty) {
          await t.insert('services', vals);
          sAdd++;
        } else {
          await t.update('services', vals, where: 'id=?', whereArgs: [ex.first['id']]);
          sUpd++;
        }
      }

      for (final r in _rows(x, 'Recipes')) {
        final sv = await t.rawQuery('SELECT id FROM services WHERE name = ? COLLATE NOCASE', [_g(r, 0)]);
        final mt = await t.rawQuery('SELECT id FROM materials WHERE name = ? COLLATE NOCASE', [_g(r, 1)]);
        if (sv.isEmpty || mt.isEmpty) {
          rSkip++;
          continue;
        }
        await t.insert(
          'recipe',
          {'service_id': sv.first['id'], 'material_id': mt.first['id'], 'qty': parseNum(_g(r, 2))},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        rAdd++;
      }

      for (final r in _rows(x, 'Customers')) {
        final name = _g(r, 0);
        if (name.isEmpty) continue;
        final plate = _g(r, 1).toUpperCase();
        final ex = await t.query('customers', where: 'name=? AND plate=?', whereArgs: [name, plate]);
        if (ex.isEmpty) {
          await t.insert('customers', {'name': name, 'plate': plate, 'phone': _g(r, 2), 'notes': _g(r, 3)});
          cAdd++;
        }
      }

      for (final r in _rows(x, 'Expenses')) {
        final amount = parseNum(_g(r, 2));
        if (amount <= 0) continue;
        final ts = (DateTime.tryParse(_g(r, 0)) ?? DateTime.now()).millisecondsSinceEpoch;
        final cat = _g(r, 1).isEmpty ? 'Other' : _g(r, 1);
        final ex = await t.query('expenses',
            where: 'ts=? AND category=? AND amount=? AND note=?',
            whereArgs: [ts, cat, amount, _g(r, 3)]);
        if (ex.isEmpty) {
          await t.insert('expenses', {'ts': ts, 'category': cat, 'amount': amount, 'note': _g(r, 3)});
          eAdd++;
        }
      }
    });
    Db.i.bump();

    return 'Materials: $mAdd added, $mUpd updated\n'
        'Packages: $sAdd added, $sUpd updated\n'
        'Recipe lines: $rAdd set${rSkip > 0 ? ', $rSkip skipped (package or material not found)' : ''}\n'
        'Customers: $cAdd added\n'
        'Expenses: $eAdd added (duplicates skipped)\n\n'
        'Sales are export-only and are not imported.';
  }
}
