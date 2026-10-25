import 'package:flutter/material.dart';

import '../main.dart';
import 'backup_screen.dart';
import 'brands_screens.dart';
import 'collabs_screens.dart';
import 'contacts_screens.dart';
import 'dashboard_screen.dart';
import 'payments_screen.dart';
import 'products_screens.dart';
import 'reports_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onOpenTab: (i) => setState(() => _tab = i)),
      const CollabsScreen(),
      const PaymentsScreen(),
      const ReportsScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake), label: 'Collabs'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Payments'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
        ],
      ),
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData i, String t, String s, Widget page) => ListTile(
          leading: Icon(i),
          title: Text(t),
          subtitle: Text(s),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => push(context, page),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(children: [
        Card(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(children: [
            tile(Icons.storefront_outlined, 'Brands', 'Companies you work with', const BrandsScreen()),
            tile(Icons.contacts_outlined, 'Contacts', 'People at brands and agencies', const ContactsScreen()),
            tile(Icons.inventory_2_outlined, 'Products', 'Items with images and links', const ProductsScreen()),
            tile(Icons.search, 'Search everything', 'Brands, collabs, products, links', const SearchScreen()),
          ]),
        ),
        Card(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(children: [
            tile(Icons.settings_outlined, 'Settings', 'Limits, invoice profile, security', const SettingsScreen()),
            tile(Icons.backup_outlined, 'Backup, restore & export', 'Encrypted .ccrm file, CSV', const BackupScreen()),
          ]),
        ),
        Card(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Lock now'),
            onTap: AuthGate.lockNow,
          ),
        ),
      ]),
    );
  }
}
