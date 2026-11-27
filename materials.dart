import 'package:flutter/material.dart';
import 'db.dart';
import 'util.dart';

class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({super.key});
  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen> {
  final q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => materialDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Material'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: tf('Search materials', q, onChanged: (_) => setState(() {})),
          ),
          Expanded(
            child: Reload<List<Rec>>(
              load: Db.i.materials,
              builder: (context, all) {
                final key = q.text.trim().toLowerCase();
                final rows = all.where((m) => str(m['name']).toLowerCase().contains(key)).toList();
                if (all.isEmpty) {
                  return const EmptyState(
                      icon: Icons.water_drop_outlined,
                      text: 'Add the materials you use per wash:\nfoam soap, wax, tire shine, water, electricity…\nGive each one a unit and a cost.');
                }
                final value = all.fold<double>(0, (s, m) => s + dbl(m['stock']) * dbl(m['cost']));
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                  itemCount: rows.length + 1,
                  itemBuilder: (c, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Inventory value: ${money(value)}', style: TextStyle(color: cs.outline)),
                      );
                    }
                    final m = rows[i - 1];
                    final stock = dbl(m['stock']);
                    final low = dbl(m['low']);
                    final isLow = low > 0 && stock <= low;
                    final unit = str(m['unit']);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => materialDialog(context, m),
                        leading: CircleAvatar(
                          backgroundColor: isLow ? cs.errorContainer : cs.primaryContainer,
                          child: Icon(isLow ? Icons.warning_amber : Icons.inventory_2_outlined,
                              color: isLow ? cs.error : cs.primary),
                        ),
                        title: Text(str(m['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${fmtQty(stock)} $unit in stock  •  ${moneyUnit(dbl(m['cost']))} / $unit'
                            '${isLow ? '\nLow stock!' : ''}'),
                        isThreeLine: isLow,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'restock') {
                              restockDialog(context, m);
                            } else if (v == 'edit') {
                              materialDialog(context, m);
                            } else if (v == 'delete') {
                              if (await confirm(context, 'Delete ${m['name']}?',
                                  'It will be removed from every package recipe. Past sales keep their history.')) {
                                await Db.i.deleteMaterial(intv(m['id']));
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'restock', child: Text('Restock')),
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
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

Future<void> materialDialog(BuildContext context, [Rec? m]) async {
  final name = TextEditingController(text: m == null ? '' : str(m['name']));
  final unit = TextEditingController(text: m == null ? 'ml' : str(m['unit']));
  final cost = TextEditingController(text: m == null ? '' : fmtPlain(dbl(m['cost'])));
  final stock = TextEditingController(text: m == null ? '' : fmtPlain(dbl(m['stock'])));
  final low = TextEditingController(text: m == null ? '' : fmtPlain(dbl(m['low'])));
  final packPrice = TextEditingController();
  final packSize = TextEditingController();
  const gap = SizedBox(height: 10);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(m == null ? 'New material' : 'Edit material'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tf('Name (e.g. Foam soap)', name, autofocus: m == null),
            gap,
            Row(children: [
              Expanded(child: tf('Unit (ml, g, pcs)', unit, cap: TextCapitalization.none)),
              const SizedBox(width: 8),
              Expanded(child: tf('Cost per unit', cost, number: true)),
            ]),
            gap,
            Align(
              alignment: Alignment.centerLeft,
              child: Text('…or work it out from a pack:', style: Theme.of(c).textTheme.bodySmall),
            ),
            gap,
            Row(children: [
              Expanded(child: tf('Pack price', packPrice, number: true)),
              const SizedBox(width: 8),
              Expanded(child: tf('Pack size (in unit)', packSize, number: true)),
            ]),
            gap,
            Row(children: [
              Expanded(child: tf('Stock on hand', stock, number: true)),
              const SizedBox(width: 8),
              Expanded(child: tf('Low-stock alert', low, number: true)),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true) return;
  if (name.text.trim().isEmpty) {
    if (context.mounted) snack(context, 'Enter a name');
    return;
  }
  var c = parseNum(cost.text);
  final pp = parseNum(packPrice.text), ps = parseNum(packSize.text);
  if (pp > 0 && ps > 0) c = pp / ps;
  try {
    await Db.i.saveMaterial(
      id: m == null ? null : intv(m['id']),
      name: name.text.trim(),
      unit: unit.text.trim().isEmpty ? 'unit' : unit.text.trim(),
      cost: c,
      stock: parseNum(stock.text),
      low: parseNum(low.text),
    );
  } catch (e) {
    if (context.mounted) snack(context, 'Could not save. Is that name already used?');
  }
}

Future<void> restockDialog(BuildContext context, Rec m) async {
  final qty = TextEditingController();
  final paid = TextEditingController();
  bool record = true, updateCost = true;
  final unit = str(m['unit']);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text('Restock ${m['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tf('Quantity added', qty, number: true, suffix: unit, autofocus: true),
              const SizedBox(height: 10),
              tf('Total amount paid (optional)', paid, number: true),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: record,
                onChanged: (v) => set(() => record = v ?? true),
                title: const Text('Record as an expense'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: updateCost,
                onChanged: (v) => set(() => updateCost = v ?? true),
                title: const Text('Update cost per unit from this purchase'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add stock')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final q = parseNum(qty.text);
  if (q <= 0) return;
  await Db.i.restock(
    id: intv(m['id']),
    qty: q,
    paid: parseNum(paid.text),
    record: record,
    updateCost: updateCost,
  );
}
