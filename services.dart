import 'package:flutter/material.dart';
import 'db.dart';
import 'util.dart';

class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ServiceEditPage())),
        icon: const Icon(Icons.add),
        label: const Text('Package'),
      ),
      body: Reload<List<Rec>>(
        load: Db.i.servicesWithCost,
        builder: (context, rows) {
          if (rows.isEmpty) {
            return const EmptyState(
                icon: Icons.sell_outlined,
                text: 'Create your wash packages\n(e.g. Basic, Premium, Lava foam)\nand set what materials each one uses.');
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            itemCount: rows.length,
            itemBuilder: (c, i) {
              final s = rows[i];
              final price = dbl(s['price']);
              final cost = dbl(s['cost']);
              final active = intv(s['active']) == 1;
              final margin = price > 0 ? (price - cost) / price * 100 : 0;
              return Opacity(
                opacity: active ? 1 : 0.5,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ServiceEditPage(id: intv(s['id'])))),
                    title: Row(children: [
                      Flexible(child: Text(str(s['name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(str(s['machine'])),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ]),
                    subtitle: Text(
                        'Price ${money(price)}  •  Cost ${money(cost)}\nProfit ${money(price - cost)} (${margin.toStringAsFixed(0)}%)'
                        '${active ? '' : '  •  Hidden'}',
                        style: TextStyle(color: cs.outline)),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ServiceEditPage extends StatefulWidget {
  const ServiceEditPage({super.key, this.id, this.copy = false});
  final int? id;
  final bool copy;
  @override
  State<ServiceEditPage> createState() => _ServiceEditPageState();
}

class _ServiceEditPageState extends State<ServiceEditPage> {
  final name = TextEditingController();
  final price = TextEditingController();
  String machine = 'Any';
  bool active = true;
  final Map<int, TextEditingController> qty = {};
  List<Rec> mats = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    for (final c in qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    mats = await Db.i.materials();
    final id = widget.id;
    if (id != null) {
      final s = (await Db.i.d.query('services', where: 'id=?', whereArgs: [id])).first;
      name.text = str(s['name']) + (widget.copy ? ' (copy)' : '');
      price.text = fmtPlain(dbl(s['price']));
      machine = str(s['machine']);
      active = intv(s['active']) == 1;
      for (final r in await Db.i.recipeOf(id)) {
        qty[intv(r['material_id'])] = TextEditingController(text: fmtPlain(dbl(r['qty'])));
      }
    }
    if (!mounted) return;
    setState(() => loading = false);
  }

  double get cost {
    double t = 0;
    for (final e in qty.entries) {
      final m = mats.firstWhere((x) => intv(x['id']) == e.key, orElse: () => <String, Object?>{});
      t += parseNum(e.value.text) * dbl(m['cost']);
    }
    return t;
  }

  Future<void> _addMat() async {
    final avail = mats.where((m) => !qty.containsKey(intv(m['id']))).toList();
    if (avail.isEmpty) {
      snack(context, 'Add more materials in the Materials tab first');
      return;
    }
    final pick = await showModalBottomSheet<Rec>(
      context: context,
      builder: (c) => ListView(
        children: [
          for (final m in avail)
            ListTile(
              title: Text(str(m['name'])),
              subtitle: Text('${moneyUnit(dbl(m['cost']))} / ${str(m['unit'])}'),
              onTap: () => Navigator.pop(c, m),
            ),
        ],
      ),
    );
    if (pick != null) setState(() => qty[intv(pick['id'])] = TextEditingController());
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      snack(context, 'Enter a package name');
      return;
    }
    final rec = <int, double>{for (final e in qty.entries) e.key: parseNum(e.value.text)};
    try {
      await Db.i.saveService(
        id: widget.copy ? null : widget.id,
        name: name.text.trim(),
        price: parseNum(price.text),
        machine: machine,
        active: active,
        recipe: rec,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, 'Could not save. Is that package name already used?');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNew = widget.id == null || widget.copy;
    final machines = <String>['Any', ...Db.i.cfgList('machines')];
    if (!machines.contains(machine)) machines.add(machine);
    final p = parseNum(price.text);
    final c = loading ? 0.0 : cost;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New package' : 'Edit package'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'Duplicate',
              icon: const Icon(Icons.copy),
              onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ServiceEditPage(id: widget.id, copy: true))),
            ),
          if (!isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'Delete package?', 'Past sales keep their history.')) {
                  await Db.i.deleteService(widget.id!);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      bottomNavigationBar: loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Save package'),
                ),
              ),
            ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                tf('Package name', name, autofocus: isNew),
                const SizedBox(height: 12),
                tf('Selling price', price, number: true, onChanged: (_) => setState(() {})),
                const SizedBox(height: 12),
                Text('Machine', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in machines)
                      ChoiceChip(label: Text(m), selected: m == machine, onSelected: (_) => setState(() => machine = m)),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show on the Wash screen'),
                  value: active,
                  onChanged: (v) => setState(() => active = v),
                ),
                Card(
                  color: cs.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _kv('Price', money(p)),
                        _kv('Material cost', money(c)),
                        _kv('Profit', money(p - c)),
                        _kv('Margin', p > 0 ? '${((p - c) / p * 100).toStringAsFixed(0)}%' : '-'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text('Materials used per wash', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _addMat,
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (qty.isEmpty)
                  Text('No materials yet. Add soap, wax, etc. so each wash has a real cost.',
                      style: TextStyle(color: cs.outline)),
                for (final e in qty.entries.toList()) _matRow(e.key, e.value, cs),
              ],
            ),
    );
  }

  Widget _kv(String k, String v) => Column(
        children: [
          Text(k, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      );

  Widget _matRow(int id, TextEditingController ctl, ColorScheme cs) {
    final m = mats.firstWhere((x) => intv(x['id']) == id, orElse: () => <String, Object?>{});
    final unit = str(m['unit']);
    final line = parseNum(ctl.text) * dbl(m['cost']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(str(m['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${moneyUnit(dbl(m['cost']))} / $unit  →  ${money(line)}',
                      style: TextStyle(fontSize: 12, color: cs.outline)),
                ],
              ),
            ),
            SizedBox(
              width: 110,
              child: tf('Qty', ctl, number: true, suffix: unit, onChanged: (_) => setState(() {})),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                qty.remove(id);
              }),
            ),
          ],
        ),
      ),
    );
  }
}
