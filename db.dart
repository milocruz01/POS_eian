import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

double dbl(Object? v) => (v as num?)?.toDouble() ?? 0;
int intv(Object? v) => (v as num?)?.toInt() ?? 0;
String str(Object? v) => v?.toString() ?? '';

typedef Rec = Map<String, Object?>;

const kRestock = 'Materials restock';

class CartLine {
  CartLine(this.serviceId, this.name, this.price, this.unitCost, this.qty);
  final int serviceId;
  final String name;
  final double price;
  final double unitCost;
  int qty;
}

class SaleDetail {
  SaleDetail(this.sale, this.items, this.usage);
  final Rec sale;
  final List<Rec> items;
  final List<Rec> usage;
}

class Report {
  int cars = 0;
  double sales = 0, cogs = 0, discount = 0, expenses = 0, restock = 0;
  List<Rec> packages = [], machines = [], payments = [], usage = [];
  List<Rec> daily = [], hourly = [], expenseCats = [], lowStock = [];
  double get gross => sales - cogs;
  double get net => gross - expenses;
}

class Db {
  Db._();
  static final Db i = Db._();

  late Database d;
  final ValueNotifier<int> tick = ValueNotifier<int>(0);
  final Map<String, String> _settings = {};

  static const defaults = <String, String>{
    'business': 'My Car Wash',
    'currency': '₱',
    'machines': 'TS-5,TS-7',
    'payments': 'Cash,GCash,Maya,Card',
    'categories':
        'Water,Electricity,Rent,Salaries,Materials restock,Maintenance,Spare parts,Internet,Permits & taxes,Marketing,Other',
    'footer': 'Thank you! Please come again.',
    'pin': '',
  };

  void bump() => tick.value++;

  String cfg(String k) => _settings[k] ?? defaults[k] ?? '';
  List<String> cfgList(String k) => cfg(k)
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> setCfg(String k, String v) async {
    await d.insert('settings', {'k': k, 'v': v},
        conflictAlgorithm: ConflictAlgorithm.replace);
    _settings[k] = v;
    bump();
  }

  Future<void> init() async {
    final path = p.join(await getDatabasesPath(), 'carwash_pos.db');
    d = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, v) async {
        await db.execute('''CREATE TABLE materials(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          unit TEXT NOT NULL DEFAULT 'ml',
          cost REAL NOT NULL DEFAULT 0,
          stock REAL NOT NULL DEFAULT 0,
          low REAL NOT NULL DEFAULT 0)''');
        await db.execute('''CREATE TABLE services(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          price REAL NOT NULL DEFAULT 0,
          machine TEXT NOT NULL DEFAULT 'Any',
          active INTEGER NOT NULL DEFAULT 1)''');
        await db.execute('''CREATE TABLE recipe(
          service_id INTEGER NOT NULL,
          material_id INTEGER NOT NULL,
          qty REAL NOT NULL DEFAULT 0,
          PRIMARY KEY(service_id, material_id),
          FOREIGN KEY(service_id) REFERENCES services(id) ON DELETE CASCADE,
          FOREIGN KEY(material_id) REFERENCES materials(id) ON DELETE CASCADE)''');
        await db.execute('''CREATE TABLE customers(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          plate TEXT NOT NULL DEFAULT '',
          phone TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '')''');
        await db.execute('''CREATE TABLE sales(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts INTEGER NOT NULL,
          machine TEXT NOT NULL DEFAULT '',
          plate TEXT NOT NULL DEFAULT '',
          customer TEXT NOT NULL DEFAULT '',
          payment TEXT NOT NULL DEFAULT 'Cash',
          discount REAL NOT NULL DEFAULT 0,
          total REAL NOT NULL DEFAULT 0,
          cost REAL NOT NULL DEFAULT 0,
          note TEXT NOT NULL DEFAULT '',
          void INTEGER NOT NULL DEFAULT 0)''');
        await db.execute('''CREATE TABLE sale_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          service_id INTEGER,
          name TEXT NOT NULL,
          price REAL NOT NULL,
          qty INTEGER NOT NULL,
          cost REAL NOT NULL DEFAULT 0,
          FOREIGN KEY(sale_id) REFERENCES sales(id) ON DELETE CASCADE)''');
        await db.execute('''CREATE TABLE sale_usage(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          material_id INTEGER,
          name TEXT NOT NULL,
          unit TEXT NOT NULL,
          qty REAL NOT NULL,
          cost REAL NOT NULL,
          FOREIGN KEY(sale_id) REFERENCES sales(id) ON DELETE CASCADE)''');
        await db.execute('''CREATE TABLE expenses(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts INTEGER NOT NULL,
          category TEXT NOT NULL,
          amount REAL NOT NULL,
          note TEXT NOT NULL DEFAULT '')''');
        await db.execute(
            'CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT NOT NULL)');
        await db.execute('CREATE INDEX idx_sales_ts ON sales(ts)');
        await db.execute('CREATE INDEX idx_expenses_ts ON expenses(ts)');
      },
    );
    for (final r in await d.query('settings')) {
      _settings[str(r['k'])] = str(r['v']);
    }
  }

  // ---------------- Materials ----------------
  Future<List<Rec>> materials() =>
      d.query('materials', orderBy: 'name COLLATE NOCASE');

  Future<List<Rec>> lowStock() => d.rawQuery(
      'SELECT * FROM materials WHERE low > 0 AND stock <= low ORDER BY name COLLATE NOCASE');

  Future<int> saveMaterial({
    int? id,
    required String name,
    required String unit,
    required double cost,
    required double stock,
    required double low,
  }) async {
    final v = <String, Object?>{
      'name': name,
      'unit': unit,
      'cost': cost,
      'stock': stock,
      'low': low,
    };
    int rid;
    if (id == null) {
      rid = await d.insert('materials', v);
    } else {
      await d.update('materials', v, where: 'id=?', whereArgs: [id]);
      rid = id;
    }
    bump();
    return rid;
  }

  Future<void> deleteMaterial(int id) async {
    await d.delete('materials', where: 'id=?', whereArgs: [id]);
    bump();
  }

  Future<void> restock({
    required int id,
    required double qty,
    required double paid,
    required bool record,
    required bool updateCost,
  }) async {
    await d.transaction((t) async {
      final m = (await t.query('materials', where: 'id=?', whereArgs: [id])).first;
      final vals = <String, Object?>{'stock': dbl(m['stock']) + qty};
      if (updateCost && paid > 0 && qty > 0) vals['cost'] = paid / qty;
      await t.update('materials', vals, where: 'id=?', whereArgs: [id]);
      if (record && paid > 0) {
        await t.insert('expenses', {
          'ts': DateTime.now().millisecondsSinceEpoch,
          'category': kRestock,
          'amount': paid,
          'note': 'Restock ${m['name']} (+$qty ${m['unit']})',
        });
      }
    });
    bump();
  }

  // ---------------- Packages (services) ----------------
  Future<List<Rec>> servicesWithCost() => d.rawQuery('''
    SELECT s.*, COALESCE((SELECT SUM(r.qty*m.cost) FROM recipe r
      JOIN materials m ON m.id=r.material_id WHERE r.service_id=s.id),0) AS cost
    FROM services s ORDER BY s.active DESC, s.name COLLATE NOCASE''');

  Future<List<Rec>> recipeOf(int serviceId) => d.rawQuery('''
    SELECT r.material_id, r.qty, m.name, m.unit, m.cost FROM recipe r
    JOIN materials m ON m.id=r.material_id
    WHERE r.service_id=? ORDER BY m.name COLLATE NOCASE''', [serviceId]);

  Future<int> saveService({
    int? id,
    required String name,
    required double price,
    required String machine,
    required bool active,
    required Map<int, double> recipe,
  }) async {
    int sid = 0;
    await d.transaction((t) async {
      final v = <String, Object?>{
        'name': name,
        'price': price,
        'machine': machine,
        'active': active ? 1 : 0,
      };
      if (id == null) {
        sid = await t.insert('services', v);
      } else {
        sid = id;
        await t.update('services', v, where: 'id=?', whereArgs: [id]);
      }
      await t.delete('recipe', where: 'service_id=?', whereArgs: [sid]);
      for (final e in recipe.entries) {
        if (e.value > 0) {
          await t.insert('recipe',
              {'service_id': sid, 'material_id': e.key, 'qty': e.value});
        }
      }
    });
    bump();
    return sid;
  }

  Future<void> deleteService(int id) async {
    await d.delete('services', where: 'id=?', whereArgs: [id]);
    bump();
  }

  // ---------------- Customers ----------------
  Future<List<Rec>> customers([String q = '']) => d.rawQuery('''
    SELECT c.*,
      (SELECT COUNT(*) FROM sales s WHERE s.void=0 AND c.plate<>'' AND s.plate=c.plate) AS visits,
      (SELECT COALESCE(SUM(s.total),0) FROM sales s WHERE s.void=0 AND c.plate<>'' AND s.plate=c.plate) AS spent
    FROM customers c
    WHERE c.name LIKE ? OR c.plate LIKE ? OR c.phone LIKE ?
    ORDER BY c.name COLLATE NOCASE''', ['%$q%', '%$q%', '%$q%']);

  Future<Rec?> customerByPlate(String plate) async {
    final r = await d.query('customers', where: 'plate=?', whereArgs: [plate]);
    return r.isEmpty ? null : r.first;
  }

  Future<void> saveCustomer(
      {int? id,
      required String name,
      required String plate,
      required String phone,
      required String notes}) async {
    final v = <String, Object?>{
      'name': name,
      'plate': plate,
      'phone': phone,
      'notes': notes
    };
    if (id == null) {
      await d.insert('customers', v);
    } else {
      await d.update('customers', v, where: 'id=?', whereArgs: [id]);
    }
    bump();
  }

  Future<void> deleteCustomer(int id) async {
    await d.delete('customers', where: 'id=?', whereArgs: [id]);
    bump();
  }

  // ---------------- Expenses ----------------
  Future<List<Rec>> expenses(DateTime from, DateTime to) => d.query('expenses',
      where: 'ts>=? AND ts<?',
      whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
      orderBy: 'ts DESC');

  Future<void> saveExpense(
      {int? id,
      required int ts,
      required String category,
      required double amount,
      required String note}) async {
    final v = <String, Object?>{
      'ts': ts,
      'category': category,
      'amount': amount,
      'note': note
    };
    if (id == null) {
      await d.insert('expenses', v);
    } else {
      await d.update('expenses', v, where: 'id=?', whereArgs: [id]);
    }
    bump();
  }

  Future<void> deleteExpense(int id) async {
    await d.delete('expenses', where: 'id=?', whereArgs: [id]);
    bump();
  }

  // ---------------- Sales ----------------
  Future<int> checkout({
    required List<CartLine> lines,
    required String machine,
    required String plate,
    required String customer,
    required String payment,
    required double discount,
  }) async {
    int saleId = 0;
    await d.transaction((t) async {
      double gross = 0, cost = 0;
      for (final l in lines) {
        gross += l.price * l.qty;
        cost += l.unitCost * l.qty;
      }
      final total = math.max(0.0, gross - discount);
      saleId = await t.insert('sales', {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'machine': machine,
        'plate': plate,
        'customer': customer,
        'payment': payment,
        'discount': discount,
        'total': total,
        'cost': cost,
      });
      final usage = <int, double>{};
      for (final l in lines) {
        await t.insert('sale_items', {
          'sale_id': saleId,
          'service_id': l.serviceId,
          'name': l.name,
          'price': l.price,
          'qty': l.qty,
          'cost': l.unitCost,
        });
        final rec = await t.query('recipe',
            where: 'service_id=?', whereArgs: [l.serviceId]);
        for (final r in rec) {
          final mid = intv(r['material_id']);
          usage[mid] = (usage[mid] ?? 0) + dbl(r['qty']) * l.qty;
        }
      }
      for (final e in usage.entries) {
        final m =
            await t.query('materials', where: 'id=?', whereArgs: [e.key]);
        if (m.isEmpty) continue;
        await t.insert('sale_usage', {
          'sale_id': saleId,
          'material_id': e.key,
          'name': m.first['name'],
          'unit': m.first['unit'],
          'qty': e.value,
          'cost': e.value * dbl(m.first['cost']),
        });
        await t.rawUpdate(
            'UPDATE materials SET stock = stock - ? WHERE id=?', [e.value, e.key]);
      }
      if (plate.isNotEmpty) {
        final ex =
            await t.query('customers', where: 'plate=?', whereArgs: [plate]);
        if (ex.isEmpty) {
          await t.insert('customers', {
            'name': customer.isEmpty ? plate : customer,
            'plate': plate,
          });
        } else if (customer.isNotEmpty && str(ex.first['name']) == plate) {
          await t.update('customers', {'name': customer},
              where: 'id=?', whereArgs: [ex.first['id']]);
        }
      }
    });
    bump();
    return saleId;
  }

  Future<void> voidSale(int id) async {
    await d.transaction((t) async {
      final s = await t
          .query('sales', where: 'id=? AND void=0', whereArgs: [id]);
      if (s.isEmpty) return;
      final us =
          await t.query('sale_usage', where: 'sale_id=?', whereArgs: [id]);
      for (final u in us) {
        final mid = u['material_id'];
        if (mid != null) {
          await t.rawUpdate('UPDATE materials SET stock = stock + ? WHERE id=?',
              [dbl(u['qty']), mid]);
        }
      }
      await t.update('sales', {'void': 1}, where: 'id=?', whereArgs: [id]);
    });
    bump();
  }

  Future<List<Rec>> sales(DateTime from, DateTime to) => d.query('sales',
      where: 'ts>=? AND ts<?',
      whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
      orderBy: 'ts DESC');

  Future<SaleDetail> saleDetail(int id) async {
    final s = (await d.query('sales', where: 'id=?', whereArgs: [id])).first;
    final items =
        await d.query('sale_items', where: 'sale_id=?', whereArgs: [id]);
    final usage = await d.query('sale_usage',
        where: 'sale_id=?', whereArgs: [id], orderBy: 'name COLLATE NOCASE');
    return SaleDetail(s, items, usage);
  }

  // ---------------- Reports ----------------
  Future<Report> report(DateTime from, DateTime to) async {
    final a = from.millisecondsSinceEpoch, b = to.millisecondsSinceEpoch;
    final r = Report();
    final s = (await d.rawQuery(
            'SELECT COUNT(*) c, COALESCE(SUM(total),0) t, COALESCE(SUM(cost),0) k, COALESCE(SUM(discount),0) x FROM sales WHERE void=0 AND ts>=? AND ts<?',
            [a, b]))
        .first;
    r.cars = intv(s['c']);
    r.sales = dbl(s['t']);
    r.cogs = dbl(s['k']);
    r.discount = dbl(s['x']);

    r.expenseCats = await d.rawQuery(
        'SELECT category, SUM(amount) a FROM expenses WHERE ts>=? AND ts<? GROUP BY category ORDER BY a DESC',
        [a, b]);
    for (final e in r.expenseCats) {
      if (str(e['category']) == kRestock) {
        r.restock += dbl(e['a']);
      } else {
        r.expenses += dbl(e['a']);
      }
    }

    r.packages = await d.rawQuery(
        'SELECT si.name name, SUM(si.qty) q, SUM(si.price*si.qty) rev FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.void=0 AND s.ts>=? AND s.ts<? GROUP BY si.name ORDER BY rev DESC',
        [a, b]);
    r.machines = await d.rawQuery(
        'SELECT machine name, COUNT(*) q, SUM(total) rev FROM sales WHERE void=0 AND ts>=? AND ts<? GROUP BY machine ORDER BY rev DESC',
        [a, b]);
    r.payments = await d.rawQuery(
        'SELECT payment name, COUNT(*) q, SUM(total) rev FROM sales WHERE void=0 AND ts>=? AND ts<? GROUP BY payment ORDER BY rev DESC',
        [a, b]);
    r.usage = await d.rawQuery(
        'SELECT u.name name, u.unit unit, SUM(u.qty) q, SUM(u.cost) cost FROM sale_usage u JOIN sales s ON s.id=u.sale_id WHERE s.void=0 AND s.ts>=? AND s.ts<? GROUP BY u.name, u.unit ORDER BY cost DESC',
        [a, b]);
    r.daily = await d.rawQuery(
        "SELECT strftime('%Y-%m-%d', ts/1000, 'unixepoch', 'localtime') day, COUNT(*) q, SUM(total) rev FROM sales WHERE void=0 AND ts>=? AND ts<? GROUP BY day ORDER BY day",
        [a, b]);
    r.hourly = await d.rawQuery(
        "SELECT CAST(strftime('%H', ts/1000, 'unixepoch', 'localtime') AS INTEGER) hr, COUNT(*) q FROM sales WHERE void=0 AND ts>=? AND ts<? GROUP BY hr ORDER BY hr",
        [a, b]);
    r.lowStock = await lowStock();
    return r;
  }
}
