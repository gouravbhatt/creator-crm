import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/repo.dart';
import '../core/snapshot.dart';
import 'brands_screens.dart';
import 'collabs_screens.dart';
import 'contacts_screens.dart';
import 'products_screens.dart';
import 'widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with AutoReload {
  Snapshot? _s;
  List<Rec> _links = [];
  String _q = '';

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    final links = await Repo.all('product_links');
    if (mounted) {
      setState(() {
        _s = s;
        _links = links;
      });
    }
  }

  bool _m(List<Object?> fields) => fields.map(str).join(' ').toLowerCase().contains(_q);

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final results = <Widget>[];
    if (s != null && _q.length >= 2) {
      void section(String title, List<Widget> items) {
        if (items.isEmpty) return;
        results.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text('$title (${items.length})', style: const TextStyle(fontWeight: FontWeight.w600, color: kMuted)),
        ));
        results.add(Card(child: Column(children: items)));
      }

      section(
          'Collabs',
          s.collabs
              .where((c) => _m([c.title, c.brandName, c.row['campaign'], c.stage, c.paymentStatus, c.row['notes']]))
              .map((c) => ListTile(
                    title: Text(c.title),
                    subtitle: Text('${c.brandName} · ${c.stage} · ${c.paymentStatus}'),
                    onTap: () => push(context, CollabDetailScreen(collabId: c.id)),
                  ))
              .toList());
      section(
          'Deliverables & reel links',
          s.deliverables
              .where((d) => _m([d['type'], d['title'], d['status'], d['live_link'], d['draft_link']]))
              .map((d) => ListTile(
                    title: Text('${str(d['type'])} · ${str(d['status'])}'),
                    subtitle: Text(
                        '${s.collabTitle(str(d['collab_id']))}\n${str(d['live_link']).isEmpty ? str(d['draft_link']) : str(d['live_link'])}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    onTap: () => push(context, CollabDetailScreen(collabId: str(d['collab_id']))),
                  ))
              .toList());
      section(
          'Brands',
          s.brands
              .where((b) => _m([b['name'], b['email'], b['phone'], b['website']]))
              .map((b) => ListTile(
                    title: Text(str(b['name'])),
                    subtitle: Text(str(b['email'])),
                    onTap: () => push(context, BrandDetailScreen(brandId: str(b['id']))),
                  ))
              .toList());
      section(
          'Contacts',
          s.contacts
              .where((c) => _m([c['name'], c['email'], c['phone'], c['role'], s.brandNames[str(c['brand_id'])]]))
              .map((c) => ListTile(
                    title: Text(str(c['name'])),
                    subtitle: Text([s.brandNames[str(c['brand_id'])] ?? '', str(c['role'])].where((x) => x.isNotEmpty).join(' · ')),
                    onTap: () => push(context, ContactFormScreen(contactId: str(c['id']))),
                  ))
              .toList());
      final pn = {for (final p in s.products) str(p['id']): str(p['name'])};
      final linkHits = _links.where((l) => _m([l['url'], l['title'], l['link_type']])).map((l) => str(l['product_id'])).toSet();
      section(
          'Products',
          s.products
              .where((p) => linkHits.contains(str(p['id'])) || _m([p['name'], p['category'], p['description'], s.brandNames[str(p['brand_id'])]]))
              .map((p) => ListTile(
                    title: Text(pn[str(p['id'])] ?? ''),
                    subtitle: Text(linkHits.contains(str(p['id'])) ? 'Matched a product link' : str(p['category'])),
                    onTap: () => push(context, ProductDetailScreen(productId: str(p['id']))),
                  ))
              .toList());
      section(
          'Payments',
          s.receipts
              .where((r) => _m([r['reference'], r['method'], r['notes'], s.collabTitle(str(r['collab_id']))]))
              .map((r) => ListTile(
                    title: Text(money(toD(r['amount']))),
                    subtitle: Text('${showDate(r['received_date'])} · ${s.collabTitle(str(r['collab_id']))}'),
                    onTap: () => push(context, CollabDetailScreen(collabId: str(r['collab_id']))),
                  ))
              .toList());
    }
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search everything', border: InputBorder.none, filled: false),
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
        ),
      ),
      body: _q.length < 2
          ? const EmptyState(icon: Icons.search, text: 'Search brands, contacts, collabs, status, reel links, products and payments.')
          : results.isEmpty
              ? const EmptyState(icon: Icons.search_off, text: 'No matches.')
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: results),
    );
  }
}
