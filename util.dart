import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db.dart';

String money(num v) {
  final f = NumberFormat('#,##0.00');
  return '${v < 0 ? '-' : ''}${Db.i.cfg('currency')}${f.format(v.abs())}';
}

String moneyUnit(num v) =>
    '${Db.i.cfg('currency')}${NumberFormat('#,##0.00###').format(v)}';

String fmtQty(num v) {
  final d = v.toDouble();
  if (d == d.roundToDouble()) return NumberFormat('#,##0').format(d);
  return NumberFormat('#,##0.##').format(d);
}

String fmtPlain(double v) {
  if (v == 0) return '';
  var s = v.toStringAsFixed(6);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s;
}

String fmtDateTime(int ms) =>
    DateFormat('MMM d, y  h:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));
String fmtDate(int ms) =>
    DateFormat('EEE, MMM d, y').format(DateTime.fromMillisecondsSinceEpoch(ms));
String stamp() => DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

double parseNum(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

void snack(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
}

Widget tf(
  String label,
  TextEditingController c, {
  bool number = false,
  String? suffix,
  int lines = 1,
  bool autofocus = false,
  bool obscure = false,
  ValueChanged<String>? onChanged,
  TextCapitalization cap = TextCapitalization.sentences,
}) {
  return TextField(
    controller: c,
    autofocus: autofocus,
    obscureText: obscure,
    maxLines: lines,
    onChanged: onChanged,
    textCapitalization: cap,
    keyboardType:
        number ? const TextInputType.numberWithOptions(decimal: true) : null,
    decoration: InputDecoration(
      labelText: label,
      suffixText: suffix,
      isDense: true,
      border: const OutlineInputBorder(),
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body,
    {String yes = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
      ],
    ),
  );
  return r == true;
}

// ---------------- date ranges ----------------
class DateSpan {
  DateSpan(this.label, this.from, this.to);
  final String label;
  final DateTime from;
  final DateTime to; // exclusive
  String get text {
    final f = DateFormat('MMM d, y');
    final last = to.subtract(const Duration(days: 1));
    if (label == 'All') return 'All time';
    return from.year == last.year &&
            from.month == last.month &&
            from.day == last.day
        ? f.format(from)
        : '${f.format(from)} – ${f.format(last)}';
  }
}

DateSpan makeSpan(String key, [DateTimeRange? custom]) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  switch (key) {
    case 'Today':
      return DateSpan(key, today, tomorrow);
    case 'Yesterday':
      return DateSpan(key, DateTime(now.year, now.month, now.day - 1), today);
    case '7 days':
      return DateSpan(key, DateTime(now.year, now.month, now.day - 6), tomorrow);
    case 'This month':
      return DateSpan(key, DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 1));
    case 'Last month':
      return DateSpan(key, DateTime(now.year, now.month - 1, 1),
          DateTime(now.year, now.month, 1));
    case 'Custom':
      if (custom != null) {
        return DateSpan(
            key,
            DateTime(custom.start.year, custom.start.month, custom.start.day),
            DateTime(custom.end.year, custom.end.month, custom.end.day + 1));
      }
      return DateSpan('Today', today, tomorrow);
    default:
      return DateSpan('All', DateTime(2000), DateTime(2100));
  }
}

class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.current, required this.onChange});
  final String current;
  final void Function(String key, DateTimeRange? custom) onChange;

  static const keys = [
    'Today', 'Yesterday', '7 days', 'This month', 'Last month', 'All', 'Custom'
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final k in keys)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(k),
                selected: current == k,
                onSelected: (_) async {
                  if (k == 'Custom') {
                    final r = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (r != null) onChange(k, r);
                  } else {
                    onChange(k, null);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------- reload on data changes ----------------
class Reload<T> extends StatelessWidget {
  const Reload({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Db.i.tick,
      builder: (context, _, __) => FutureBuilder<T>(
        future: load(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return builder(context, snap.data as T);
        },
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: c),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: c)),
          ],
        ),
      ),
    );
  }
}

// ---------------- optional PIN lock ----------------
class Pin {
  static bool unlocked = false;

  static Future<bool> ensure(BuildContext context) async {
    final pin = Db.i.cfg('pin');
    if (pin.isEmpty || unlocked) return true;
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enter PIN'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN'),
          onSubmitted: (_) => Navigator.pop(c, ctl.text == pin),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text == pin), child: const Text('Unlock')),
        ],
      ),
    );
    if (ok == true) {
      unlocked = true;
      return true;
    }
    if (ok == false && context.mounted) snack(context, 'Wrong PIN');
    return false;
  }
}

// ---------------- receipt text ----------------
Future<String> buildReceipt(int saleId) async {
  final dt = await Db.i.saleDetail(saleId);
  final s = dt.sale;
  final b = StringBuffer();
  b.writeln(Db.i.cfg('business'));
  b.writeln(fmtDateTime(intv(s['ts'])));
  b.writeln('Receipt #$saleId');
  final machine = str(s['machine']);
  final plate = str(s['plate']);
  final cust = str(s['customer']);
  if (machine.isNotEmpty) b.writeln('Machine: $machine');
  if (plate.isNotEmpty) b.writeln('Plate: $plate');
  if (cust.isNotEmpty) b.writeln('Customer: $cust');
  b.writeln('--------------------------');
  for (final i in dt.items) {
    b.writeln('${i['qty']} x ${i['name']}  ${money(dbl(i['price']) * intv(i['qty']))}');
  }
  b.writeln('--------------------------');
  if (dbl(s['discount']) > 0) b.writeln('Discount: -${money(dbl(s['discount']))}');
  b.writeln('TOTAL: ${money(dbl(s['total']))}');
  b.writeln('Paid by: ${s['payment']}');
  if (Db.i.cfg('footer').isNotEmpty) {
    b.writeln();
    b.writeln(Db.i.cfg('footer'));
  }
  return b.toString();
}
