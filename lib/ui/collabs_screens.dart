import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/repo.dart';
import '../core/snapshot.dart';
import 'brands_screens.dart';
import 'deliverable_screen.dart';
import 'invoice_screen.dart';
import 'products_screens.dart';
import 'widgets.dart';

// ======================= LIST =======================

class CollabsScreen extends StatefulWidget {
  final String? brandId;
  const CollabsScreen({super.key, this.brandId});
  @override
  State<CollabsScreen> createState() => _CollabsScreenState();
}

class _CollabsScreenState extends State<CollabsScreen> with AutoReload {
  Snapshot? _s;
  String _q = '';
  String _filter = 'Active';
  String _sort = 'Next action';
  static const _filters = ['Active', 'All', ...kAllStages, 'Unpaid', 'Overdue'];
  static const _sorts = ['Next action', 'Recently updated', 'Amount', 'Brand'];

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    if (mounted) setState(() => _s = s);
  }

  List<CollabView> _visible(Snapshot s) {
    final q = _q.toLowerCase();
    var l = s.collabs.where((c) {
      if (widget.brandId != null && c.row['brand_id'] != widget.brandId) return false;
      switch (_filter) {
        case 'Active':
          if (!c.active) return false;
          break;
        case 'All':
          break;
        case 'Unpaid':
          if (c.pending <= 0) return false;
          break;
        case 'Overdue':
          if (c.paymentStatus != 'Overdue') return false;
          break;
        default:
          if (c.stage != _filter) return false;
      }
      if (q.isEmpty) return true;
      final hay = [
        c.title, c.brandName, str(c.row['campaign']), c.stage, c.paymentStatus, str(c.row['notes']),
        ...c.deliverables.map((d) => '${str(d['live_link'])} ${str(d['draft_link'])} ${str(d['title'])}'),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
    switch (_sort) {
      case 'Recently updated':
        l.sort((a, b) => str(b.row['updated_at']).compareTo(str(a.row['updated_at'])));
        break;
      case 'Amount':
        l.sort((a, b) => b.agreed.compareTo(a.agreed));
        break;
      case 'Brand':
        l.sort((a, b) => a.brandName.toLowerCase().compareTo(b.brandName.toLowerCase()));
        break;
      default:
        String k(CollabView c) {
          final n = c.nextAction;
          return (n == null || n.$2.isEmpty) ? '9999' : n.$2;
        }
        l.sort((a, b) => k(a).compareTo(k(b)));
    }
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final list = s == null ? <CollabView>[] : _visible(s);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.brandId == null ? 'Collabs' : 'Brand collabs'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => _sorts.map((e) => CheckedPopupMenuItem(value: e, checked: e == _sort, child: Text(e))).toList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_collabs_${widget.brandId ?? 'all'}',
        onPressed: () => push(context, CollabFormScreen(brandId: widget.brandId)),
        icon: const Icon(Icons.add),
        label: const Text('New collab'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: deco('Search title, brand, status, reel link…').copyWith(prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _filters
                .map((f) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(label: Text(f), selected: f == _filter, onSelected: (_) => setState(() => _filter = f)),
                    ))
                .toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            Text('${list.length} collabs · ${money(list.fold<double>(0.0, (a, c) => a + c.agreed))}',
                style: const TextStyle(color: kMuted, fontSize: 12)),
            const Spacer(),
            Text('Sort: $_sort', style: const TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
        Expanded(
          child: s == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? EmptyState(
                      icon: Icons.handshake_outlined,
                      text: s.collabs.isEmpty ? 'No collabs yet. Add your first brand deal.' : 'No collabs match.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) => CollabCard(c: list[i]),
                    ),
        ),
      ]),
    );
  }
}

class CollabCard extends StatelessWidget {
  final CollabView c;
  const CollabCard({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final total = c.deliverables.length;
    final next = c.nextAction;
    final ps = c.paymentStatus;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => push(context, CollabDetailScreen(collabId: c.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text('${c.brandName} · ${c.dealType}',
                      style: const TextStyle(fontSize: 12, color: kMuted), overflow: TextOverflow.ellipsis)),
              Pill(c.stage, stageColor(c.stage)),
            ]),
            const SizedBox(height: 4),
            Text(c.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : c.liveCount / total,
                    minHeight: 6,
                    color: kOk,
                    backgroundColor: const Color(0xFFEEF0F3),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(total == 0 ? 'No deliverables' : '${c.liveCount}/$total live', style: const TextStyle(fontSize: 12)),
            ]),
            const Divider(height: 18),
            Row(children: [
              if (c.isBarter) ...[
                Icon(c.postedDate == null ? Icons.schedule : Icons.check_circle, size: 14,
                    color: c.postedDate == null ? kMuted : kOk),
                const SizedBox(width: 4),
                Text(c.postedDate == null ? 'Not posted yet' : 'Posted ${showDate(c.postedDate)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.postedDate == null ? kMuted : kOk)),
                if (c.barterValue > 0) Text(' · worth ${money(c.barterValue)}', style: const TextStyle(fontSize: 12, color: kMuted)),
              ] else ...[
                Text(money(c.agreed), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Text(ps == 'Paid' ? ps : '$ps · ${money(c.pending)} due',
                    style: TextStyle(fontSize: 12, color: paymentStatusColor(ps))),
              ],
              const Spacer(),
              if (next != null)
                Flexible(
                  child: Text(next.$2.isEmpty ? next.$1 : '${next.$1} · ${showDate(next.$2)}',
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: daysFromToday(next.$2) < 0 ? kDanger : null)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ======================= FORM =======================

class CollabFormScreen extends StatefulWidget {
  final String? collabId;
  final String? brandId;
  const CollabFormScreen({super.key, this.collabId, this.brandId});
  @override
  State<CollabFormScreen> createState() => _CollabFormScreenState();
}

class _CollabFormScreenState extends State<CollabFormScreen> {
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  Rec _row = {};
  List<Rec> _brands = [];
  List<Rec> _contacts = [];
  String? _brandId;
  String? _contactId;
  String _dealType = 'Paid';
  String _stage = 'Inquiry';
  String? _source;
  final title = TextEditingController(),
      campaign = TextEditingController(),
      agreed = TextEditingController(),
      barter = TextEditingController(),
      start = TextEditingController(),
      end = TextEditingController(),
      publish = TextEditingController(),
      payDue = TextEditingController(),
      terms = TextEditingController(),
      rights = TextEditingController(),
      exclusivity = TextEditingController(),
      renewal = TextEditingController(),
      nextAction = TextEditingController(),
      nextActionDate = TextEditingController(),
      links = TextEditingController(),
      notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _brands = await Repo.all('brands', orderBy: 'name COLLATE NOCASE');
    _contacts = await Repo.all('contacts', orderBy: 'name COLLATE NOCASE');
    if (widget.collabId != null) {
      _row = await Repo.byId('collabs', widget.collabId!) ?? {};
      _brandId = str(_row['brand_id']);
      _contactId = _row['contact_id'] as String?;
      _dealType = str(_row['deal_type']).isEmpty ? 'Paid' : str(_row['deal_type']);
      _stage = str(_row['stage']).isEmpty ? 'Inquiry' : str(_row['stage']);
      _source = _row['source'] as String?;
      title.text = str(_row['title']);
      campaign.text = str(_row['campaign']);
      agreed.text = numCtl(_row['agreed_amount']).text;
      barter.text = numCtl(_row['barter_value']).text;
      start.text = str(_row['start_date']);
      end.text = str(_row['end_date']);
      publish.text = str(_row['publish_date']);
      payDue.text = str(_row['payment_due_date']);
      terms.text = str(_row['payment_terms']);
      rights.text = str(_row['usage_rights_until']);
      exclusivity.text = str(_row['exclusivity_until']);
      renewal.text = str(_row['renewal_date']);
      nextAction.text = str(_row['next_action']);
      nextActionDate.text = str(_row['next_action_date']);
      links.text = str(_row['links']);
      notes.text = str(_row['notes']);
    } else {
      _brandId = widget.brandId;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addBrand() async {
    final id = await push<String>(context, const BrandFormScreen());
    if (id != null) {
      _brands = await Repo.all('brands', orderBy: 'name COLLATE NOCASE');
      setState(() => _brandId = id);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_brandId == null || _brandId!.isEmpty) {
      toast(context, 'Choose a brand');
      return;
    }
    final isNew = widget.collabId == null;
    final row = <String, dynamic>{
      'id': widget.collabId,
      'brand_id': _brandId,
      'contact_id': _contactId,
      'title': title.text.trim(),
      'campaign': nn(campaign),
      'deal_type': _dealType,
      'agreed_amount': toD(agreed.text),
      'barter_value': toD(barter.text),
      'stage': _stage,
      'source': _source,
      'start_date': nn(start),
      'end_date': nn(end),
      'publish_date': nn(publish),
      'payment_due_date': nn(payDue),
      'payment_terms': nn(terms),
      'usage_rights_until': nn(rights),
      'exclusivity_until': nn(exclusivity),
      'renewal_date': nn(renewal),
      'next_action': nn(nextAction),
      'next_action_date': nn(nextActionDate),
      'links': nn(links),
      'notes': nn(notes),
    };
    final id = await Repo.save('collabs', row);
    if (isNew) {
      await Repo.log(id, 'Collab created at stage $_stage');
    } else if (str(_row['agreed_amount']) != str(row['agreed_amount']) && toD(_row['agreed_amount']) != toD(row['agreed_amount'])) {
      await Repo.log(id, 'Agreed amount changed to ${money(toD(row['agreed_amount']))}');
    }
    Repo.notify();
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop(id);
    if (isNew) nav.push(MaterialPageRoute(builder: (_) => CollabDetailScreen(collabId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final contactsForBrand = _contacts.where((c) => _brandId == null || c['brand_id'] == null || c['brand_id'] == _brandId).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collabId == null ? 'New collab' : 'Edit collab'),
        actions: [TextButton(onPressed: _loading ? null : _save, child: const Text('Save'))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Pick(
                      label: 'Brand *',
                      value: _brandId,
                      options: _brands.map((b) => str(b['id'])).toList(),
                      labels: {for (final b in _brands) str(b['id']): str(b['name'])},
                      onChanged: (v) => setState(() {
                        _brandId = v;
                        _contactId = null;
                      }),
                    ),
                  ),
                  IconButton(onPressed: _addBrand, icon: const Icon(Icons.add_business_outlined), tooltip: 'New brand'),
                ]),
                Pick(
                  label: 'Contact',
                  value: _contactId,
                  allowEmpty: true,
                  options: contactsForBrand.map((c) => str(c['id'])).toList(),
                  labels: {for (final c in contactsForBrand) str(c['id']): str(c['name'])},
                  onChanged: (v) => setState(() => _contactId = v),
                ),
                textField(title, 'Collaboration title', req: true),
                textField(campaign, 'Campaign or product'),
                Pick(label: 'Deal type', value: _dealType, options: kDealTypes, onChanged: (v) => setState(() => _dealType = v ?? 'Paid')),
                moneyField(agreed, 'Agreed amount (₹)'),
                if (_dealType != 'Paid') moneyField(barter, 'Barter / product value (₹)'),
                if (widget.collabId == null)
                  Pick(label: 'Starting stage', value: _stage, options: kStages, onChanged: (v) => setState(() => _stage = v ?? 'Inquiry')),
                Pick(label: 'Source', value: _source, options: kSources, allowEmpty: true, onChanged: (v) => setState(() => _source = v)),
                const _Heading('Dates'),
                DateField(start, 'Campaign start'),
                DateField(end, 'Campaign end'),
                DateField(publish, 'Content publish date'),
                DateField(payDue, 'Payment due date'),
                textField(terms, 'Payment terms', hint: 'e.g. 50% advance, balance Net 30 after go-live'),
                const _Heading('Rights'),
                DateField(rights, 'Usage rights until'),
                DateField(exclusivity, 'Exclusivity until'),
                DateField(renewal, 'Renewal / follow-up date'),
                const _Heading('Next action'),
                textField(nextAction, 'Next action', hint: 'e.g. Send revised quote'),
                DateField(nextActionDate, 'Next action date'),
                const _Heading('More'),
                textField(links, 'Links (brief, drive folder, etc.)', maxLines: 4, keyboard: TextInputType.multiline),
                textField(notes, 'Notes', maxLines: 5, keyboard: TextInputType.multiline),
              ]),
            ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String t;
  const _Heading(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 0, 10),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, color: kMuted)),
      );
}

// ======================= DETAIL =======================

class CollabDetailScreen extends StatefulWidget {
  final String collabId;
  const CollabDetailScreen({super.key, required this.collabId});
  @override
  State<CollabDetailScreen> createState() => _CollabDetailScreenState();
}

class _CollabDetailScreenState extends State<CollabDetailScreen> with AutoReload {
  CollabView? _c;
  Rec? _brand;
  Rec? _contact;
  List<Rec> _activity = [];
  List<Rec> _products = [];
  Map<String, String> _productImage = {};
  Map<String, int> _productLinks = {};
  bool _gone = false;

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    final c = s.collab(widget.collabId);
    if (c == null) {
      if (mounted) setState(() => _gone = true);
      return;
    }
    final b = await Repo.byId('brands', str(c.row['brand_id']));
    final ct = str(c.row['contact_id']).isEmpty ? null : await Repo.byId('contacts', str(c.row['contact_id']));
    final act = await Repo.all('activity', where: 'collab_id = ?', args: [c.id], orderBy: 'created_at DESC');
    final prods = await Repo.all('products', where: 'collab_id = ?', args: [c.id], orderBy: 'name COLLATE NOCASE');
    final ids = prods.map((p) => str(p['id'])).toList();
    final img = <String, String>{};
    final links = <String, int>{};
    if (ids.isNotEmpty) {
      final marks = List.filled(ids.length, '?').join(',');
      for (final r in await Repo.all('product_images', where: 'product_id IN ($marks)', args: ids, orderBy: 'sort, created_at')) {
        img.putIfAbsent(str(r['product_id']), () => str(r['file_name']));
      }
      for (final r in await Repo.all('product_links', where: 'product_id IN ($marks)', args: ids)) {
        links[str(r['product_id'])] = (links[str(r['product_id'])] ?? 0) + 1;
      }
    }
    if (mounted) {
      setState(() {
        _c = c;
        _brand = b;
        _contact = ct;
        _activity = act;
        _products = prods;
        _productImage = img;
        _productLinks = links;
      });
    }
  }

  Future<void> _delete() async {
    final c = _c!;
    final ok = await confirm(context, 'Delete collab?',
        'This deletes "${c.title}" with its ${c.deliverables.length} deliverables, ${c.receipts.length} payments, invoices, expenses and timeline. Linked products are kept.');
    if (!ok) return;
    await Repo.delete('collabs', c.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.delete_outline, text: 'This collab was deleted.'));
    }
    final c = _c;
    if (c == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(c.title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => push(context, CollabFormScreen(collabId: c.id))),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete collab'))],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(118),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(children: [
                  Expanded(
                      child: Text('${c.brandName} · ${c.dealType}',
                          style: const TextStyle(color: kMuted, fontSize: 13), overflow: TextOverflow.ellipsis)),
                  TextButton.icon(
                    onPressed: () => showStageSheet(context, c),
                    icon: const Icon(Icons.swap_vert, size: 18),
                    label: Text(c.stage),
                    style: TextButton.styleFrom(foregroundColor: stageColor(c.stage)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: List.generate(kStages.length, (i) {
                    final si = stageIndex(c.stage);
                    final color = c.stage == kCancelled
                        ? kDanger.withOpacity(0.3)
                        : i < si
                            ? kOk
                            : i == si
                                ? stageColor(c.stage)
                                : const Color(0xFFE3E5EA);
                    return Expanded(
                      child: Container(
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                    );
                  }),
                ),
              ),
              const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Deliverables'),
                Tab(text: 'Money'),
                Tab(text: 'Timeline'),
              ]),
            ]),
          ),
        ),
        body: TabBarView(children: [
          _overview(c),
          _deliverables(c),
          _money(c),
          _timeline(),
        ]),
      ),
    );
  }

  // ---------- Overview ----------
  Widget _overview(CollabView c) {
    final next = c.nextAction;
    final contact = _contact;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (next != null)
        Card(
          color: const Color(0xFFFDF0E6),
          child: ListTile(
            title: Text(next.$2.isEmpty ? 'NEXT ACTION' : 'NEXT ACTION · ${showDate(next.$2)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF8A3A06), fontWeight: FontWeight.w700)),
            subtitle: Text(next.$1, style: const TextStyle(color: Colors.black87)),
            trailing: str(c.row['next_action']).isNotEmpty
                ? TextButton(
                    onPressed: () async {
                      await Repo.save('collabs', {'id': c.id, 'next_action': null, 'next_action_date': null});
                      await Repo.log(c.id, 'Done: ${str(c.row['next_action'])}');
                      Repo.notify();
                    },
                    child: const Text('Done'))
                : null,
          ),
        ),
      SectionCard(
        title: 'Deal',
        child: Column(children: [
          if (c.isBarter)
            Row(children: [
              Expanded(child: _money3('Product value', money(c.barterValue), const Color(0xFFF3F4F6))),
              const SizedBox(width: 8),
              Expanded(
                  child: _money3('Reel posted', c.postedDate == null ? 'Not yet' : showDate(c.postedDate),
                      c.postedDate == null ? const Color(0xFFFDF0E6) : const Color(0xFFE5F4EC))),
              const SizedBox(width: 8),
              Expanded(
                  child: _money3('Live', '${c.liveCount} / ${c.deliverables.length}', const Color(0xFFE8ECFC))),
            ])
          else
            Row(children: [
              Expanded(child: _money3('Agreed', money(c.agreed), const Color(0xFFF3F4F6))),
              const SizedBox(width: 8),
              Expanded(child: _money3('Received', money(c.received), const Color(0xFFE5F4EC))),
              const SizedBox(width: 8),
              Expanded(child: _money3('Pending', money(c.pending), const Color(0xFFFCEBEA))),
            ]),
          const SizedBox(height: 8),
          if (!c.isBarter) KV('Payment status', c.paymentStatus),
          if (!c.isBarter) KV('Reel posted', c.postedDate == null ? 'Not yet' : showDate(c.postedDate)),
          KV('Campaign', str(c.row['campaign'])),
          if (c.barterValue > 0) KV('Barter value', money(c.barterValue)),
          KV('Source', str(c.row['source'])),
          KV('Campaign window', _range(c.row['start_date'], c.row['end_date'])),
          KV('Publish date', showDate(c.row['publish_date'])),
          KV('Payment due', showDate(c.dueDate)),
          KV('Payment terms', str(c.row['payment_terms'])),
          KV('Usage rights until', showDate(c.row['usage_rights_until'])),
          KV('Exclusivity until', showDate(c.row['exclusivity_until'])),
          KV('Renewal date', showDate(c.row['renewal_date'])),
          if (c.stage == kCancelled) KV('Cancel reason', str(c.row['cancel_reason'])),
        ]),
      ),
      SectionCard(
        title: 'Products${_products.isEmpty ? '' : ' (${_products.length})'}',
        trailing: TextButton(
            onPressed: () => push(context, ProductFormScreen(brandId: str(c.row['brand_id']), collabId: c.id)),
            child: const Text('+ Add')),
        child: _products.isEmpty
            ? const Text('No products yet. Tap + Add and paste a product link to auto-fill image, name and price.',
                style: TextStyle(color: kMuted))
            : Column(
                children: _products
                    .map((p) => ProductTile(
                          product: p,
                          imageFile: _productImage[str(p['id'])],
                          linkCount: _productLinks[str(p['id'])] ?? 0,
                        ))
                    .toList()),
      ),
      SectionCard(
        title: 'People',
        child: Column(children: [
          KV('Brand', str(_brand?['name']), onTap: _brand == null ? null : () => push(context, BrandDetailScreen(brandId: str(_brand!['id'])))),
          if (contact != null) ...[
            KV('Contact', '${str(contact['name'])}${str(contact['role']).isEmpty ? '' : ' · ${str(contact['role'])}'}'),
            KV('Email', str(contact['email'])),
            KV('Phone', str(contact['phone'])),
          ],
        ]),
      ),
      if (str(c.row['links']).isNotEmpty)
        SectionCard(
          title: 'Links',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: str(c.row['links'])
                .split(RegExp(r'\s+'))
                .where((l) => l.isNotEmpty)
                .map((l) => InkWell(
                      onTap: isValidUrl(l) ? () => openUrl(context, l) : null,
                      onLongPress: () => copyText(context, l),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(l, style: TextStyle(color: isValidUrl(l) ? kPrimary : null)),
                      ),
                    ))
                .toList(),
          ),
        ),
      if (str(c.row['notes']).isNotEmpty) SectionCard(title: 'Notes', child: Text(str(c.row['notes']))),
    ]);
  }

  String _range(Object? a, Object? b) {
    if (str(a).isEmpty && str(b).isEmpty) return '';
    return '${showDate(a)} → ${showDate(b)}';
  }

  Widget _money3(String k, String v, Color bg) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 11, color: kMuted)),
          FittedBox(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
        ]),
      );

  // ---------- Deliverables ----------
  Widget _deliverables(CollabView c) {
    return Stack(children: [
      c.deliverables.isEmpty
          ? const EmptyState(icon: Icons.movie_outlined, text: 'No deliverables yet.\nAdd each reel, story or post you owe.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: c.deliverables.map((d) {
                final st = str(d['status']);
                final live = str(d['live_link']);
                final draft = str(d['draft_link']);
                final m = Snapshot.bestMetric(c.metricsFor(str(d['id']))) ??
                    (c.metricsFor(str(d['id'])).isEmpty ? null : c.metricsFor(str(d['id'])).last);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => push(context, DeliverableScreen(collabId: c.id, deliverableId: str(d['id']))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                                '${str(d['type'])} · ${str(d['platform'])}${str(d['title']).isEmpty ? '' : ' · ${str(d['title'])}'}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          Pill(st == 'Revision' ? 'Revision ${toI(d['revision_count'])}' : st, deliverableStatusColor(st)),
                        ]),
                        const SizedBox(height: 4),
                        Text('Due ${showDate(d['due_date'])} · go-live ${showDate(d['live_date'])}',
                            style: const TextStyle(fontSize: 12, color: kMuted)),
                        if (live.isNotEmpty || draft.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [
                              Icon(Icons.link, size: 16, color: live.isNotEmpty ? kPrimary : kMuted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(live.isNotEmpty ? live : 'Draft: $draft',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: live.isNotEmpty ? kPrimary : kMuted)),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.open_in_new, size: 18),
                                tooltip: 'Open',
                                onPressed: () => openUrl(context, live.isNotEmpty ? live : draft),
                              ),
                            ]),
                          ),
                        ],
                        if (m != null) ...[
                          const SizedBox(height: 6),
                          Text(
                              '${str(m['label'])}: ${plainNum(toI(m['views']))} views · ${plainNum(toI(m['likes']))} likes · ${plainNum(toI(m['comments']))} comments',
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ]),
                    ),
                  ),
                );
              }).toList(),
            ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'add_deliverable',
          onPressed: () => push(context, DeliverableScreen(collabId: c.id)),
          icon: const Icon(Icons.add),
          label: const Text('Deliverable'),
        ),
      ),
    ]);
  }

  // ---------- Money ----------
  Widget _money(CollabView c) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(
        title: 'Payments received',
        trailing: TextButton(onPressed: () => receiptDialog(context, c), child: const Text('+ Record')),
        child: Column(children: [
          if (c.receipts.isEmpty) const Text('No payments recorded.', style: TextStyle(color: kMuted)),
          ...c.receipts.map((r) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(money(toD(r['amount']))),
                subtitle: Text([
                  showDate(r['received_date']),
                  if (str(r['method']).isNotEmpty) str(r['method']),
                  if (toD(r['tds']) > 0) 'TDS ${money(toD(r['tds']))}',
                  if (str(r['reference']).isNotEmpty) str(r['reference']),
                ].join(' · ')),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => receiptDialog(context, c, existing: r),
                ),
              )),
          const Divider(),
          KV('Agreed', money(c.agreed)),
          KV('Credited', money(c.netReceived)),
          KV('TDS deducted', c.tds > 0 ? money(c.tds) : ''),
          KV('Pending', money(c.pending)),
        ]),
      ),
      SectionCard(
        title: 'Invoices',
        trailing: TextButton(
            onPressed: () => push(context, InvoiceScreen(collabId: c.id)), child: const Text('+ Create')),
        child: Column(children: [
          if (c.invoices.isEmpty) const Text('No invoices yet.', style: TextStyle(color: kMuted)),
          ...c.invoices.map((i) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(str(i['number'])),
                subtitle: Text('${showDate(i['invoice_date'])} · ${money(toD(i['total']))}'),
                trailing: Pill(str(i['status']), str(i['status']) == 'Paid' ? kOk : kMuted),
                onTap: () => push(context, InvoiceScreen(collabId: c.id, invoiceId: str(i['id']))),
              )),
        ]),
      ),
      SectionCard(
        title: 'Expenses',
        trailing: TextButton(onPressed: () => expenseDialog(context, c.id), child: const Text('+ Add')),
        child: Column(children: [
          if (c.expenses.isEmpty) const Text('No expenses.', style: TextStyle(color: kMuted)),
          ...c.expenses.map((e) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${str(e['category'])} · ${money(toD(e['amount']))}'),
                subtitle: Text([showDate(e['date']), str(e['notes'])].where((x) => x.isNotEmpty && x != '—').join(' · ')),
                trailing: IconButton(
                    icon: const Icon(Icons.more_vert), onPressed: () => expenseDialog(context, c.id, existing: e)),
              )),
        ]),
      ),
      SectionCard(
        title: 'Collab P&L',
        child: Column(children: [
          KV('Fee settled', money(c.received)),
          KV('Barter value', c.barterValue > 0 ? money(c.barterValue) : ''),
          KV('Expenses', '- ${money(c.expenseTotal)}'),
          KV('Net profit', money(c.profit)),
          const SizedBox(height: 6),
          const Text('Barter goods may attract TDS under 194R. Not tax advice — confirm with your CA.',
              style: TextStyle(fontSize: 11, color: kMuted)),
        ]),
      ),
      if (c.pending > 0)
        SectionCard(
          title: 'Payment reminder',
          child: Column(children: [
            for (final t in _reminders(c))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.$1),
                subtitle: Text(t.$2, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.share_outlined),
                onTap: () => Share.share(t.$2),
              ),
          ]),
        ),
    ]);
  }

  List<(String, String)> _reminders(CollabView c) {
    final who = str(_contact?['name']).isEmpty ? 'there' : str(_contact?['name']).split(' ').first;
    final inv = c.invoices.isEmpty ? '' : ' (invoice ${str(c.invoices.first['number'])})';
    final due = c.dueDate == null ? '' : ' due on ${showDate(c.dueDate)}';
    final amt = money(c.pending);
    return [
      ('Friendly nudge',
          'Hi $who, hope you are well! Just a gentle reminder about the payment of $amt for "${c.title}"$inv$due. Please let me know if you need anything from my side.'),
      ('Overdue follow-up',
          'Hi $who, following up on the pending payment of $amt for "${c.title}"$inv, which was$due. Could you share an expected payment date?'),
      ('Final reminder',
          'Hi $who, the payment of $amt for "${c.title}"$inv is now significantly overdue. Please process it at the earliest, or let me know if there is an issue I can help resolve.'),
    ];
  }

  // ---------- Timeline ----------
  Widget _timeline() {
    if (_activity.isEmpty) return const EmptyState(icon: Icons.timeline, text: 'No activity yet.');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _activity.length,
      itemBuilder: (_, i) {
        final a = _activity[i];
        final dt = DateTime.tryParse(str(a['created_at']));
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.circle, size: 10, color: kPrimary),
          minLeadingWidth: 12,
          title: Text(str(a['message'])),
          subtitle: Text(dt == null ? '' : '${showDate(isoDate(dt))} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'),
        );
      },
    );
  }
}

// ======================= STAGE CHANGE =======================

List<String> stageGateIssues(CollabView c, String target) {
  final issues = <String>[];
  final ti = stageIndex(target);
  if (ti >= stageIndex('Contract') && c.agreed <= 0 && c.dealType != 'Barter') issues.add('Agreed amount is not set');
  if (ti >= stageIndex('Review') && c.deliverables.isEmpty) issues.add('No deliverables added');
  if (ti >= stageIndex('Live') && c.approvedOrLive < c.deliverables.length) {
    issues.add('${c.deliverables.length - c.approvedOrLive} deliverable(s) not approved yet');
  }
  if (ti >= stageIndex('Performance')) {
    final missing = c.deliverables.where((d) => str(d['live_link']).isEmpty).length;
    if (missing > 0) issues.add('$missing deliverable(s) missing live link');
  }
  if (ti >= stageIndex('Payment')) {
    final noMetrics = c.deliverables.where((d) => c.metricsFor(str(d['id'])).isEmpty).length;
    if (noMetrics > 0) issues.add('$noMetrics deliverable(s) without performance metrics');
  }
  if (target == 'Closed' && c.pending > 0) issues.add('${money(c.pending)} still pending');
  return issues;
}

Future<void> showStageSheet(BuildContext context, CollabView c) async {
  final target = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Move to stage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        ...kAllStages.map((st) {
          final issues = st == kCancelled ? <String>[] : stageGateIssues(c, st);
          return ListTile(
            leading: Icon(st == c.stage ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: stageColor(st)),
            title: Text(st),
            subtitle: issues.isEmpty ? null : Text(issues.join(' · '), style: const TextStyle(color: kWarn, fontSize: 12)),
            enabled: st != c.stage,
            onTap: () => Navigator.pop(ctx, st),
          );
        }),
      ]),
    ),
  );
  if (target == null || !context.mounted) return;
  String? reason;
  if (target == kCancelled) {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Cancel collab'),
        content: TextField(controller: ctrl, decoration: deco('Reason *'), maxLines: 3, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(d, ctrl.text.trim().isNotEmpty), child: const Text('Cancel collab')),
        ],
      ),
    );
    if (ok != true) return;
    reason = ctrl.text.trim();
  } else {
    final issues = stageGateIssues(c, target);
    if (issues.isNotEmpty) {
      if (!context.mounted) return;
      final go = await confirm(context, 'Checklist not complete', '${issues.join('\n')}\n\nMove to $target anyway?',
          ok: 'Move anyway', danger: false);
      if (!go) return;
    }
  }
  await Repo.save('collabs', {
    'id': c.id,
    'stage': target,
    if (target == kCancelled) 'cancel_reason': reason,
    if (target == kCancelled) 'cancelled_from': c.stage,
  });
  await Repo.log(c.id, target == kCancelled ? 'Cancelled at ${c.stage}: $reason' : 'Stage: ${c.stage} → $target');
  Repo.notify();
}

// ======================= DIALOGS =======================

Future<void> receiptDialog(BuildContext context, CollabView c, {Rec? existing}) async {
  final form = GlobalKey<FormState>();
  final amount = numCtl(existing?['amount']);
  final tds = numCtl(existing?['tds']);
  final date = ctl(existing?['received_date'] ?? todayIso());
  final ref = ctl(existing?['reference']);
  final notes = ctl(existing?['notes']);
  String? method = existing?['method'] as String?;
  final res = await showDialog<String>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(existing == null ? 'Record payment' : 'Edit payment'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Pending ${money(c.pending)}', style: const TextStyle(color: kMuted)),
              const Gap(),
              moneyField(amount, 'Amount credited (₹)', req: true),
              moneyField(tds, 'TDS deducted (₹)'),
              DateField(date, 'Received on'),
              Pick(label: 'Method', value: method, options: kPaymentMethods, allowEmpty: true, onChanged: (v) => set(() => method = v)),
              textField(ref, 'Reference / UTR'),
              textField(notes, 'Notes'),
            ]),
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(onPressed: () => Navigator.pop(d, 'delete'), child: const Text('Delete', style: TextStyle(color: kDanger))),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                if (toD(amount.text) <= 0) return;
                Navigator.pop(d, 'save');
              },
              child: const Text('Save')),
        ],
      ),
    ),
  );
  if (res == 'delete' && existing != null) {
    if (!context.mounted) return;
    if (await confirm(context, 'Delete payment?', 'Remove ${money(toD(existing['amount']))} received on ${showDate(existing['received_date'])}?')) {
      await Repo.delete('payments', str(existing['id']));
      await Repo.log(c.id, 'Payment of ${money(toD(existing['amount']))} deleted');
      Repo.notify();
    }
  } else if (res == 'save') {
    await Repo.save('payments', {
      'id': existing?['id'],
      'collab_id': c.id,
      'amount': toD(amount.text),
      'tds': toD(tds.text),
      'received_date': date.text.isEmpty ? todayIso() : date.text,
      'method': method,
      'reference': nn(ref),
      'notes': nn(notes),
    });
    await Repo.log(c.id, '${existing == null ? 'Payment received' : 'Payment edited'}: ${money(toD(amount.text))}');
    Repo.notify();
  }
}

Future<void> expenseDialog(BuildContext context, String collabId, {Rec? existing}) async {
  final form = GlobalKey<FormState>();
  final amount = numCtl(existing?['amount']);
  final date = ctl(existing?['date'] ?? todayIso());
  final notes = ctl(existing?['notes']);
  String category = str(existing?['category']).isEmpty ? kExpenseCategories.first : str(existing?['category']);
  final res = await showDialog<String>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(existing == null ? 'Add expense' : 'Edit expense'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Pick(label: 'Category', value: category, options: kExpenseCategories, onChanged: (v) => set(() => category = v ?? category)),
              moneyField(amount, 'Amount (₹)', req: true),
              DateField(date, 'Date'),
              textField(notes, 'Notes'),
            ]),
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(onPressed: () => Navigator.pop(d, 'delete'), child: const Text('Delete', style: TextStyle(color: kDanger))),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(d, 'save');
              },
              child: const Text('Save')),
        ],
      ),
    ),
  );
  if (res == 'delete' && existing != null) {
    await Repo.delete('expenses', str(existing['id']));
  } else if (res == 'save') {
    await Repo.save('expenses', {
      'id': existing?['id'],
      'collab_id': collabId,
      'category': category,
      'amount': toD(amount.text),
      'date': nn(date),
      'notes': nn(notes),
    });
  }
}
