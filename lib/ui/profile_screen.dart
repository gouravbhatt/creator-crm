import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';
import '../core/media.dart';
import '../core/repo.dart';
import '../main.dart';
import 'backup_screen.dart';
import 'brands_screens.dart';
import 'contacts_screens.dart';
import 'payments_screen.dart';
import 'products_screens.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'v2_widgets.dart';
import 'widgets.dart';

/// Creator profile — what appears on invoices — plus links to everything else.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  bool _dirty = false;
  bool _gst = false;
  String _photo = '';
  String _signature = '';
  final name = TextEditingController(),
      handle = TextEditingController(),
      niche = TextEditingController(),
      address = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController(),
      upi = TextEditingController(),
      pan = TextEditingController(),
      bank = TextEditingController(),
      gstin = TextEditingController(),
      gstRate = TextEditingController(),
      prefix = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Repo.settings();
    name.text = s['profile_name'] ?? '';
    handle.text = s['profile_handle'] ?? '';
    niche.text = s['profile_niche'] ?? '';
    address.text = s['profile_address'] ?? '';
    email.text = s['profile_email'] ?? '';
    phone.text = s['profile_phone'] ?? '';
    upi.text = s['profile_upi'] ?? '';
    pan.text = s['profile_pan'] ?? '';
    bank.text = s['profile_bank'] ?? '';
    gstin.text = s['profile_gstin'] ?? '';
    gstRate.text = s['gst_rate'] ?? '18';
    prefix.text = s['invoice_prefix'] ?? 'INV';
    _gst = (s['gst_registered'] ?? '0') == '1';
    _photo = s['profile_photo'] ?? '';
    _signature = s['signature_file'] ?? '';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final map = {
      'profile_name': name.text.trim(),
      'profile_handle': handle.text.trim().replaceFirst('@', ''),
      'profile_niche': niche.text.trim(),
      'profile_address': address.text.trim(),
      'profile_email': email.text.trim(),
      'profile_phone': phone.text.trim(),
      'profile_upi': upi.text.trim(),
      'profile_pan': pan.text.trim().toUpperCase(),
      'profile_bank': bank.text.trim(),
      'profile_gstin': _gst ? gstin.text.trim().toUpperCase() : '',
      'gst_registered': _gst ? '1' : '0',
      'gst_rate': gstRate.text.trim().isEmpty ? '18' : gstRate.text.trim(),
      'invoice_prefix': prefix.text.trim().isEmpty ? 'INV' : prefix.text.trim(),
    };
    for (final e in map.entries) {
      await Repo.setSetting(e.key, e.value);
    }
    setState(() => _dirty = false);
    if (mounted) toast(context, 'Profile saved');
  }

  Future<void> _pickImage(String key) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: key == 'profile_photo' ? 600 : 800, imageQuality: 90);
    if (f == null) return;
    final n = await Media.importFile(f.path);
    final old = key == 'profile_photo' ? _photo : _signature;
    if (old.isNotEmpty) await Media.remove(old);
    await Repo.setSetting(key, n);
    setState(() {
      if (key == 'profile_photo') {
        _photo = n;
      } else {
        _signature = n;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (_dirty)
            Padding(padding: const EdgeInsets.only(right: 12), child: FilledButton(onPressed: _save, child: const Text('Save'))),
        ],
      ),
      body: Form(
        key: _form,
        onChanged: () {
          if (!_dirty) setState(() => _dirty = true);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          Panel(
            child: Column(children: [
              GestureDetector(
                onTap: () => _pickImage('profile_photo'),
                child: Stack(children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kPrimary, width: 3)),
                    child: ClipOval(
                      child: _photo.isEmpty
                          ? Container(color: kPrimaryTint, child: const Icon(Icons.person_outline, size: 44, color: kPrimary))
                          : ProductThumb(fileName: _photo, type: kPaid, size: 100, radius: 50),
                    ),
                  ),
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(radius: 17, backgroundColor: kPrimary, child: Icon(Icons.edit, size: 16, color: Colors.white)),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              Text(name.text.isEmpty ? 'Your name' : name.text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(handle.text.isEmpty ? '@your_handle' : '@${handle.text.replaceFirst('@', '')}',
                  style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Your photo and @handle go on the invoice header', style: TextStyle(fontSize: 12, color: kMuted)),
            ]),
          ),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SmallLabel('About you'),
              const SizedBox(height: 10),
              textField(name, 'Name on invoice'),
              textField(handle, 'Instagram handle', hint: 'without @', keyboard: TextInputType.text),
              textField(niche, 'Niche', hint: 'Beauty · Lifestyle'),
              textField(address, 'Address (printed on invoice)', maxLines: 3, keyboard: TextInputType.multiline),
              emailField(email),
              textField(phone, 'Phone / WhatsApp', keyboard: TextInputType.phone),
            ]),
          ),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SmallLabel('Get paid'),
              const SizedBox(height: 10),
              textField(upi, 'UPI ID (QR on invoice)',
                  hint: 'name@bank',
                  keyboard: TextInputType.emailAddress,
                  validate: (t) => RegExp(r'^[\w.\-]{2,}@[A-Za-z]{2,}$').hasMatch(t) ? null : 'Format: name@bank'),
              textField(pan, 'PAN (optional, for TDS)',
                  keyboard: TextInputType.visiblePassword,
                  validate: (t) => RegExp(r'^[A-Za-z]{5}[0-9]{4}[A-Za-z]$').hasMatch(t) ? null : 'Format: ABCDE1234F'),
              textField(bank, 'Bank details (optional)', hint: 'A/c no · IFSC · bank', maxLines: 2, keyboard: TextInputType.multiline),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I’m GST registered', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Off: simple invoice, no GST'),
                value: _gst,
                onChanged: (v) => setState(() {
                  _gst = v;
                  _dirty = true;
                }),
              ),
              if (_gst) ...[
                textField(gstin, 'GSTIN',
                    keyboard: TextInputType.visiblePassword,
                    validate: (t) => RegExp(r'^[0-9]{2}[A-Za-z0-9]{13}$').hasMatch(t) ? null : 'GSTIN is 15 characters'),
                textField(gstRate, 'GST rate (%)', keyboard: const TextInputType.numberWithOptions(decimal: true)),
              ],
              textField(prefix, 'Invoice number prefix'),
              Row(children: [
                SizedBox(
                  width: 120,
                  height: 50,
                  child: _signature.isEmpty
                      ? const Center(child: Text('No signature', style: TextStyle(color: kMuted, fontSize: 12)))
                      : MediaImage(_signature, fit: BoxFit.contain),
                ),
                const Spacer(),
                TextButton(onPressed: () => _pickImage('signature_file'), child: Text(_signature.isEmpty ? 'Add signature' : 'Change')),
              ]),
              const SizedBox(height: 8),
              FilledButton(onPressed: _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: const Text('Save profile')),
            ]),
          ),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              _link(Icons.storefront_outlined, 'Brands', const BrandsScreen()),
              _link(Icons.contacts_outlined, 'Contacts', const ContactsScreen()),
              _link(Icons.inventory_2_outlined, 'Products', const ProductsScreen()),
              _link(Icons.payments_outlined, 'Payments', const PaymentsScreen()),
              _link(Icons.search, 'Search everything', const SearchScreen()),
            ]),
          ),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              _link(Icons.backup_outlined, 'Backup, restore & export', const BackupScreen()),
              _link(Icons.tune, 'Limits & security', const SettingsScreen()),
              ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Lock now'), onTap: AuthGate.lockNow),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _link(IconData i, String t, Widget page) => ListTile(
        leading: Icon(i),
        title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => push(context, page),
      );
}
