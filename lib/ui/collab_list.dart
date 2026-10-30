import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/snapshot.dart';
import 'collab_detail.dart';
import 'type_picker.dart';
import 'v2_widgets.dart';
import 'widgets.dart';

class CollabsScreen extends StatefulWidget {
  final String? brandId;
  final String initialFilter;
  const CollabsScreen({super.key, this.brandId, this.initialFilter = 'All'});
  @override
  State<CollabsScreen> createState() => _CollabsScreenState();
}

class _CollabsScreenState extends State<CollabsScreen> with AutoReload {
  Snapshot? _s;
  String _q = '';
  late String _filter = widget.initialFilter;
  static const _filters = ['All', 'Active', 'To post', 'Unpaid', 'Refund due', ...kDealTypes, 'Done', kCancelled];

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    if (mounted) setState(() => _s = s);
  }

  bool _match(CollabView c) {
    if (widget.brandId != null && c.row['brand_id'] != widget.brandId) return false;
    switch (_filter) {
      case 'Active':
        if (!c.active) return false;
        break;
      case 'Refund due':
        if (c.pendingRefund <= 0.5) return false;
        break;
      case 'To post':
        if (c.stage == kCancelled || c.deliverables.isEmpty || c.liveCount >= c.deliverables.length) return false;
        break;
      case 'Unpaid':
        if (c.pending <= 0) return false;
        break;
      case 'Done':
      case kCancelled:
        if (c.stage != _filter) return false;
        break;
      default:
        if (kDealTypes.contains(_filter) && c.kind != _filter) return false;
    }
    final q = _q.toLowerCase().trim();
    if (q.isEmpty) return true;
    return [
      c.title, c.brandName, c.stage, c.dealType, c.source, c.agencyName, str(c.row['campaign']), str(c.row['notes']),
      str(c.row['order_no']), str(c.contact?['name']),
      ...c.products.map((p) => str(p['name'])),
      ...c.deliverables.map((d) => '${str(d['live_link'])} ${str(d['draft_link'])}'),
    ].join(' ').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final list = s == null ? <CollabView>[] : s.collabs.where(_match).toList();
    list.sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return str(b.row['updated_at']).compareTo(str(a.row['updated_at']));
    });
    final total = list.fold<double>(0, (a, c) => a + c.totalValue);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.brandId == null ? 'Collabs' : (s?.brandNames[widget.brandId] ?? 'Collabs')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('${list.length} · ${money(total)}', style: const TextStyle(color: kMuted, fontSize: 13))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_collabs_${widget.brandId ?? 'all'}',
        onPressed: () => showAddSheet(context, brandId: widget.brandId),
        icon: const Icon(Icons.add),
        label: const Text('New collab', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search brand, product, contact, order #, link',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(16))),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        PillRow(options: _filters, value: _filter, onChanged: (v) => setState(() => _filter = v), padding: const EdgeInsets.symmetric(horizontal: 16)),
        const SizedBox(height: 8),
        Expanded(
          child: s == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? EmptyState(
                      icon: Icons.handshake_outlined,
                      text: s.collabs.isEmpty ? 'No collabs yet.\nTap + New collab to add your first one.' : 'No collabs match.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
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
  Widget build(BuildContext context) => CollabRow(c: c, onTap: () => push(context, CollabDetailScreen(collabId: c.id)));
}
