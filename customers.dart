import 'package:flutter/material.dart';
import 'db.dart';
import 'util.dart';

Future<Rec?> pickCustomer(BuildContext context) {
  return showModalBottomSheet<Rec>(
    context: context,
    isScrollControlled: true,
    builder: (c) => const _Picker(),
  );
}

class _Picker extends StatefulWidget {
  const _Picker();
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final q = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: tf('Search name, plate or phone', q, autofocus: true, onChanged: (_) => setState(() {})),
          ),
          Expanded(
            child: FutureBuilder<List<Rec>>(
              future: Db.i.customers(q.text.trim()),
              builder: (c, snap) {
                final rows = snap.data ?? [];
                if (rows.isEmpty) return const EmptyState(icon: Icons.people_outline, text: 'No customers found');
                return ListView(
                  children: [
                    for (final r in rows)
                      ListTile(
                        title: Text(str(r['name'])),
                        subtitle: Text(str(r['plate'])),
                        onTap: () => Navigator.pop(context, r),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final q = TextEditingController();

  Future<void> _edit([Rec? c]) async {
    final name = TextEditingController(text: c == null ? '' : str(c['name']));
    final plate = TextEditingController(text: c == null ? '' : str(c['plate']));
    final phone = TextEditingController(text: c == null ? '' : str(c['phone']));
    final notes = TextEditingController(text: c == null ? '' : str(c['notes']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(c == null ? 'New customer' : 'Edit customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tf('Name', name),
              const SizedBox(height: 10),
              tf('Plate no.', plate, cap: TextCapitalization.characters),
              const SizedBox(height: 10),
              tf('Phone', phone),
              const SizedBox(height: 10),
              tf('Notes', notes, lines: 2),
            ],
          ),
        ),
        actions: [
          if (c != null)
            TextButton(
              onPressed: () async {
                if (await confirm(d, 'Delete customer?', 'Their past sales stay in your reports.')) {
                  await Db.i.deleteCustomer(intv(c['id']));
                  if (d.mounted) Navigator.pop(d, false);
                }
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    await Db.i.saveCustomer(
      id: c == null ? null : intv(c['id']),
      name: name.text.trim(),
      plate: plate.text.trim().toUpperCase(),
      phone: phone.text.trim(),
      notes: notes.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add),
        label: const Text('Customer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: tf('Search', q, onChanged: (_) => setState(() {})),
          ),
          Expanded(
            child: Reload<List<Rec>>(
              load: () => Db.i.customers(q.text.trim()),
              builder: (c, rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                      icon: Icons.people_outline,
                      text: 'No customers yet.\nPlates you enter at checkout are saved here automatically.');
                }
                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (c, i) {
                    final r = rows[i];
                    return ListTile(
                      onTap: () => _edit(r),
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(str(r['name'])),
                      subtitle: Text([
                        if (str(r['plate']).isNotEmpty) str(r['plate']),
                        if (str(r['phone']).isNotEmpty) str(r['phone']),
                      ].join('  •  ')),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${intv(r['visits'])} washes'),
                          Text(money(dbl(r['spent'])), style: const TextStyle(fontSize: 12)),
                        ],
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
