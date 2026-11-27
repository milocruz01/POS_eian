import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db.dart';
import 'util.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String key = 'This month';
  DateSpan span = makeSpan('This month');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => expenseDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Expense'),
      ),
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
              load: () => Db.i.expenses(span.from, span.to),
              builder: (context, rows) {
                final total = rows.fold<double>(0, (s, r) => s + dbl(r['amount']));
                final cats = <String, double>{};
                for (final r in rows) {
                  cats[str(r['category'])] = (cats[str(r['category'])] ?? 0) + dbl(r['amount']);
                }
                final sorted = cats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  itemCount: rows.length + 1,
                  itemBuilder: (c, i) {
                    if (i == 0) {
                      return Card(
                        color: cs.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(span.text, style: const TextStyle(fontSize: 12)),
                              Text('Total expenses', style: Theme.of(context).textTheme.labelLarge),
                              Text(money(total), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                              if (sorted.isNotEmpty) const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: -4,
                                children: [
                                  for (final e in sorted) Chip(label: Text('${e.key}  ${money(e.value)}'), visualDensity: VisualDensity.compact),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final r = rows[i - 1];
                    return Dismissible(
                      key: ValueKey('exp${r['id']}'),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => confirm(context, 'Delete expense?', '${r['category']} – ${money(dbl(r['amount']))}'),
                      onDismissed: (_) => Db.i.deleteExpense(intv(r['id'])),
                      background: Container(
                        color: cs.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: Icon(Icons.delete, color: cs.error),
                      ),
                      child: ListTile(
                        onTap: () => expenseDialog(context, r),
                        leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                        title: Text(str(r['category'])),
                        subtitle: Text('${fmtDate(intv(r['ts']))}${str(r['note']).isEmpty ? '' : '\n${r['note']}'}'),
                        isThreeLine: str(r['note']).isNotEmpty,
                        trailing: Text(money(dbl(r['amount'])), style: const TextStyle(fontWeight: FontWeight.bold)),
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

Future<void> expenseDialog(BuildContext context, [Rec? e]) async {
  final cats = Db.i.cfgList('categories');
  String cat = e == null ? (cats.isEmpty ? 'Other' : cats.first) : str(e['category']);
  if (!cats.contains(cat)) cats.add(cat);
  DateTime when = e == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(intv(e['ts']));
  final amount = TextEditingController(text: e == null ? '' : fmtPlain(dbl(e['amount'])));
  final note = TextEditingController(text: e == null ? '' : str(e['note']));
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(e == null ? 'Add expense' : 'Edit expense'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                children: [
                  for (final k in cats)
                    ChoiceChip(label: Text(k), selected: k == cat, onSelected: (_) => set(() => cat = k)),
                ],
              ),
              const SizedBox(height: 12),
              tf('Amount', amount, number: true, autofocus: e == null),
              const SizedBox(height: 10),
              tf('Note (optional)', note),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: c,
                    initialDate: when,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) set(() => when = DateTime(d.year, d.month, d.day, when.hour, when.minute));
                },
                icon: const Icon(Icons.event),
                label: Text(DateFormat('EEE, MMM d, y').format(when)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final a = parseNum(amount.text);
  if (a <= 0) return;
  await Db.i.saveExpense(
    id: e == null ? null : intv(e['id']),
    ts: when.millisecondsSinceEpoch,
    category: cat,
    amount: a,
    note: note.text.trim(),
  );
}
