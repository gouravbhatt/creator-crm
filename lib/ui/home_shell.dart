import 'package:flutter/material.dart';

import '../core/constants.dart';
import 'collabs_screens.dart';
import 'dashboard_screen.dart';
import 'income_screen.dart';
import 'reports_screen.dart';
import 'type_picker.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0; // 0 home, 1 collabs, 2 income, 3 reports

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onOpenTab: (i) => setState(() => _tab = i)),
      const CollabsScreen(),
      const IncomeScreen(),
      const ReportsScreen(),
    ];
    Widget item(int i, IconData icon, IconData active, String label) {
      final on = _tab == i;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = i),
          child: SizedBox(
            height: 64,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(on ? active : icon, color: on ? kPrimary : kMuted),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: on ? FontWeight.w800 : FontWeight.w500, color: on ? kPrimary : kMuted)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Color(0x0F17142B), blurRadius: 20, offset: Offset(0, -4))],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 68,
            child: Row(children: [
              item(0, Icons.space_dashboard_outlined, Icons.space_dashboard, 'Home'),
              item(1, Icons.handshake_outlined, Icons.handshake, 'Collabs'),
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  heightFactor: 1,
                  child: Material(
                    color: kPrimary,
                    shape: const CircleBorder(),
                    elevation: 4,
                    shadowColor: kPrimary.withOpacity(0.5),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => showAddSheet(context),
                      child: const SizedBox(width: 54, height: 54, child: Icon(Icons.add, color: Colors.white, size: 30)),
                    ),
                  ),
                ),
              ),
              item(2, Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Income'),
              item(3, Icons.insights_outlined, Icons.insights, 'Reports'),
            ]),
          ),
        ),
      ),
    );
  }
}
