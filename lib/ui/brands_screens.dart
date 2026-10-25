import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/repo.dart';
import '../core/snapshot.dart';
import 'collabs_screens.dart';
import 'contacts_screens.dart';
import 'products_screens.dart';
import 'widgets.dart';

class BrandsScreen extends StatefulWidget {
  const BrandsScreen({super.key});
  @override
  State<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends State<BrandsScreen> with AutoReload {
  Snapshot? _s;
  String _q = '';
  String _sort = 'Name';

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    var list = <Rec>[];
    final revenue = <String, double>{};
    final counts = <String, int>{};
    if (s != null) {
      for (final c in s.collabs) {
        final b = str(c.row['brand_id']);
        revenue[b] = (revenue[b] ?? 0.0) + c.received;
        counts[b] = (counts[b] ?? 0) + 1;
      }
      final q = _q.toLowerCase();
      list = s.brands
          .where((b) => q.isEmpty ||
              [b['name'], b['email'], b['phone'], b['website'], b['notes']].map(str).join(' ').toLowerCase().contains(q))
          .toList();
      if (_sort == 'Revenue') list.sort((a, b) => (revenue[str(b['id'])] ?? 0).compareTo(revenue[str(a['id'])] ?? 0));
      if (_sort == 'Collabs') list.sort((a, b) => (counts[str(b['id'])] ?? 0).compareTo(counts[str(a['id'])] ?? 0));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Brands'), actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort),
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) =>
              ['Name', 'Revenue', 'Collabs'].map((e) => CheckedPopupMenuItem(value: e, checked: _sort == e, child: Text(e))).toList(),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => push(context, const BrandFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Brand'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: deco('Search brands').copyWith(prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: s == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const EmptyState(icon: Icons.storefront_outlined, text: 'No brands yet.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final b = list[i];
                        final id = str(b['id']);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(child: Text(str(b['name']).isEmpty ? '?' : str(b['name'])[0].toUpperCase())),
                            title: Text(str(b['name'])),
                            subtitle: Text('${counts[id] ?? 0} collabs · ${money(revenue[id] ?? 0)} received'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => push(context, BrandDetailScreen(brandId: id)),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

class BrandFormScreen extends StatefulWidget {
  final String? brandId;
  const BrandFormScreen({super.key, this.brandId});
  @override
  State<BrandFormScreen> createState() => _BrandFormScreenState();
}

class _BrandFormScreenState extends State<BrandFormScreen> {
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  final name = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController(),
      website = TextEditingController(),
      gstin = TextEditingController(),
      address = TextEditingController(),
      notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.brandId != null) {
      final b = await Repo.byId('brands', widget.brandId!) ?? {};
      name.text = str(b['name']);
      email.text = str(b['email']);
      phone.text = str(b['phone']);
      website.text = str(b['website']);
      gstin.text = str(b['gstin']);
      address.text = str(b['address']);
      notes.text = str(b['notes']);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final dup = await Repo.all('brands',
        where: 'LOWER(name) = LOWER(?) AND id != ?', args: [name.text.trim(), widget.brandId ?? '']);
    if (dup.isNotEmpty && mounted) {
      final go = await confirm(context, 'Brand exists', 'A brand named "${name.text.trim()}" already exists. Save another?',
          ok: 'Save anyway', danger: false);
      if (!go) return;
    }
    final id = await Repo.save('brands', {
      'id': widget.brandId,
      'name': name.text.trim(),
      'email': nn(email),
      'phone': nn(phone),
      'website': nn(website),
      'gstin': nn(gstin)?.toUpperCase(),
      'address': nn(address),
      'notes': nn(notes),
    });
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.brandId == null ? 'New brand' : 'Edit brand'),
        actions: [TextButton(onPressed: _loading ? null : _save, child: const Text('Save'))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                textField(name, 'Brand name', req: true),
                emailField(email),
                textField(phone, 'Phone', keyboard: TextInputType.phone),
                urlField(website, 'Website'),
                textField(gstin, 'Brand GSTIN (for invoices)',
                    keyboard: TextInputType.visiblePassword,
                    validate: (t) => RegExp(r'^[0-9]{2}[A-Za-z0-9]{13}$').hasMatch(t) ? null : 'GSTIN is 15 characters'),
                textField(address, 'Billing address', maxLines: 3, keyboard: TextInputType.multiline),
                textField(notes, 'Notes', maxLines: 4, keyboard: TextInputType.multiline),
              ]),
            ),
    );
  }
}

class BrandDetailScreen extends StatefulWidget {
  final String brandId;
  const BrandDetailScreen({super.key, required this.brandId});
  @override
  State<BrandDetailScreen> createState() => _BrandDetailScreenState();
}

class _BrandDetailScreenState extends State<BrandDetailScreen> with AutoReload {
  Rec? _b;
  Snapshot? _s;
  bool _gone = false;

  @override
  Future<void> reload() async {
    final b = await Repo.byId('brands', widget.brandId);
    final s = await Snapshot.load();
    if (!mounted) return;
    setState(() {
      _b = b;
      _s = s;
      _gone = b == null;
    });
  }

  Future<void> _delete(List<CollabView> collabs) async {
    if (collabs.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Cannot delete brand'),
          content: Text('${collabs.length} collab(s) belong to this brand. Delete or move them first so no records are orphaned.'),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
        ),
      );
      return;
    }
    if (!await confirm(context, 'Delete brand?', 'Contacts and products stay, but will no longer be linked to this brand.')) return;
    await Repo.delete('brands', widget.brandId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.delete_outline, text: 'Brand deleted.'));
    final b = _b;
    final s = _s;
    if (b == null || s == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final collabs = s.collabs.where((c) => c.row['brand_id'] == widget.brandId).toList();
    final contacts = s.contacts.where((c) => c['brand_id'] == widget.brandId).toList();
    final products = s.products.where((p) => p['brand_id'] == widget.brandId).toList();
    final received = collabs.fold(0.0, (a, c) => a + c.received);
    final pending = collabs.fold(0.0, (a, c) => a + c.pending);
    return Scaffold(
      appBar: AppBar(title: Text(str(b['name'])), actions: [
        IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => push(context, BrandFormScreen(brandId: widget.brandId))),
        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(collabs)),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        StatGrid(children: [
          StatTile(label: 'Received', value: money(received)),
          StatTile(label: 'Pending', value: money(pending), color: pending > 0 ? kDanger : null),
        ]),
        SectionCard(
          title: 'Details',
          child: Column(children: [
            KV('Email', str(b['email'])),
            KV('Phone', str(b['phone'])),
            KV('Website', str(b['website']), onTap: isValidUrl(str(b['website'])) ? () => openUrl(context, str(b['website'])) : null),
            KV('GSTIN', str(b['gstin'])),
            KV('Address', str(b['address'])),
            KV('Notes', str(b['notes'])),
          ]),
        ),
        SectionCard(
          title: 'Collabs (${collabs.length})',
          trailing: TextButton(
              onPressed: () => push(context, CollabFormScreen(brandId: widget.brandId)), child: const Text('+ Add')),
          child: Column(
            children: collabs.isEmpty
                ? [const Text('No collabs yet.', style: TextStyle(color: kMuted))]
                : collabs.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: CollabCard(c: c))).toList(),
          ),
        ),
        SectionCard(
          title: 'Contacts (${contacts.length})',
          trailing: TextButton(
              onPressed: () => push(context, ContactFormScreen(brandId: widget.brandId)), child: const Text('+ Add')),
          child: Column(
            children: contacts
                .map((c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(str(c['name'])),
                      subtitle: Text([str(c['role']), str(c['email']), str(c['phone'])].where((x) => x.isNotEmpty).join(' · ')),
                      onTap: () => push(context, ContactFormScreen(contactId: str(c['id']))),
                    ))
                .toList(),
          ),
        ),
        SectionCard(
          title: 'Products (${products.length})',
          trailing: TextButton(
              onPressed: () => push(context, ProductFormScreen(brandId: widget.brandId)), child: const Text('+ Add')),
          child: Column(
            children: products
                .map((p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(str(p['name'])),
                      subtitle: Text(str(p['category'])),
                      onTap: () => push(context, ProductDetailScreen(productId: str(p['id']))),
                    ))
                .toList(),
          ),
        ),
      ]),
    );
  }
}
