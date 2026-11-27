import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'db.dart';
import 'util.dart';
import 'customers.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Rec> services = [];
  final Map<int, CartLine> cart = {};
  String machine = '';
  String payment = '';
  final plate = TextEditingController();
  final cust = TextEditingController();
  final disc = TextEditingController();

  @override
  void initState() {
    super.initState();
    Db.i.tick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Db.i.tick.removeListener(_load);
    plate.dispose();
    cust.dispose();
    disc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await Db.i.servicesWithCost();
    if (!mounted) return;
    setState(() => services = r.where((e) => intv(e['active']) == 1).toList());
  }

  double get gross =>
      cart.values.fold(0.0, (s, l) => s + l.price * l.qty);
  double get discount => parseNum(disc.text).clamp(0, gross).toDouble();
  double get total => gross - discount;

  void _add(Rec s) {
    final id = intv(s['id']);
    setState(() {
      final l = cart[id];
      if (l == null) {
        cart[id] = CartLine(id, str(s['name']), dbl(s['price']), dbl(s['cost']), 1);
      } else {
        l.qty++;
      }
    });
  }

  void _clear() => setState(() {
        cart.clear();
        plate.clear();
        cust.clear();
        disc.clear();
      });

  Future<void> _lookup(String v) async {
    final c = await Db.i.customerByPlate(v.trim().toUpperCase());
    if (c != null && mounted && cust.text.isEmpty) {
      final n = str(c['name']);
      if (n != str(c['plate'])) setState(() => cust.text = n);
    }
  }

  Future<void> _pick() async {
    final c = await pickCustomer(context);
    if (c != null) {
      setState(() {
        plate.text = str(c['plate']);
        cust.text = str(c['name']);
      });
    }
  }

  Future<void> _charge() async {
    final t = total;
    final received = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final rec = parseNum(received.text);
        return AlertDialog(
          title: Text('Charge ${money(t)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$machine  •  $payment'),
              if (payment == 'Cash') ...[
                const SizedBox(height: 12),
                tf('Cash received', received,
                    number: true, autofocus: true, onChanged: (_) => set(() {})),
                const SizedBox(height: 8),
                Text(rec >= t && rec > 0 ? 'Change: ${money(rec - t)}' : '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
          ],
        );
      }),
    );
    if (ok != true) return;
    try {
      final id = await Db.i.checkout(
        lines: cart.values.toList(),
        machine: machine,
        plate: plate.text.trim().toUpperCase(),
        customer: cust.text.trim(),
        payment: payment,
        discount: discount,
      );
      final text = await buildReceipt(id);
      final low = await Db.i.lowStock();
      _clear();
      if (!mounted) return;
      if (low.isNotEmpty) {
        snack(context, 'Low stock: ${low.map((e) => e['name']).join(', ')}');
      }
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Sale saved'),
          content: SingleChildScrollView(
            child: Text(text, style: const TextStyle(fontFamily: 'monospace')),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Share.share(text),
              icon: const Icon(Icons.share),
              label: const Text('Share'),
            ),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) snack(context, 'Could not save sale: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final machines = Db.i.cfgList('machines');
    final payments = Db.i.cfgList('payments');
    if (!machines.contains(machine)) machine = machines.isEmpty ? '' : machines.first;
    if (!payments.contains(payment)) payment = payments.isEmpty ? 'Cash' : payments.first;
    final shown = services.where((s) {
      final m = str(s['machine']);
      return m == 'Any' || m == machine;
    }).toList();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final m in machines)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: const Icon(Icons.local_car_wash, size: 18),
                        label: Text(m),
                        selected: m == machine,
                        onSelected: (_) => setState(() => machine = m),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                Expanded(child: tf('Plate no.', plate, cap: TextCapitalization.characters, onChanged: _lookup)),
                const SizedBox(width: 8),
                Expanded(child: tf('Customer', cust)),
                IconButton(tooltip: 'Pick customer', icon: const Icon(Icons.person_search), onPressed: _pick),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const EmptyState(
                    icon: Icons.sell_outlined,
                    text: 'No packages yet.\nGo to Materials, add your soap, wax, etc., then create a package in Packages.')
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.6,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (c, i) {
                      final s = shown[i];
                      final inCart = cart[intv(s['id'])]?.qty ?? 0;
                      return Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _add(s),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(str(s['name']),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                    if (inCart > 0)
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundColor: cs.primary,
                                        child: Text('$inCart', style: TextStyle(fontSize: 12, color: cs.onPrimary)),
                                      ),
                                  ],
                                ),
                                Text(money(dbl(s['price'])),
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary)),
                                Text('Cost ${money(dbl(s['cost']))}',
                                    style: TextStyle(fontSize: 12, color: cs.outline)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (cart.isNotEmpty) _cartPanel(cs, payments),
        ],
      ),
    );
  }

  Widget _cartPanel(ColorScheme cs, List<String> payments) {
    return Material(
      elevation: 8,
      color: cs.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 130),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final l in cart.values.toList())
                      Row(
                        children: [
                          Expanded(child: Text(l.name, overflow: TextOverflow.ellipsis)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => setState(() {
                              if (l.qty > 1) {
                                l.qty--;
                              } else {
                                cart.remove(l.serviceId);
                              }
                            }),
                          ),
                          Text('${l.qty}'),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => setState(() => l.qty++),
                          ),
                          SizedBox(
                            width: 76,
                            child: Text(money(l.price * l.qty), textAlign: TextAlign.end),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final p in payments)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(p),
                                selected: p == payment,
                                onSelected: (_) => setState(() => payment = p),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 90, child: tf('Discount', disc, number: true, onChanged: (_) => setState(() {}))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total', style: TextStyle(fontSize: 12, color: cs.outline)),
                        Text(money(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _clear, child: const Text('Clear')),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: _charge,
                    icon: const Icon(Icons.payments),
                    label: const Text('Charge'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
