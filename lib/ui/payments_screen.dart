import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/snapshot.dart';
import 'collabs_screens.dart';
import 'v2_widgets.dart';
import 'widgets.dart';

/// Stand-alone payments page (from Profile).
class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Brand payments')), body: const PaymentsBody());
}

/// Brand payments: what's owed (fees + refunds) and what was received.
class PaymentsBody extends StatefulWidget {
  const PaymentsBody({super.key});
  @override
  State<PaymentsBody> createState() => _PaymentsBodyState();
}

class _PaymentsBodyState extends State<PaymentsBody> with AutoReload {
  Snapshot? _s;
  String _view = 'Owed to you';
  String _q = '';

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const Center(child: CircularProgressIndicator());
    final fees = s.collabs.fold<double>(0, (a, c) => a + c.pendingFee);
    final refunds = s.collabs.fold<double>(0, (a, c) => a + c.pendingRefund);
    final overdue = s.collabs.where((c) => c.paymentStatus == 'Overdue').fold<double>(0, (a, c) => a + c.pending);
    final tds = s.collabs.fold<double>(0, (a, c) => a + c.tds);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      StatGrid(children: [
        StatTile(label: 'Fees owed', value: money(fees), color: fees > 0 ? kPrimaryDark : null),
        StatTile(label: 'Refunds owed', value: money(refunds), sub: 'your money out', color: refunds > 0 ? kAmberDark : null),
        StatTile(label: 'Overdue', value: money(overdue), color: overdue > 0 ? kDanger : null),
        StatTile(label: 'TDS deducted', value: money(tds)),
      ]),
      Segmented(options: const ['Owed to you', 'Received'], value: _view, onChanged: (v) => setState(() => _view = v)),
      const SizedBox(height: 12),
      TextField(
        decoration: deco('Search brand, collab, reference').copyWith(prefixIcon: const Icon(Icons.search)),
        onChanged: (v) => setState(() => _q = v.toLowerCase()),
      ),
      const SizedBox(height: 12),
      ...(_view == 'Owed to you' ? _owed(s) : _received(s)),
    ]);
  }

  List<Widget> _owed(Snapshot s) {
    final l = s.collabs.where((c) => c.pending > 0.5).where((c) {
      if (_q.isEmpty) return true;
      return '${c.title} ${c.brandName} ${c.paymentStatus}'.toLowerCase().contains(_q);
    }).toList()
      ..sort((a, b) => (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999'));
    if (l.isEmpty) return [const EmptyState(icon: Icons.check_circle_outline, text: 'Nothing owed. All settled.')];
    return l
        .map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => push(context, CollabDetailScreen(collabId: c.id)),
                  onLongPress: () => receiptDialog(context, c),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      ProductThumb(fileName: c.coverImage, type: c.kind, size: 48, radius: 12),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.brandName, style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w600)),
                          Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            [
                              if (c.pendingFee > 0) 'Fee ${money(c.pendingFee)}',
                              if (c.pendingRefund > 0) 'Refund ${money(c.pendingRefund)}',
                              'due ${showDate(c.dueDate)}',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 12, color: kBody),
                          ),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(money(c.pending), style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Pill(c.paymentStatus, paymentStatusColor(c.paymentStatus)),
                      ]),
                    ]),
                  ),
                ),
              ),
            ))
        .toList();
  }

  List<Widget> _received(Snapshot s) {
    final l = s.receipts.where((r) {
      if (_q.isEmpty) return true;
      final c = s.collab(str(r['collab_id']));
      return '${c?.title} ${c?.brandName} ${str(r['reference'])} ${str(r['method'])} ${str(r['kind'])}'.toLowerCase().contains(_q);
    }).toList();
    if (l.isEmpty) return [const EmptyState(icon: Icons.payments_outlined, text: 'No payments recorded yet.')];
    return l.map((r) {
      final c = s.collab(str(r['collab_id']));
      final kind = str(r['kind']).isEmpty ? 'Fee' : str(r['kind']);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Text(money(toD(r['amount'])), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Pill(kind, kind == 'Refund' ? kAmberDark : kPrimaryDark),
            ]),
            subtitle: Text([
              showDate(r['received_date']),
              if (c != null) '${c.brandName} · ${c.title}',
              if (toD(r['tds']) > 0) 'TDS ${money(toD(r['tds']))}',
            ].join('\n')),
            onTap: c == null ? null : () => receiptDialog(context, c, existing: r),
          ),
        ),
      );
    }).toList();
  }
}
