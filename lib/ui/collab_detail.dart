import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/repo.dart';
import '../core/snapshot.dart';
import 'brands_screens.dart';
import 'collab_dialogs.dart';
import 'collab_form.dart';
import 'deliverable_screen.dart';
import 'invoice_screen.dart';
import 'products_screens.dart';
import 'v2_widgets.dart';
import 'widgets.dart';

class CollabDetailScreen extends StatefulWidget {
  final String collabId;
  const CollabDetailScreen({super.key, required this.collabId});
  @override
  State<CollabDetailScreen> createState() => _CollabDetailScreenState();
}

class _CollabDetailScreenState extends State<CollabDetailScreen> with AutoReload {
  CollabView? _c;
  Snapshot? _s;
  Rec? _contact;
  List<Rec> _activity = [];
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
    final ct = str(c.row['contact_id']).isEmpty ? null : await Repo.byId('contacts', str(c.row['contact_id']));
    final act = await Repo.all('activity', where: 'collab_id = ?', args: [c.id], orderBy: 'created_at DESC');
    final links = <String, int>{};
    if (c.products.isNotEmpty) {
      final ids = c.products.map((p) => str(p['id'])).toList();
      final marks = List.filled(ids.length, '?').join(',');
      for (final r in await Repo.all('product_links', where: 'product_id IN ($marks)', args: ids)) {
        links[str(r['product_id'])] = (links[str(r['product_id'])] ?? 0) + 1;
      }
    }
    if (mounted) {
      setState(() {
        _c = c;
        _s = s;
        _contact = ct;
        _activity = act;
        _productLinks = links;
      });
    }
  }

  Future<void> _delete() async {
    final c = _c!;
    final ok = await confirm(context, 'Delete collab?',
        'Deletes "${c.title}" with its ${c.deliverables.length} posts, ${c.receipts.length} payments, invoices and timeline. Products stay in your Products list.');
    if (!ok) return;
    await Repo.delete('collabs', c.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.delete_outline, text: 'This collab was deleted.'));
    final c = _c;
    if (c == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: reload,
        child: ListView(padding: EdgeInsets.zero, children: [
          _hero(c),
          Transform.translate(
            offset: const Offset(0, -28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _headerCard(c),
                const SizedBox(height: 12),
                _valueTiles(c),
                const SizedBox(height: 12),
                if (c.nextAction != null && c.active) _nextAction(c),
                _posts(c),
                if (c.hasBarter || c.products.isNotEmpty) _productsPanel(c),
                if (c.hasCash) _paymentPanel(c),
                _actions(c),
                const SizedBox(height: 12),
                _fold('Expenses & profit', '${money(c.profit)} net', _expenses(c)),
                if (c.invoices.isNotEmpty) _fold('Invoices', '${c.invoices.length}', _invoices(c)),
                _fold('Details', str(_contact?['name']), _details(c)),
                _fold('Timeline', '${_activity.length} events', _timeline()),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _hero(CollabView c) {
    final top = MediaQuery.of(context).padding.top;
    Widget roundBtn(IconData i, String tip, VoidCallback onTap) => Material(
          color: Colors.white.withOpacity(0.92),
          shape: const CircleBorder(),
          child: IconButton(icon: Icon(i, color: kInk), tooltip: tip, onPressed: onTap),
        );
    return SizedBox(
      height: 250 + top,
      child: Stack(fit: StackFit.expand, children: [
        Container(color: typeTint(c.dealType)),
        if (c.coverImage != null)
          ProductThumb(fileName: c.coverImage, type: c.dealType, size: MediaQuery.of(context).size.width, radius: 0)
        else
          Center(child: Icon(c.hasBarter ? Icons.inventory_2_outlined : Icons.campaign_outlined, size: 84, color: typeColor(c.dealType))),
        Positioned(left: 12, top: top + 8, child: roundBtn(Icons.arrow_back, 'Back', () => Navigator.pop(context))),
        Positioned(
          right: 12,
          top: top + 8,
          child: Row(children: [
            roundBtn(Icons.edit_outlined, 'Edit', () => push(context, CollabFormScreen(collabId: c.id))),
            const SizedBox(width: 8),
            Material(
              color: Colors.white.withOpacity(0.92),
              shape: const CircleBorder(),
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: kInk),
                onSelected: (v) {
                  if (v == 'delete') _delete();
                  if (v == 'cancel') showStageSheet(context, c, preselect: kCancelled);
                },
                itemBuilder: (_) => [
                  if (c.stage != kCancelled) const PopupMenuItem(value: 'cancel', child: Text('Cancel collab')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete collab')),
                ],
              ),
            ),
          ]),
        ),
        if (c.products.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xB317142B), borderRadius: BorderRadius.circular(10)),
              child: Text('${c.products.length} product${c.products.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
      ]),
    );
  }

  Widget _headerCard(CollabView c) {
    final si = stageIndex(c.stage);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x0F17142B), blurRadius: 20, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          InkWell(
            onTap: () => push(context, BrandDetailScreen(brandId: str(c.row['brand_id']))),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: kPrimaryTint, borderRadius: BorderRadius.circular(8)),
                child: Text(c.brandName.isEmpty ? '?' : c.brandName[0].toUpperCase(),
                    style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Text(c.brandName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3B3753))),
            ]),
          ),
          const Spacer(),
          TypeBadge(c.dealType),
        ]),
        const SizedBox(height: 10),
        Text(c.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(height: 12),
        if (c.stage == kCancelled)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFCEBEA), borderRadius: BorderRadius.circular(12)),
            child: Text('Cancelled${str(c.row['cancel_reason']).isEmpty ? '' : ': ${str(c.row['cancel_reason'])}'}',
                style: const TextStyle(color: kDanger, fontWeight: FontWeight.w600)),
          )
        else
          InkWell(
            onTap: () => showStageSheet(context, c),
            child: Row(
              children: List.generate(kStages.length, (i) {
                final color = i < si ? kOk : (i == si ? kPrimary : kLine);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(height: 6, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(height: 5),
                      Text(kStages[i],
                          style: TextStyle(
                              fontSize: 10,
                              color: i == si ? kPrimary : kMuted,
                              fontWeight: i == si ? FontWeight.w800 : FontWeight.w500)),
                    ]),
                  ),
                );
              }),
            ),
          ),
        if (c.stage != kCancelled)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Tap the bar to change stage', style: TextStyle(fontSize: 10, color: kMuted)),
          ),
      ]),
    );
  }

  Widget _tile(String k, String v, String sub, Color bg, Color fg, {bool dark = false}) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: TextStyle(fontSize: 11, color: fg)),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: dark ? Colors.white : kInk))),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: fg)),
          ]),
        ),
      );

  Widget _valueTiles(CollabView c) {
    final tiles = <Widget>[];
    if (c.hasCash) {
      tiles.add(_tile('Cash', money(c.agreed), '${money(c.received)} received', kPrimaryTint, const Color(0xFF3F2A9E)));
    }
    if (c.hasBarter) {
      final posted = c.postedDate;
      tiles.add(_tile('Barter', money(c.barterValue), posted == null ? '${c.products.length} product(s)' : 'Posted ${showDate(posted)}',
          kBarterTint, const Color(0xFFA3194E)));
    }
    tiles.add(_tile('Total', money(c.totalValue), 'net ${money(c.profit)}', kInk, const Color(0xFFC9C5DC), dark: true));
    final out = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) out.add(const SizedBox(width: 8));
      out.add(tiles[i]);
    }
    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: out));
  }

  Widget _nextAction(CollabView c) {
    final n = c.nextAction!;
    final overdue = n.$2.isNotEmpty && daysFromToday(n.$2) < 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(color: overdue ? const Color(0xFFFCEBEA) : kWarnTint, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Icons.flag_outlined, color: overdue ? kDanger : kWarn),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.$2.isEmpty ? 'NEXT' : 'NEXT · ${showDate(n.$2)}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: overdue ? kDanger : kWarn)),
            Text(n.$1, style: const TextStyle(fontSize: 13)),
          ]),
        ),
        if (str(c.row['next_action']).isNotEmpty)
          TextButton(
            onPressed: () async {
              await Repo.save('collabs', {'id': c.id, 'next_action': null, 'next_action_date': null});
              await Repo.log(c.id, 'Done: ${str(c.row['next_action'])}');
              Repo.notify();
            },
            child: const Text('Done'),
          ),
      ]),
    );
  }

  Widget _posts(CollabView c) {
    return Panel(
      title: 'Reels & posts',
      trailing: TextButton(onPressed: () => push(context, DeliverableScreen(collabId: c.id)), child: const Text('+ Add')),
      child: Column(children: [
        if (c.deliverables.isEmpty) const Text('Nothing to post added yet.', style: TextStyle(color: kMuted)),
        for (final d in c.deliverables) ...[
          _postCard(c, d),
          const SizedBox(height: 8),
        ],
      ]),
    );
  }

  Widget _postCard(CollabView c, Rec d) {
    final st = str(d['status']);
    final live = str(d['live_link']);
    final draft = str(d['draft_link']);
    final isLive = st == 'Live';
    final ms = c.metricsFor(str(d['id']));
    final m = Snapshot.bestMetric(ms) ?? (ms.isEmpty ? null : ms.last);
    final name = '${str(d['type'])}${str(d['title']).isEmpty ? '' : ' ${str(d['title'])}'} · ${str(d['platform'])}';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => push(context, DeliverableScreen(collabId: c.id, deliverableId: str(d['id']))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: kLine), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            Pill(isLive ? 'Posted' : (st == 'Revision' ? 'Revision ${toI(d['revision_count'])}' : st), deliverableStatusColor(st)),
            SizedBox(
              width: 36,
              height: 32,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert, size: 20),
                tooltip: 'Post options',
                onSelected: (v) => _postAction(c, d, v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit / change type'), dense: true)),
                  if (!isLive)
                    const PopupMenuItem(value: 'live', child: ListTile(leading: Icon(Icons.check_circle_outline), title: Text('Mark as posted'), dense: true)),
                  const PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy_outlined), title: Text('Add one more like this'), dense: true)),
                  const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(leading: Icon(Icons.delete_outline, color: kDanger), title: Text('Delete', style: TextStyle(color: kDanger)), dense: true)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.link, size: 16, color: live.isNotEmpty ? kPrimary : kMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(live.isNotEmpty ? live : (draft.isNotEmpty ? 'Draft: $draft' : 'Paste live link after posting'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: live.isNotEmpty ? kPrimary : kMuted)),
              ),
              TextButton(
                onPressed: () => live.isNotEmpty
                    ? openUrl(context, live)
                    : push(context, DeliverableScreen(collabId: c.id, deliverableId: str(d['id']))),
                child: Text(live.isNotEmpty ? 'Open' : 'Add'),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text(isLive ? 'Posted ${showDate(d['live_date'])}' : 'Post by ${showDate(d['due_date'])}',
                style: TextStyle(fontSize: 12, color: isLive ? kBothC : const Color(0xFF3B3753), fontWeight: FontWeight.w600)),
            const Spacer(),
            if (m != null)
              Text('${str(m['label'])}: ${plainNum(toI(m['views']))} views · ${plainNum(toI(m['likes']))} likes',
                  style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
        ]),
      ),
    );
  }

  Future<void> _postAction(CollabView c, Rec d, String action) async {
    final id = str(d['id']);
    final name = '${str(d['type'])}${str(d['title']).isEmpty ? '' : ' ${str(d['title'])}'}';
    switch (action) {
      case 'edit':
      case 'live':
        await push(context, DeliverableScreen(collabId: c.id, deliverableId: id));
        break;
      case 'duplicate':
        await Repo.save('deliverables', {
          'collab_id': c.id,
          'type': d['type'],
          'platform': d['platform'],
          'due_date': d['due_date'],
          'status': 'Planned',
          'revision_count': 0,
        });
        await Repo.log(c.id, 'Post added: ${str(d['type'])}');
        Repo.notify();
        break;
      case 'delete':
        if (!await confirm(context, 'Delete $name?', 'Its links, checklist and views will be removed.')) return;
        await Repo.delete('deliverables', id);
        await Repo.log(c.id, 'Post deleted: $name');
        Repo.notify();
        break;
    }
  }

  Widget _productsPanel(CollabView c) {
    final s = _s!;
    return Panel(
      title: 'Products received',
      trailing: TextButton(
          onPressed: () => push(context, ProductFormScreen(brandId: str(c.row['brand_id']), collabId: c.id)),
          child: const Text('+ Add')),
      child: c.products.isEmpty
          ? Text(
              str(c.row['barter_value']).isEmpty || toD(c.row['barter_value']) == 0
                  ? 'Add the product you got — paste its link to auto-fill photo, name and price.'
                  : 'Barter value ${money(c.barterValue)} (no product added).',
              style: const TextStyle(color: kMuted))
          : Column(
              children: c.products
                  .map((p) => ProductTile(product: p, imageFile: s.productImage[str(p['id'])], linkCount: _productLinks[str(p['id'])] ?? 0))
                  .toList()),
    );
  }

  Widget _paymentPanel(CollabView c) {
    final frac = c.agreed <= 0 ? 0.0 : (c.received / c.agreed).clamp(0.0, 1.0);
    return Panel(
      title: 'Payment',
      trailing: TextButton(onPressed: () => receiptDialog(context, c), child: const Text('+ Record')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(value: frac, minHeight: 10, color: kOk, backgroundColor: kLine),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('Received ${money(c.received)}', style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text(c.pending > 0 ? 'Pending ${money(c.pending)}' : 'Fully paid',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.pending > 0 ? kDanger : kOk)),
        ]),
        if (c.dueDate != null && c.pending > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Due ${showDate(c.dueDate)}${c.paymentStatus == 'Overdue' ? ' · overdue' : ''}',
                style: TextStyle(fontSize: 12, color: c.paymentStatus == 'Overdue' ? kDanger : kMuted)),
          ),
        for (final r in c.receipts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.check_circle, color: kOk, size: 20),
            title: Text(money(toD(r['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              showDate(r['received_date']),
              if (str(r['method']).isNotEmpty) str(r['method']),
              if (toD(r['tds']) > 0) 'TDS ${money(toD(r['tds']))}',
              if (str(r['notes']).isNotEmpty) str(r['notes']),
            ].join(' · ')),
            onTap: () => receiptDialog(context, c, existing: r),
          ),
      ]),
    );
  }

  Widget _actions(CollabView c) {
    return Row(children: [
      if (c.hasCash)
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: () => push(context,
                InvoiceScreen(collabId: c.id, invoiceId: c.invoices.isNotEmpty ? str(c.invoices.first['id']) : null)),
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(c.invoices.isEmpty ? 'Create invoice' : 'Invoice'),
          ),
        ),
      if (c.hasCash) const SizedBox(width: 10),
      if (c.hasCash)
        SizedBox(
          width: 132,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: () => _remind(c),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: const Text('Remind'),
          ),
        )
      else
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: () => _remind(c),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: const Text('Message brand'),
          ),
        ),
    ]);
  }

  void _remind(CollabView c) {
    final who = str(_contact?['name']).isEmpty ? 'there' : str(_contact?['name']).split(' ').first;
    final amt = money(c.pending);
    final inv = c.invoices.isEmpty ? '' : ' (invoice ${str(c.invoices.first['number'])})';
    final due = c.dueDate == null ? '' : ' due on ${showDate(c.dueDate)}';
    final links = c.deliverables.map((d) => str(d['live_link'])).where((l) => l.isNotEmpty).join('\n');
    final templates = <(String, String)>[
      if (c.pending > 0)
        ('Friendly payment nudge',
            'Hi $who, hope you are well! Just a gentle reminder about the payment of $amt for "${c.title}"$inv$due. Thank you!'),
      if (c.pending > 0)
        ('Overdue follow-up', 'Hi $who, following up on the pending $amt for "${c.title}"$inv. Could you share an expected payment date?'),
      if (links.isNotEmpty) ('Share live links', 'Hi $who, the content for "${c.title}" is live:\n$links\nThanks for collaborating!'),
      ('Check in', 'Hi $who, quick check-in on "${c.title}". Let me know if you need anything from my side.'),
    ];
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final t in templates)
            ListTile(
              title: Text(t.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t.$2, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.share_outlined),
              onTap: () {
                Navigator.pop(s);
                Share.share(t.$2);
              },
            ),
        ]),
      ),
    );
  }

  Widget _fold(String title, String sub, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          subtitle: sub.isEmpty ? null : Text(sub, style: const TextStyle(fontSize: 12, color: kMuted)),
          shape: const Border(),
          collapsedShape: const Border(),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [child],
        ),
      );

  Widget _expenses(CollabView c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final e in c.expenses)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('${str(e['category'])} · ${money(toD(e['amount']))}'),
          subtitle: Text([showDate(e['date']), str(e['notes'])].where((x) => x.isNotEmpty && x != '—').join(' · ')),
          onTap: () => expenseDialog(context, c.id, existing: e),
        ),
      Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => expenseDialog(context, c.id), child: const Text('+ Add expense'))),
      KV('Cash received', money(c.received)),
      if (c.hasBarter) KV('Barter value', money(c.barterEarned)),
      KV('Expenses', '- ${money(c.expenseTotal)}'),
      KV('Net profit', money(c.profit)),
    ]);
  }

  Widget _invoices(CollabView c) => Column(
        children: c.invoices
            .map((i) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(str(i['number'])),
                  subtitle: Text('${showDate(i['invoice_date'])} · ${money(toD(i['total']))}'),
                  trailing: Pill(str(i['status']), str(i['status']) == 'Paid' ? kOk : kMuted),
                  onTap: () => push(context, InvoiceScreen(collabId: c.id, invoiceId: str(i['id']))),
                ))
            .toList(),
      );

  Widget _details(CollabView c) {
    final ct = _contact;
    String range(Object? a, Object? b) => (str(a).isEmpty && str(b).isEmpty) ? '' : '${showDate(a)} → ${showDate(b)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (ct != null) KV('Contact', '${str(ct['name'])}${str(ct['role']).isEmpty ? '' : ' · ${str(ct['role'])}'}'),
      if (ct != null) KV('Email', str(ct['email'])),
      if (ct != null) KV('Phone', str(ct['phone'])),
      KV('Campaign', str(c.row['campaign'])),
      KV('Campaign window', range(c.row['start_date'], c.row['end_date'])),
      KV('Post by', showDate(c.row['publish_date'])),
      KV('Payment terms', str(c.row['payment_terms'])),
      KV('Usage rights until', showDate(c.row['usage_rights_until'])),
      KV('Exclusivity until', showDate(c.row['exclusivity_until'])),
      KV('Follow up', showDate(c.row['renewal_date'])),
      KV('Source', str(c.row['source'])),
      for (final l in str(c.row['links']).split(RegExp(r'\s+')).where((l) => l.isNotEmpty))
        KV('Link', l, onTap: isValidUrl(l) ? () => openUrl(context, l) : null),
      KV('Notes', str(c.row['notes'])),
      TextButton(onPressed: () => push(context, CollabFormScreen(collabId: c.id)), child: const Text('Edit details')),
    ]);
  }

  Widget _timeline() {
    if (_activity.isEmpty) return const Text('No activity yet.', style: TextStyle(color: kMuted));
    return Column(
      children: _activity.map((a) {
        final dt = DateTime.tryParse(str(a['created_at']));
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.circle, size: 9, color: kPrimary),
          minLeadingWidth: 12,
          title: Text(str(a['message'])),
          subtitle: Text(dt == null ? '' : '${showDate(isoDate(dt))} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'),
        );
      }).toList(),
    );
  }
}

// ======================= STAGE CHANGE =======================

List<String> stageGateIssues(CollabView c, String target) {
  final issues = <String>[];
  final ti = stageIndex(target);
  if (ti >= stageIndex('Confirmed')) {
    if (c.hasCash && c.agreed <= 0) issues.add('Agreed amount not set');
    if (c.hasBarter && c.barterValue <= 0) issues.add('Product value not set');
  }
  if (ti >= stageIndex('Shooting') && c.deliverables.isEmpty) issues.add('No reels/posts added');
  if (ti >= stageIndex('Posted')) {
    final missing = c.deliverables.where((d) => str(d['live_link']).isEmpty).length;
    if (missing > 0) issues.add('$missing post(s) without live link');
  }
  if (target == 'Done' && c.pending > 0) issues.add('${money(c.pending)} still pending');
  return issues;
}

Future<void> showStageSheet(BuildContext context, CollabView c, {String? preselect}) async {
  final target = preselect ??
      await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Move to stage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            ...kAllStages.map((st) {
              final issues = st == kCancelled ? <String>[] : stageGateIssues(c, st);
              return ListTile(
                leading: Icon(st == c.stage ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: stageColor(st)),
                title: Text(st, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(issues.isEmpty ? (kStageHint[st] ?? '') : issues.join(' · '),
                    style: TextStyle(color: issues.isEmpty ? kMuted : kWarn, fontSize: 12)),
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
      final go = await confirm(context, 'Not complete yet', '${issues.join('\n')}\n\nMove to $target anyway?', ok: 'Move anyway', danger: false);
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
