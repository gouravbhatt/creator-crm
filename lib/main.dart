import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'core/constants.dart';
import 'core/db.dart';
import 'core/repo.dart';
import 'core/security.dart';
import 'ui/auth_screens.dart';
import 'ui/home_shell.dart';

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CreatorCrmApp());
}

class CreatorCrmApp extends StatelessWidget {
  const CreatorCrmApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: kPrimary, primary: kPrimary, surface: Colors.white);
    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(26));
    return MaterialApp(
      title: 'Creator CRM',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: kBg,
        textTheme: ThemeData.light().textTheme.apply(bodyColor: kInk, displayColor: kInk),
        appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          foregroundColor: kInk,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kInk, letterSpacing: -0.3),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(shape: pill, textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(shape: pill, side: const BorderSide(color: kPrimary, width: 1.5)),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          side: BorderSide.none,
          backgroundColor: Colors.white,
          selectedColor: kInk,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          secondaryLabelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          checkmarkColor: Colors.white,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: kPrimaryTint,
          labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E0EC))),
          enabledBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E0EC))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kPrimary, width: 1.6)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

enum _Gate { loading, setup, locked, unlocked }

/// Decides between first-run setup, lock screen and the app; auto-locks after inactivity.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  /// Callable from anywhere (e.g. "Lock now" in More).
  static void lockNow() => _AuthGateState.instance?._lock();

  static Future<void> refreshAutoLock() async => _AuthGateState.instance?.refreshAutoLock();

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  static _AuthGateState? instance;
  _Gate _gate = _Gate.loading;
  DateTime? _pausedAt;
  int _autoLockMinutes = 5;

  @override
  void initState() {
    super.initState();
    instance = this;
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (instance == this) instance = null;
    super.dispose();
  }

  Future<void> _init() async {
    final exists = await Vault.exists();
    setState(() => _gate = exists ? _Gate.locked : _Gate.setup);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final p = _pausedAt;
      _pausedAt = null;
      if (_gate == _Gate.unlocked && _autoLockMinutes > 0 && p != null &&
          DateTime.now().difference(p).inMinutes >= _autoLockMinutes) {
        _lock();
      }
    }
  }

  Future<void> onUnlocked(List<int> dbKey, String user) async {
    await AppDb.open(dbKey);
    Session.dbKey = Uint8List.fromList(dbKey);
    Session.user = user;
    _autoLockMinutes = await Repo.settingInt('auto_lock_minutes', 5);
    if (mounted) setState(() => _gate = _Gate.unlocked);
  }

  Future<void> refreshAutoLock() async {
    _autoLockMinutes = await Repo.settingInt('auto_lock_minutes', 5);
  }

  Future<void> _lock() async {
    rootNavKey.currentState?.popUntil((r) => r.isFirst);
    await AppDb.close();
    Session.clear();
    if (mounted) setState(() => _gate = _Gate.locked);
  }

  Future<void> resetToSetup() async {
    rootNavKey.currentState?.popUntil((r) => r.isFirst);
    await AppDb.close();
    Session.clear();
    if (mounted) setState(() => _gate = _Gate.setup);
  }

  @override
  Widget build(BuildContext context) {
    switch (_gate) {
      case _Gate.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _Gate.setup:
        return SetupScreen(onDone: onUnlocked);
      case _Gate.locked:
        return LoginScreen(onUnlocked: onUnlocked);
      case _Gate.unlocked:
        return const HomeShell();
    }
  }
}
