import 'package:flutter/material.dart';
import 'db.dart';
import 'util.dart';
import 'customers.dart';
import 'sales.dart';
import 'excel_io.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  Future<void> _guarded(BuildContext context, Future<void> Function() job) async {
    if (!await Pin.ensure(context)) return;
    try {
      await job();
    } catch (e) {
      if (context.mounted) snack(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Customers'),
            subtitle: const Text('Plates, phones and wash history'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomersPage())),
          ),
          ListTile(
            leading: const Icon(Icons.receipt),
            title: const Text('Sales history'),
            subtitle: const Text('Review or void past sales'),
            onTap: () => _guarded(context, () async {
              if (!context.mounted) return;
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesPage()));
            }),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('Export everything to Excel'),
            subtitle: const Text('Materials, packages, recipes, customers, expenses, sales'),
            onTap: () => _guarded(context, () async {
              snack(context, 'Preparing Excel file…');
              await XlsxIo.exportAll();
            }),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload),
            title: const Text('Import from Excel'),
            subtitle: const Text('Materials, packages, recipes, customers, expenses'),
            onTap: () => _guarded(context, () async {
              final msg = await XlsxIo.importFile();
              if (msg == null || !context.mounted) return;
              await showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Import finished'),
                  content: Text(msg),
                  actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
                ),
              );
            }),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () => _guarded(context, () async {
              if (!context.mounted) return;
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
            }),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Car Wash POS 1.0 • works offline • all data stays on this device. '
                'Use "Export everything to Excel" regularly as a backup.'),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final biz = TextEditingController(text: Db.i.cfg('business'));
  final cur = TextEditingController(text: Db.i.cfg('currency'));
  final machines = TextEditingController(text: Db.i.cfg('machines'));
  final payments = TextEditingController(text: Db.i.cfg('payments'));
  final cats = TextEditingController(text: Db.i.cfg('categories'));
  final footer = TextEditingController(text: Db.i.cfg('footer'));
  final pin = TextEditingController(text: Db.i.cfg('pin'));

  Future<void> _save() async {
    await Db.i.setCfg('business', biz.text.trim());
    await Db.i.setCfg('currency', cur.text.trim());
    await Db.i.setCfg('machines', machines.text.trim());
    await Db.i.setCfg('payments', payments.text.trim());
    await Db.i.setCfg('categories', cats.text.trim());
    await Db.i.setCfg('footer', footer.text.trim());
    await Db.i.setCfg('pin', pin.text.trim());
    Pin.unlocked = false;
    if (mounted) {
      snack(context, 'Settings saved');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          tf('Business name', biz),
          gap,
          tf('Currency symbol', cur, cap: TextCapitalization.none),
          gap,
          tf('Machines (comma separated)', machines, cap: TextCapitalization.characters),
          gap,
          tf('Payment methods (comma separated)', payments),
          gap,
          tf('Expense categories (comma separated)', cats, lines: 3),
          gap,
          tf('Receipt footer', footer),
          gap,
          tf('PIN lock for Expenses, Reports, Sales, Excel and Settings (leave empty for none)', pin,
              number: true, obscure: true, lines: 1),
          const SizedBox(height: 8),
          Text(
            'Tip: keep "Materials restock" in the expense categories. It is used when you restock materials and is not double counted in profit.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
