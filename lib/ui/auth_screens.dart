import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../core/constants.dart';
import '../core/db.dart';
import '../core/media.dart';
import '../core/security.dart';
import 'widgets.dart';

typedef UnlockCallback = Future<void> Function(List<int> dbKey, String user);

String? passwordProblem(String p) {
  if (p.length < 8) return 'Use at least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'[0-9]').hasMatch(p)) return 'Use letters and numbers';
  return null;
}

class _Brand extends StatelessWidget {
  final String subtitle;
  const _Brand(this.subtitle);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset('assets/logo.png', width: 60, height: 60)),
        const SizedBox(height: 16),
        const Text(kAppName, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: kMuted)),
        const SizedBox(height: 24),
      ]);
}

class SetupScreen extends StatefulWidget {
  final UnlockCallback onDone;
  const SetupScreen({super.key, required this.onDone});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  bool _show = false;

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AppDb.destroy();
      await Media.clearAll();
      final (rk, key) = await Vault.create(_user.text.trim(), _pw.text);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RecoveryKeyScreen(recoveryKey: rk),
      ));
      await widget.onDone(key, _user.text.trim());
    } catch (e) {
      if (mounted) toast(context, 'Setup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const _Brand('Set up your private, offline workspace. Data stays encrypted on this phone.'),
            textField(_user, 'Username', req: true),
            TextFormField(
              controller: _pw,
              obscureText: !_show,
              decoration: deco('Password *',
                  suffix: IconButton(
                      icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _show = !_show))),
              validator: (v) => passwordProblem(v ?? ''),
            ),
            const Gap(),
            TextFormField(
              controller: _pw2,
              obscureText: !_show,
              decoration: deco('Confirm password *'),
              validator: (v) => v != _pw.text ? 'Passwords do not match' : null,
            ),
            const Gap(),
            FilledButton(
              onPressed: _busy ? null : _create,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create workspace'),
            ),
            const SizedBox(height: 12),
            const Text('Next you will get a recovery key. It is the only way back in if you forget the password.',
                style: TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class RecoveryKeyScreen extends StatefulWidget {
  final String recoveryKey;
  const RecoveryKeyScreen({super.key, required this.recoveryKey});
  @override
  State<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends State<RecoveryKeyScreen> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _saved,
      child: Scaffold(
        appBar: AppBar(title: const Text('Your recovery key'), automaticallyImplyLeading: false),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text(
              'Write this down or store it in a password manager. It is shown only once and is not stored on the phone in readable form.',
              style: TextStyle(color: kMuted)),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(widget.recoveryKey,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 18, letterSpacing: 1, height: 1.6)),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => copyText(context, widget.recoveryKey),
            icon: const Icon(Icons.copy),
            label: const Text('Copy key'),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _saved,
            onChanged: (v) => setState(() => _saved = v ?? false),
            title: const Text('I have saved my recovery key somewhere safe'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saved ? () => Navigator.pop(context) : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const Text('Continue'),
          ),
        ]),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final UnlockCallback onUnlocked;
  const LoginScreen({super.key, required this.onUnlocked});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  bool _show = false;
  bool _bio = false;
  bool _usePassword = false;
  String _name = '';
  int _fails = 0;
  DateTime? _blockedUntil;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final u = await Vault.username();
    final mode = await Vault.quickMode();
    if (!mounted) return;
    setState(() {
      _user.text = u;
      _name = u;
      _bio = mode == Vault.quickBio;
      _usePassword = !_bio;
    });
    if (_bio) _fingerprint();
  }

  Future<void> _fingerprint() async {
    setState(() => _error = null);
    try {
      final auth = LocalAuthentication();
      final ok = await auth.authenticate(
        localizedReason: 'Unlock $kAppName',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      if (!ok) return;
      final key = await Vault.quickKey();
      if (key == null) {
        setState(() {
          _usePassword = true;
          _error = 'Fingerprint needs to be set up again. Use your password.';
        });
        return;
      }
      setState(() => _busy = true);
      await widget.onUnlocked(key, _user.text.trim());
    } catch (e) {
      if (mounted) {
        setState(() {
          _usePassword = true;
          _error = 'Fingerprint not available. Use your password.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    final until = _blockedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      setState(() => _error = 'Too many attempts. Try again in ${until.difference(DateTime.now()).inSeconds + 1}s');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await Vault.unlockWithPassword(_user.text, _pw.text);
      _pw.clear();
      await widget.onUnlocked(key, _user.text.trim());
    } on AuthException catch (e) {
      _fails++;
      if (_fails % 5 == 0) _blockedUntil = DateTime.now().add(Duration(seconds: 30 * (_fails ~/ 5)));
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not open data: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const soft = Color(0xFFC9C5DC);
    InputDecoration dark(String l, {Widget? suffix}) => InputDecoration(
          labelText: l,
          labelStyle: const TextStyle(color: soft),
          filled: true,
          fillColor: const Color(0x14FFFFFF),
          suffixIcon: suffix,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0x33FFFFFF))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF9D87FF), width: 1.6)),
        );
    return Scaffold(
      backgroundColor: kInk,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(28, 72, 28, 28), children: [
          Center(child: ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/logo.png', width: 84, height: 84))),
          const SizedBox(height: 18),
          const Center(child: Text(kAppName, style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8))),
          Center(child: Text(_name.isEmpty ? kTagline : 'Welcome back, $_name', style: const TextStyle(color: soft))),
          const SizedBox(height: 56),
          if (_bio && !_usePassword) ...[
            Center(
              child: Material(
                color: const Color(0x14FFFFFF),
                shape: const CircleBorder(side: BorderSide(color: kPrimary, width: 2)),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _busy ? null : _fingerprint,
                  child: const SizedBox(width: 88, height: 88, child: Icon(Icons.fingerprint, color: Colors.white, size: 46)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Center(child: Text('Touch to unlock', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => setState(() => _usePassword = true),
                child: const Text('Use password instead', style: TextStyle(color: soft)),
              ),
            ),
          ] else ...[
            TextField(controller: _user, style: const TextStyle(color: Colors.white), decoration: dark('Username')),
            const SizedBox(height: 12),
            TextField(
              controller: _pw,
              obscureText: !_show,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _login(),
              decoration: dark('Password',
                  suffix: IconButton(
                      icon: Icon(_show ? Icons.visibility_off : Icons.visibility, color: soft),
                      onPressed: () => setState(() => _show = !_show))),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _login,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: kPrimary),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Unlock'),
            ),
            if (_bio)
              TextButton.icon(
                onPressed: _fingerprint,
                icon: const Icon(Icons.fingerprint, color: soft),
                label: const Text('Use fingerprint', style: TextStyle(color: soft)),
              ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecoverScreen(onUnlocked: widget.onUnlocked))),
              child: const Text('Forgot password? Use recovery key', style: TextStyle(color: soft)),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFB4A8))),
            ),
          const SizedBox(height: 40),
          const Center(child: Text('Your data never leaves this phone · encrypted', style: TextStyle(color: Color(0xFF8A85A3), fontSize: 11))),
        ]),
      ),
    );
  }
}

class RecoverScreen extends StatefulWidget {
  final UnlockCallback onUnlocked;
  const RecoverScreen({super.key, required this.onUnlocked});
  @override
  State<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends State<RecoverScreen> {
  final _form = GlobalKey<FormState>();
  final _rk = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;

  Future<void> _recover() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final key = await Vault.unlockWithRecovery(_rk.text);
      await Vault.setPassword(key, _pw.text);
      final user = await Vault.username();
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onUnlocked(key, user);
    } on AuthException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Recovery failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recover access')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Enter the recovery key you saved at setup, then choose a new password. Your data is not changed.',
              style: TextStyle(color: kMuted)),
          const SizedBox(height: 20),
          textField(_rk, 'Recovery key', req: true, keyboard: TextInputType.visiblePassword, hint: 'XXXX-XXXX-…'),
          TextFormField(
              controller: _pw,
              obscureText: true,
              decoration: deco('New password *'),
              validator: (v) => passwordProblem(v ?? '')),
          const Gap(),
          TextFormField(
              controller: _pw2,
              obscureText: true,
              decoration: deco('Confirm new password *'),
              validator: (v) => v != _pw.text ? 'Passwords do not match' : null),
          const Gap(),
          FilledButton(
            onPressed: _busy ? null : _recover,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Reset password and unlock'),
          ),
        ]),
      ),
    );
  }
}
