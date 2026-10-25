import 'package:flutter/material.dart';

import '../core/constants.dart';
import 'collabs_screens.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'reports_screen.dart';
import 'widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0; // 0 home, 1 collabs, 2 reports, 3 profile

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onOpenTab: (i) => setState(() => _tab = i)),
      const CollabsScreen(),
      const ReportsScreen(),
      const ProfileScreen(),
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
          child: Row(children: [
            item(0, Icons.space_dashboard_outlined, Icons.space_dashboard, 'Home'),
            item(1, Icons.handshake_outlined, Icons.handshake, 'Collabs'),
            Expanded(
              child: Center(
                child: Material(
                  color: kPrimary,
                  shape: const CircleBorder(),
                  elevation: 4,
                  shadowColor: kPrimary.withOpacity(0.5),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => push(context, const CollabFormScreen()),
                    child: const SizedBox(width: 54, height: 54, child: Icon(Icons.add, color: Colors.white, size: 30)),
                  ),
                ),
              ),
            ),
            item(2, Icons.insights_outlined, Icons.insights, 'Reports'),
            item(3, Icons.person_outline, Icons.person, 'Profile'),
          ]),
        ),
      ),
    );
  }
}
