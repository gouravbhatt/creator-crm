import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/repo.dart';
import '../core/snapshot.dart';
import 'widgets.dart';

// ======================= DIALOGS =======================

Future<void> receiptDialog(BuildContext context, CollabView c, {Rec? existing, String? kind}) async {
  final form = GlobalKey<FormState>();
  final amount = numCtl(existing?['amount']);
  final tds = numCtl(existing?['tds']);
  final date = ctl(existing?['received_date'] ?? todayIso());
  final ref = ctl(existing?['reference']);
  final notes = ctl(existing?['notes']);
  String? method = existing?['method'] as String?;
  final kinds = [
    if (c.hasCash) 'Fee',
    if (c.isOrder) 'Refund',
    if (c.isOrder && c.hasCash) 'Fee + Refund',
    if (c.hasCash) 'Advance',
    'Kill fee',
  ];
  String k = str(existing?['kind']).isNotEmpty
      ? str(existing?['kind'])
      : (kind ?? (c.isOrder && c.pendingRefund > 0 && c.pendingFee > 0 ? 'Fee + Refund' : (c.isOrder && c.pendingFee <= 0 ? 'Refund' : 'Fee')));
  if (!kinds.contains(k)) kinds.add(k);
  if (existing == null) {
    final suggest = k == 'Refund' ? c.pendingRefund : (k == 'Fee + Refund' ? c.pending : c.pendingFee);
    if (suggest > 0) amount.text = suggest % 1 == 0 ? suggest.toInt().toString() : suggest.toStringAsFixed(2);
  }
  final res = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(d).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Form(
              key: form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(existing == null ? 'Record payment' : 'Edit payment', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  [
                    if (c.pendingFee > 0) 'Fee due ${money(c.pendingFee)}',
                    if (c.pendingRefund > 0) 'Refund due ${money(c.pendingRefund)}',
                    if (c.pending <= 0) 'Nothing pending',
                  ].join(' · '),
                  style: const TextStyle(color: kMuted),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final x in kinds)
                    ChoiceChip(
                      label: Text(x, style: TextStyle(color: k == x ? Colors.white : kInk, fontWeight: FontWeight.w600)),
                      selected: k == x,
                      showCheckmark: false,
                      selectedColor: x == 'Refund' ? kAmberDark : kInk,
                      onSelected: (_) => set(() => k = x),
                    ),
                ]),
                if (k == 'Fee + Refund')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('One combined transfer — the app takes the refund part first, the rest counts as fee.',
                        style: TextStyle(fontSize: 12, color: kMuted)),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: moneyField(amount, 'Amount credited (₹)', req: true)),
                  if (k != 'Refund') ...[const SizedBox(width: 8), Expanded(child: moneyField(tds, 'TDS cut (₹)'))],
                ]),
                DateField(date, 'Received on'),
                Pick(label: 'Method', value: method, options: kPaymentMethods, allowEmpty: true, onChanged: (v) => set(() => method = v)),
                textField(ref, 'Reference / UTR'),
                textField(notes, 'Notes'),
                Row(children: [
                  if (existing != null)
                    TextButton(onPressed: () => Navigator.pop(d, 'delete'), child: const Text('Delete', style: TextStyle(color: kDanger))),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(140, 50)),
                    onPressed: () {
                      if (!form.currentState!.validate()) return;
                      if (toD(amount.text) <= 0) return;
                      Navigator.pop(d, 'save');
                    },
                    child: const Text('Save'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
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
    final amt = toD(amount.text);
    final base = {
      'collab_id': c.id,
      'received_date': date.text.isEmpty ? todayIso() : date.text,
      'method': method,
      'reference': nn(ref),
      'notes': nn(notes),
    };
    if (k == 'Fee + Refund' && existing == null) {
      final refundPart = amt < c.pendingRefund ? amt : c.pendingRefund;
      final feePart = amt - refundPart;
      if (refundPart > 0) await Repo.save('payments', {...base, 'kind': 'Refund', 'amount': refundPart, 'tds': 0});
      if (feePart > 0 || toD(tds.text) > 0) await Repo.save('payments', {...base, 'kind': 'Fee', 'amount': feePart, 'tds': toD(tds.text)});
      await Repo.log(c.id, 'Received ${money(amt)}: refund ${money(refundPart)} + fee ${money(feePart)}');
    } else {
      await Repo.save('payments', {
        ...base,
        'id': existing?['id'],
        'kind': k == 'Fee + Refund' ? 'Fee' : k,
        'amount': amt,
        'tds': k == 'Refund' ? 0 : toD(tds.text),
      });
      await Repo.log(c.id, '${existing == null ? '$k received' : 'Payment edited'}: ${money(amt)}');
    }
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
