import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/repo.dart';
import '../core/snapshot.dart';
import 'widgets.dart';

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
