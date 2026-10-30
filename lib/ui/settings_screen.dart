import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';

import '../core/constants.dart';
import '../core/db.dart';
import '../core/media.dart';
import '../core/repo.dart';
import '../core/security.dart';
import '../main.dart';
import 'auth_screens.dart';
import 'products_screens.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _limits = GlobalKey<FormState>();
  final _profile = GlobalKey<FormState>();
  bool _loading = true;
  int _autoLock = 30;
  String _quick = '';
  bool _bioAvailable = false;
  String _signature = '';
  int _maxImgUsed = 0;
  int _maxLinkUsed = 0;
  final maxImages = TextEditingController(),
      maxLinks = TextEditingController(),
      pName = TextEditingController(),
      pAddress = TextEditingController(),
      pGstin = TextEditingController(),
      pPan = TextEditingController(),
      pEmail = TextEditingController(),
      pPhone = TextEditingController(),
      pUpi = TextEditingController(),
      invPrefix = TextEditingController(),
      gstRate = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Repo.settings();
    maxImages.text = s['max_images'] ?? '5';
    maxLinks.text = s['max_links'] ?? '5';
    pName.text = s['profile_name'] ?? '';
    pAddress.text = s['profile_address'] ?? '';
    pGstin.text = s['profile_gstin'] ?? '';
    pPan.text = s['profile_pan'] ?? '';
    pEmail.text = s['profile_email'] ?? '';
    pPhone.text = s['profile_phone'] ?? '';
    pUpi.text = s['profile_upi'] ?? '';
    invPrefix.text = s['invoice_prefix'] ?? 'INV';
    gstRate.text = s['gst_rate'] ?? '18';
    _autoLock = int.tryParse(s['auto_lock_minutes'] ?? '30') ?? 30;
    if (![0, 1, 5, 15, 30, 60].contains(_autoLock)) _autoLock = 30;
    _quick = await Vault.quickMode();
    try {
      final la = LocalAuthentication();
      _bioAvailable = await la.isDeviceSupported() && (await la.canCheckBiometrics || await la.isDeviceSupported());
    } catch (_) {
      _bioAvailable = false;
    }
    _signature = s['signature_file'] ?? '';
    final img = await AppDb.db.rawQuery('SELECT MAX(n) AS m FROM (SELECT COUNT(*) AS n FROM product_images GROUP BY product_id)');
    final lnk = await AppDb.db.rawQuery('SELECT MAX(n) AS m FROM (SELECT COUNT(*) AS n FROM product_links GROUP BY product_id)');
    _maxImgUsed = (img.first['m'] as int?) ?? 0;
    _maxLinkUsed = (lnk.first['m'] as int?) ?? 0;
    if (mounted) setState(() => _loading = false);
  }

  String? _limitCheck(String t) {
    final v = int.tryParse(t);
    if (v == null) return 'Whole number';
    if (v < kLimitMin || v > kLimitMax) return 'Between $kLimitMin and $kLimitMax';
    return null;
  }

  Future<void> _saveLimits() async {
    if (!_limits.currentState!.validate()) return;
    final mi = int.parse(maxImages.text.trim());
    final ml = int.parse(maxLinks.text.trim());
    final warn = <String>[];
    if (mi < _maxImgUsed) warn.add('A product already has $_maxImgUsed images.');
    if (ml < _maxLinkUsed) warn.add('A product already has $_maxLinkUsed links.');
    if (warn.isNotEmpty) {
      final go = await confirm(context, 'Lower limit?',
          '${warn.join('\n')}\nNothing will be deleted. Those products just cannot get new items until they are under the limit.',
          ok: 'Save', danger: false);
      if (!go) return;
    }
    await Repo.setSetting('max_images', '$mi');
    await Repo.setSetting('max_links', '$ml');
    if (mounted) toast(context, 'Limits saved');
  }

  Future<void> _saveProfile() async {
    if (!_profile.currentState!.validate()) return;
    final map = {
      'profile_name': pName.text.trim(),
      'profile_address': pAddress.text.trim(),
      'profile_gstin': pGstin.text.trim().toUpperCase(),
      'profile_pan': pPan.text.trim().toUpperCase(),
      'profile_email': pEmail.text.trim(),
      'profile_phone': pPhone.text.trim(),
      'profile_upi': pUpi.text.trim(),
      'invoice_prefix': invPrefix.text.trim().isEmpty ? 'INV' : invPrefix.text.trim(),
      'gst_rate': gstRate.text.trim().isEmpty ? '18' : gstRate.text.trim(),
    };
    for (final e in map.entries) {
      await Repo.setSetting(e.key, e.value);
    }
    if (mounted) toast(context, 'Invoice profile saved');
  }

  Future<void> _pickSignature() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800);
    if (f == null) return;
    final name = await Media.importFile(f.path);
    if (_signature.isNotEmpty) await Media.remove(_signature);
    await Repo.setSetting('signature_file', name);
    setState(() => _signature = name);
  }

  Future<void> _setQuick(String mode) async {
    final key = Session.dbKey;
    if (key == null) return;
    if (mode.isEmpty) {
      await Vault.clearQuick();
    } else {
      if (mode == Vault.quickBio) {
        try {
          final ok = await LocalAuthentication().authenticate(
            localizedReason: 'Confirm fingerprint for $kAppName',
            options: const AuthenticationOptions(stickyAuth: true),
          );
          if (!ok) return;
        } catch (e) {
          if (mounted) toast(context, 'Fingerprint not available: $e');
          return;
        }
      }
      await Vault.setQuick(mode, key);
    }
    final m = await Vault.quickMode();
    if (mounted) {
      setState(() => _quick = m);
      toast(context, m == Vault.quickBio ? 'Fingerprint unlock on' : (m == Vault.quickStay ? 'App stays unlocked' : 'Password required'));
    }
  }

  Future<void> _changePassword() async {
    final cur = TextEditingController(), n1 = TextEditingController(), n2 = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Change password'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: cur, obscureText: true, decoration: deco('Current password')),
            const Gap(),
            TextFormField(
                controller: n1, obscureText: true, decoration: deco('New password'), validator: (v) => passwordProblem(v ?? '')),
            const Gap(),
            TextFormField(
                controller: n2,
                obscureText: true,
                decoration: deco('Confirm new password'),
                validator: (v) => v != n1.text ? 'Does not match' : null),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(d, true);
              },
              child: const Text('Change')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Vault.unlockWithPassword(Session.user, cur.text);
      await Vault.setPassword(Session.dbKey!, n1.text);
      if (mounted) toast(context, 'Password changed');
    } on AuthException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _newRecovery() async {
    final go = await confirm(context, 'New recovery key?', 'Your old recovery key will stop working. Continue?',
        ok: 'Generate', danger: false);
    if (!go) return;
    final rk = await Vault.regenerateRecovery(Session.dbKey!);
    if (!mounted) return;
    await push(context, RecoveryKeyScreen(recoveryKey: rk));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lock & limits')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
              SectionCard(
                title: 'Product limits',
                child: Form(
                  key: _limits,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    textField(maxImages, 'Max images per product', keyboard: TextInputType.number, validate: _limitCheck),
                    textField(maxLinks, 'Max links per product', keyboard: TextInputType.number, validate: _limitCheck),
                    Text(
                        'Current highest use: $_maxImgUsed images, $_maxLinkUsed links on a single product. '
                        'Lowering a limit never deletes anything. Images are stored at up to ~2000px (≈0.3–1 MB each), '
                        'so 20 images per product ≈ 10–20 MB.',
                        style: const TextStyle(fontSize: 12, color: kMuted)),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _saveLimits, child: const Text('Save limits'))),
                  ]),
                ),
              ),
              SectionCard(
                title: 'Lock & security',
                child: Column(children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Unlock with fingerprint', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_bioAvailable ? 'Password only if fingerprint fails' : 'No fingerprint / screen lock set on this phone'),
                    value: _quick == Vault.quickBio,
                    onChanged: !_bioAvailable ? null : (v) => _setQuick(v ? Vault.quickBio : ''),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Stay unlocked on this phone', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Skip the lock screen. Your phone’s own lock protects the app.'),
                    value: _quick == Vault.quickStay,
                    onChanged: (v) => _setQuick(v ? Vault.quickStay : ''),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto-lock'),
                    subtitle: const Text('Lock after the app is in the background for'),
                    trailing: DropdownButton<int>(
                      value: _autoLock,
                      items: const [0, 1, 5, 15, 30, 60]
                          .map((m) => DropdownMenuItem(value: m, child: Text(m == 0 ? 'Never' : (m == 60 ? '1 hour' : '$m min'))))
                          .toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        await Repo.setSetting('auto_lock_minutes', '$v');
                        setState(() => _autoLock = v);
                        await AuthGate.refreshAutoLock();
                      },
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Change password'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _changePassword,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Generate new recovery key'),
                    subtitle: const Text('Use if your recovery key was lost or exposed'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _newRecovery,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Signed in as ${Session.user}'),
                    subtitle: Text('Database schema v${AppDb.schemaVersion} · SQLCipher AES-256'),
                  ),
                ]),
              ),
            ]),
    );
  }
}
