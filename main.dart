import 'package:flutter/material.dart';
import 'db.dart';
import 'util.dart';
import 'pos.dart';
import 'services.dart';
import 'materials.dart';
import 'expenses.dart';
import 'reports.dart';
import 'more.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.i.init();
  runApp(const CarwashApp());
}

class CarwashApp extends StatelessWidget {
  const CarwashApp({super.key});

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0A84FF), brightness: b),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Car Wash POS',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int idx = 0;

  Future<void> _select(int i) async {
    if ((i == 3 || i == 4) && !await Pin.ensure(context)) return;
    if (!mounted) return;
    setState(() => idx = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<int>(
          valueListenable: Db.i.tick,
          builder: (_, __, ___) => Text(Db.i.cfg('business')),
        ),
        actions: [
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.menu),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const MorePage())),
          ),
        ],
      ),
      body: IndexedStack(
        index: idx,
        children: const [
          PosScreen(),
          ServicesScreen(),
          MaterialsScreen(),
          ExpensesScreen(),
          ReportsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.local_car_wash_outlined), selectedIcon: Icon(Icons.local_car_wash), label: 'Wash'),
          NavigationDestination(icon: Icon(Icons.sell_outlined), selectedIcon: Icon(Icons.sell), label: 'Packages'),
          NavigationDestination(icon: Icon(Icons.water_drop_outlined), selectedIcon: Icon(Icons.water_drop), label: 'Materials'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Expenses'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Reports'),
        ],
      ),
    );
  }
}
