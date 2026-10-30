import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/repo.dart';
import 'widgets.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with AutoReload {
  List<Rec>? _rows;
  Map<String, String> _brands = {};
  String _q = '';

  @override
  Future<void> reload() async {
    final rows = await Repo.all('contacts', orderBy: 'name COLLATE NOCASE');
    final brands = await Repo.all('brands');
    if (mounted) {
      setState(() {
        _rows = rows;
        _brands = {for (final b in brands) str(b['id']): str(b['name'])};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = (_rows ?? [])
        .where((c) =>
            q.isEmpty ||
            [c['name'], c['email'], c['phone'], c['role'], c['company'], c['instagram'], _brands[str(c['brand_id'])], c['notes']]
                .map(str)
                .join(' ')
                .toLowerCase()
                .contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => push(context, const ContactFormScreen()),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Contact'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: deco('Search name, brand, role, email…').copyWith(prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: _rows == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const EmptyState(icon: Icons.contacts_outlined, text: 'No contacts.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final c = list[i];
                        final phone = str(c['phone']);
                        final email = str(c['email']);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(str(c['name'])),
                            subtitle: Text([
                              _brands[str(c['brand_id'])] ?? '',
                              str(c['role']),
                            ].where((x) => x.isNotEmpty).join(' · ')),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (phone.isNotEmpty)
                                IconButton(
                                    tooltip: 'Call',
                                    icon: const Icon(Icons.call_outlined),
                                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone))),
                              if (email.isNotEmpty)
                                IconButton(
                                    tooltip: 'Email',
                                    icon: const Icon(Icons.mail_outline),
                                    onPressed: () => launchUrl(Uri(scheme: 'mailto', path: email))),
                            ]),
                            onTap: () => push(context, ContactFormScreen(contactId: str(c['id']))),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

class ContactFormScreen extends StatefulWidget {
  final String? contactId;
  final String? brandId;
  const ContactFormScreen({super.key, this.contactId, this.brandId});
  @override
  State<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends State<ContactFormScreen> {
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  List<Rec> _brands = [];
  String? _brandId;
  final name = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController(),
      role = TextEditingController(),
      instagram = TextEditingController(),
      company = TextEditingController(),
      notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _brands = await Repo.all('brands', orderBy: 'name COLLATE NOCASE');
    _brandId = widget.brandId;
    if (widget.contactId != null) {
      final c = await Repo.byId('contacts', widget.contactId!) ?? {};
      name.text = str(c['name']);
      email.text = str(c['email']);
      phone.text = str(c['phone']);
      role.text = str(c['role']);
      instagram.text = str(c['instagram']);
      company.text = str(c['company']);
      notes.text = str(c['notes']);
      _brandId = c['brand_id'] as String?;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await Repo.save('contacts', {
      'id': widget.contactId,
      'brand_id': _brandId,
      'name': name.text.trim(),
      'email': nn(email),
      'phone': nn(phone),
      'role': nn(role),
      'instagram': nn(instagram)?.replaceFirst('@', ''),
      'company': nn(company),
      'notes': nn(notes),
    });
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final used = await Repo.count('collabs', where: 'contact_id = ?', args: [widget.contactId]);
    if (!mounted) return;
    final msg = used > 0 ? 'This contact is linked to $used collab(s). The collabs are kept without a contact.' : 'This cannot be undone.';
    if (!await confirm(context, 'Delete contact?', msg)) return;
    await Repo.delete('contacts', widget.contactId!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.contactId == null ? 'New contact' : 'Contact'),
        actions: [
          if (widget.contactId != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
          TextButton(onPressed: _loading ? null : _save, child: const Text('Save')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                textField(name, 'Name', req: true),
                Pick(
                  label: 'Brand',
                  value: _brandId,
                  allowEmpty: true,
                  options: _brands.map((b) => str(b['id'])).toList(),
                  labels: {for (final b in _brands) str(b['id']): str(b['name'])},
                  onChanged: (v) => setState(() => _brandId = v),
                ),
                textField(role, 'Role', hint: 'Brand manager, agency, PR…'),
                textField(company, 'Company / agency'),
                textField(instagram, 'Instagram', hint: '@handle', keyboard: TextInputType.text),
                emailField(email),
                textField(phone, 'Phone', keyboard: TextInputType.phone),
                textField(notes, 'Notes', maxLines: 4, keyboard: TextInputType.multiline),
                if (widget.contactId != null)
                  const Text('Tip: tap call or email icons in the contacts list.', style: TextStyle(color: kMuted, fontSize: 12)),
              ]),
            ),
    );
  }
}
