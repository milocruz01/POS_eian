import 'package:flutter/material.dart';
import 'db.dart';
import 'util.dart';
import 'sales.dart';
import 'excel_io.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String key = 'Today';
  DateSpan span = makeSpan('Today');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        RangeBar(
          current: key,
          onChange: (k, r) => setState(() {
            key = k;
            span = makeSpan(k, r);
          }),
        ),
        Expanded(
          child: Reload<Report>(
            load: () => Db.i.report(span.from, span.to),
            builder: _body,
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, Report r) {
    final cs = Theme.of(context).colorScheme;
    final stats = <_Stat>[
      _Stat('Cars washed', '${r.cars}', Icons.local_car_wash),
      _Stat('Sales', money(r.sales), Icons.payments),
      _Stat('Material cost', money(r.cogs), Icons.water_drop),
      _Stat('Gross profit', money(r.gross), Icons.stacked_line_chart),
      _Stat('Expenses', money(r.expenses), Icons.receipt_long),
      _Stat('Net profit', money(r.net), Icons.trending_up, highlight: true),
      _Stat('Average per car', money(r.cars == 0 ? 0 : r.sales / r.cars), Icons.calculate),
      _Stat('Discounts given', money(r.discount), Icons.percent),
    ];

    final maxRev = r.daily.fold<double>(0, (m, e) => dbl(e['rev']) > m ? dbl(e['rev']) : m);
    final daily = [
      for (final e in r.daily) MapEntry(str(e['day']).substring(8), dbl(e['rev'])),
    ];
    final hours = <MapEntry<String, double>>[];
    if (r.hourly.isNotEmpty) {
      final byHour = {for (final e in r.hourly) intv(e['hr']): dbl(e['q'])};
      final lo = byHour.keys.reduce((a, b) => a < b ? a : b);
      final hi = byHour.keys.reduce((a, b) => a > b ? a : b);
      for (var h = lo; h <= hi; h++) {
        hours.add(MapEntry('$h', byHour[h] ?? 0));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Text(span.text, style: TextStyle(color: cs.outline)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  if (!await Pin.ensure(context)) return;
                  if (!context.mounted) return;
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SalesPage(initialKey: key)));
                },
                icon: const Icon(Icons.list_alt),
                label: const Text('View sales'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await XlsxIo.exportReport(span, r);
                  } catch (e) {
                    if (context.mounted) snack(context, 'Export failed: $e');
                  }
                },
                icon: const Icon(Icons.file_download),
                label: const Text('Export Excel'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.1,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [for (final s in stats) _StatCard(s)],
        ),
        const SizedBox(height: 4),
        Text(
          'Net profit = Sales − material cost − expenses. '
          'Material restock purchases (${money(r.restock)}) are not deducted again, because materials are costed as they are used.',
          style: TextStyle(fontSize: 12, color: cs.outline),
        ),
        if (r.lowStock.isNotEmpty)
          _Section('Low stock', [
            for (final m in r.lowStock)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.warning_amber, color: cs.error),
                title: Text(str(m['name'])),
                trailing: Text('${fmtQty(dbl(m['stock']))} ${m['unit']} left'),
              ),
          ]),
        if (daily.isNotEmpty) _Section('Daily sales', [_Columns(daily, maxRev, money: true)]),
        if (hours.isNotEmpty)
          _Section('Busy hours (cars)', [
            _Columns(hours, hours.fold<double>(0, (m, e) => e.value > m ? e.value : m)),
          ]),
        if (r.packages.isNotEmpty)
          _Section('By package', [
            for (final e in r.packages)
              _BarRow(str(e['name']), '${intv(e['q'])} × • ${money(dbl(e['rev']))}', dbl(e['rev']), dbl(r.packages.first['rev'])),
          ]),
        if (r.machines.isNotEmpty)
          _Section('By machine', [
            for (final e in r.machines)
              _BarRow(str(e['name']).isEmpty ? '-' : str(e['name']), '${intv(e['q'])} cars • ${money(dbl(e['rev']))}', dbl(e['rev']), dbl(r.machines.first['rev'])),
          ]),
        if (r.payments.isNotEmpty)
          _Section('By payment method', [
            for (final e in r.payments)
              _BarRow(str(e['name']), '${intv(e['q'])} • ${money(dbl(e['rev']))}', dbl(e['rev']), dbl(r.payments.first['rev'])),
          ]),
        if (r.usage.isNotEmpty)
          _Section('Materials used', [
            for (final e in r.usage)
              _BarRow(str(e['name']), '${fmtQty(dbl(e['q']))} ${e['unit']} • ${money(dbl(e['cost']))}', dbl(e['cost']), dbl(r.usage.first['cost'])),
          ]),
        if (r.expenseCats.isNotEmpty)
          _Section('Expenses by category', [
            for (final e in r.expenseCats)
              _BarRow(
                str(e['category']) == kRestock ? '$kRestock (purchases)' : str(e['category']),
                money(dbl(e['a'])),
                dbl(e['a']),
                dbl(r.expenseCats.first['a']),
              ),
          ]),
      ],
    );
  }
}

class _Stat {
  _Stat(this.label, this.value, this.icon, {this.highlight = false});
  final String label, value;
  final IconData icon;
  final bool highlight;
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.s);
  final _Stat s;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: s.highlight ? cs.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(s.icon, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.label, style: TextStyle(fontSize: 12, color: cs.outline)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(s.value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow(this.label, this.value, this.v, this.max);
  final String label, value;
  final double v, max;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
              Text(value, style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: max > 0 ? (v / max).clamp(0.0, 1.0).toDouble() : 0,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }
}

class _Columns extends StatelessWidget {
  const _Columns(this.data, this.max, {this.money = false});
  final List<MapEntry<String, double>> data;
  final double max;
  final bool money;

  String _short(double v) {
    if (v <= 0) return '';
    if (money && v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = data.fold<double>(0, (a, e) => e.value > a ? e.value : a);
    final top = max > 0 ? max : m;
    return SizedBox(
      height: 130,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final e in data)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(_short(e.value), style: const TextStyle(fontSize: 9)),
                    const SizedBox(height: 2),
                    Container(
                      width: 24,
                      height: top > 0 ? (e.value / top * 80).clamp(2.0, 80.0).toDouble() : 2.0,
                      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(4)),
                    ),
                    const SizedBox(height: 4),
                    Text(e.key, style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
