import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/snapshot.dart';
import 'collabs_screens.dart';
import 'widgets.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> with AutoReload {
  Snapshot? _s;
  String _view = 'Outstanding';
  String _q = '';

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              _summary(s),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Outstanding', label: Text('Outstanding')),
                  ButtonSegment(value: 'Received', label: Text('Received')),
                ],
                selected: {_view},
                onSelectionChanged: (v) => setState(() => _view = v.first),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: deco('Search brand, collab, status, reference').copyWith(prefixIcon: const Icon(Icons.search)),
                onChanged: (v) => setState(() => _q = v.toLowerCase()),
              ),
              const SizedBox(height: 12),
              ...(_view == 'Outstanding' ? _outstanding(s) : _received(s)),
            ]),
    );
  }

  Widget _summary(Snapshot s) {
    final received = s.collabs.fold(0.0, (a, c) => a + c.received);
    final pending = s.collabs.fold(0.0, (a, c) => a + c.pending);
    final overdue = s.collabs.where((c) => c.paymentStatus == 'Overdue').fold(0.0, (a, c) => a + c.pending);
    final tds = s.collabs.fold(0.0, (a, c) => a + c.tds);
    return StatGrid(children: [
      StatTile(label: 'Total received', value: money(received)),
      StatTile(label: 'Outstanding', value: money(pending)),
      StatTile(label: 'Overdue', value: money(overdue), color: overdue > 0 ? kDanger : null),
      StatTile(label: 'TDS deducted', value: money(tds)),
    ]);
  }

  List<Widget> _outstanding(Snapshot s) {
    final l = s.collabs.where((c) => c.pending > 0).where((c) {
      if (_q.isEmpty) return true;
      return '${c.title} ${c.brandName} ${c.paymentStatus}'.toLowerCase().contains(_q);
    }).toList()
      ..sort((a, b) => (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999'));
    if (l.isEmpty) return [const EmptyState(icon: Icons.check_circle_outline, text: 'Nothing outstanding.')];
    return l
        .map((c) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(c.title),
                subtitle: Text(
                    '${c.brandName} · received ${money(c.received)} of ${money(c.agreed)}\nDue ${showDate(c.dueDate)}'),
                isThreeLine: true,
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money(c.pending), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Pill(c.paymentStatus, paymentStatusColor(c.paymentStatus)),
                ]),
                onTap: () => push(context, CollabDetailScreen(collabId: c.id)),
                onLongPress: () => receiptDialog(context, c),
              ),
            ))
        .toList();
  }

  List<Widget> _received(Snapshot s) {
    final l = s.receipts.where((r) {
      if (_q.isEmpty) return true;
      final c = s.collab(str(r['collab_id']));
      return '${c?.title} ${c?.brandName} ${str(r['reference'])} ${str(r['method'])}'.toLowerCase().contains(_q);
    }).toList();
    if (l.isEmpty) return [const EmptyState(icon: Icons.payments_outlined, text: 'No payments recorded yet.')];
    return l.map((r) {
      final c = s.collab(str(r['collab_id']));
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          title: Text(money(toD(r['amount']))),
          subtitle: Text([
            showDate(r['received_date']),
            if (c != null) '${c.brandName} · ${c.title}',
            if (toD(r['tds']) > 0) 'TDS ${money(toD(r['tds']))}',
            if (str(r['method']).isNotEmpty) str(r['method']),
          ].join('\n')),
          onTap: c == null ? null : () => receiptDialog(context, c, existing: r),
        ),
      );
    }).toList();
  }
}
