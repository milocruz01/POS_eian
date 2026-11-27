import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'db.dart';
import 'util.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key, this.initialKey = 'Today'});
  final String initialKey;
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  late String key;
  late DateSpan span;

  @override
  void initState() {
    super.initState();
    key = widget.initialKey == 'Custom' ? 'Today' : widget.initialKey;
    span = makeSpan(key);
  }

  Future<void> _detail(int id) async {
    final dt = await Db.i.saleDetail(id);
    if (!mounted) return;
    final s = dt.sale;
    final voided = intv(s['void']) == 1;
    final total = dbl(s['total']);
    final cost = dbl(s['cost']);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Sale #$id${voided ? '  (VOID)' : ''}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(fmtDateTime(intv(s['ts']))),
              Text([
                if (str(s['machine']).isNotEmpty) str(s['machine']),
                if (str(s['plate']).isNotEmpty) str(s['plate']),
                if (str(s['customer']).isNotEmpty) str(s['customer']),
                str(s['payment']),
              ].join('  •  ')),
              const Divider(),
              for (final i in dt.items) Text('${i['qty']} × ${i['name']}   ${money(dbl(i['price']) * intv(i['qty']))}'),
              if (dbl(s['discount']) > 0) Text('Discount  -${money(dbl(s['discount']))}'),
              const SizedBox(height: 6),
              Text('Total  ${money(total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Material cost  ${money(cost)}'),
              Text('Profit  ${money(total - cost)}'),
              if (dt.usage.isNotEmpty) ...[
                const Divider(),
                const Text('Materials used', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final u in dt.usage)
                  Text('${u['name']}: ${fmtQty(dbl(u['qty']))} ${u['unit']}  (${money(dbl(u['cost']))})'),
              ],
            ],
          ),
        ),
        actions: [
          if (!voided)
            TextButton(
              onPressed: () async {
                if (await confirm(c, 'Void this sale?', 'Materials used will be returned to stock and the sale removed from reports.', yes: 'Void')) {
                  await Db.i.voidSale(id);
                  if (c.mounted) Navigator.pop(c);
                }
              },
              child: const Text('Void'),
            ),
          TextButton(
            onPressed: () async => Share.share(await buildReceipt(id)),
            child: const Text('Receipt'),
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sales history')),
      body: Column(
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
            child: Reload<List<Rec>>(
              load: () => Db.i.sales(span.from, span.to),
              builder: (context, rows) {
                if (rows.isEmpty) return const EmptyState(icon: Icons.receipt_outlined, text: 'No sales in this period');
                final good = rows.where((r) => intv(r['void']) == 0);
                final total = good.fold<double>(0, (s, r) => s + dbl(r['total']));
                return ListView.builder(
                  itemCount: rows.length + 1,
                  itemBuilder: (c, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('${good.length} cars  •  ${money(total)}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      );
                    }
                    final r = rows[i - 1];
                    final voided = intv(r['void']) == 1;
                    final time = DateFormat('MMM d  h:mm a').format(DateTime.fromMillisecondsSinceEpoch(intv(r['ts'])));
                    return ListTile(
                      onTap: () => _detail(intv(r['id'])),
                      title: Text(str(r['plate']).isEmpty ? 'No plate' : str(r['plate'])),
                      subtitle: Text('$time  •  ${str(r['machine'])}  •  ${str(r['payment'])}'),
                      trailing: Text(
                        money(dbl(r['total'])),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          decoration: voided ? TextDecoration.lineThrough : null,
                          color: voided ? cs.outline : null,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
