import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/invoice_pdf.dart';
import '../core/repo.dart';
import '../core/snapshot.dart';
import 'widgets.dart';

class InvoiceScreen extends StatefulWidget {
  final String collabId;
  final String? invoiceId;
  const InvoiceScreen({super.key, required this.collabId, this.invoiceId});
  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _Item {
  final TextEditingController desc;
  final TextEditingController amount;
  final String link;
  final String posted;
  _Item(String d, double a, {this.link = '', this.posted = ''})
      : desc = TextEditingController(text: d),
        amount = TextEditingController(text: a == 0 ? '' : (a % 1 == 0 ? a.toInt().toString() : a.toStringAsFixed(2)));
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  bool _busy = false;
  CollabView? _c;
  Rec _brand = {};
  String? _id;
  String _status = 'Draft';
  bool _gst = true;
  double _gstRate = 18;
  final number = TextEditingController(), date = TextEditingController(), due = TextEditingController(), notes = TextEditingController();
  List<_Item> _items = [];

  @override
  void initState() {
    super.initState();
    _id = widget.invoiceId;
    _load();
  }

  Future<void> _load() async {
    final s = await Snapshot.load();
    _c = s.collab(widget.collabId);
    final c = _c;
    if (c == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    _brand = await Repo.byId('brands', str(c.row['brand_id'])) ?? {};
    _gstRate = toD(await Repo.setting('gst_rate', '18'));
    if (_id != null) {
      final inv = await Repo.byId('invoices', _id!) ?? {};
      number.text = str(inv['number']);
      date.text = str(inv['invoice_date']);
      due.text = str(inv['due_date']);
      notes.text = str(inv['notes']);
      _status = str(inv['status']).isEmpty ? 'Draft' : str(inv['status']);
      final r = toD(inv['gst_rate']);
      _gst = r > 0;
      if (r > 0) _gstRate = r;
      _items = invoiceItems(inv)
          .map((e) => _Item(str(e['desc']), toD(e['amount']), link: str(e['link']), posted: str(e['posted'])))
          .toList();
    } else {
      number.text = await Repo.nextInvoiceNumber();
      date.text = todayIso();
      due.text = c.dueDate ?? isoDate(DateTime.now().add(const Duration(days: 30)));
      _gst = (await Repo.setting('gst_registered', '0')) == '1';
      final ds = c.deliverables;
      if (ds.isEmpty) {
        _items = [_Item(c.title, c.agreed)];
      } else {
        final each = (c.agreed / ds.length * 100).roundToDouble() / 100;
        _items = ds
            .map((d) => _Item(
                  '${str(d['platform'])} ${str(d['type'])}${str(d['title']).isEmpty ? '' : ' ${str(d['title'])}'}',
                  each,
                  link: str(d['live_link']),
                  posted: d['status'] == 'Live' ? str(d['live_date']) : '',
                ))
            .toList();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  double get _subtotal => _items.fold(0.0, (a, i) => a + toD(i.amount.text));
  double get _gstAmount => _gst ? (_subtotal * _gstRate / 100 * 100).roundToDouble() / 100 : 0;
  double get _total => _subtotal + _gstAmount;

  Future<bool> _save() async {
    if (!_form.currentState!.validate()) return false;
    if (_items.isEmpty || _subtotal <= 0) {
      toast(context, 'Add at least one line item with an amount');
      return false;
    }
    final isNew = _id == null;
    if (isNew) {
      final clash = await Repo.count('invoices', where: 'number = ?', args: [number.text.trim()]);
      if (clash > 0) {
        if (mounted) toast(context, 'Invoice number already used');
        return false;
      }
    }
    final id = await Repo.save('invoices', {
      'id': _id,
      'collab_id': widget.collabId,
      'number': number.text.trim(),
      'invoice_date': date.text.isEmpty ? todayIso() : date.text,
      'due_date': nn(due),
      'items': jsonEncode(_items
          .map((i) => {'desc': i.desc.text.trim(), 'amount': toD(i.amount.text), 'link': i.link, 'posted': i.posted})
          .toList()),
      'subtotal': _subtotal,
      'gst_rate': _gst ? _gstRate : 0,
      'gst_amount': _gstAmount,
      'total': _total,
      'status': _status,
      'notes': nn(notes),
    });
    if (isNew) {
      await Repo.consumeInvoiceNumber();
      await Repo.log(widget.collabId, 'Invoice ${number.text.trim()} created: ${money(_total)}');
      final c = _c!;
      if (str(c.row['payment_due_date']).isEmpty && due.text.isNotEmpty) {
        await Repo.save('collabs', {'id': c.id, 'payment_due_date': due.text});
      }
    }
    Repo.notify();
    _id = id;
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _sharePdf() async {
    if (!await _save()) return;
    setState(() => _busy = true);
    try {
      final inv = await Repo.byId('invoices', _id!);
      final c = _c!;
      final contact = str(c.row['contact_id']).isEmpty ? null : await Repo.byId('contacts', str(c.row['contact_id']));
      final file = await InvoicePdf.build(invoice: inv!, brand: _brand, collab: c, contact: contact);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], subject: 'Invoice ${number.text.trim()}');
      if (_status == 'Draft') {
        _status = 'Sent';
        await Repo.save('invoices', {'id': _id, 'status': 'Sent'});
        await Repo.log(widget.collabId, 'Invoice ${number.text.trim()} shared');
        Repo.notify();
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not create PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_id == null) return;
    if (!await confirm(context, 'Delete invoice?', 'Invoice ${number.text} will be removed. Payments are not affected.')) return;
    await Repo.delete('invoices', _id!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_id == null ? 'New invoice' : 'Invoice'),
        actions: [
          if (_id != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Delete'),
          TextButton(
              onPressed: _loading
                  ? null
                  : () async {
                      if (await _save() && mounted) toast(context, 'Invoice saved');
                    },
              child: const Text('Save')),
        ],
      ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _sharePdf,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Save & share PDF (WhatsApp, email…)'),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                SectionCard(
                  title: 'Invoice',
                  child: Column(children: [
                    textField(number, 'Invoice number', req: true),
                    DateField(date, 'Invoice date'),
                    DateField(due, 'Due date'),
                    Pick(label: 'Status', value: _status, options: const ['Draft', 'Sent', 'Paid'], onChanged: (v) => setState(() => _status = v ?? _status)),
                    Text('Bill to: ${str(_brand['name'])}${str(_brand['gstin']).isEmpty ? '' : ' · GSTIN ${str(_brand['gstin'])}'}',
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  ]),
                ),
                SectionCard(
                  title: 'Line items',
                  trailing: TextButton(onPressed: () => setState(() => _items.add(_Item('', 0))), child: const Text('+ Item')),
                  child: Column(children: [
                    for (var i = 0; i < _items.length; i++)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 3, child: textField(_items[i].desc, 'Description', req: true)),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Focus(
                            onFocusChange: (_) => setState(() {}),
                            child: moneyField(_items[i].amount, 'Amount', req: true),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _items.removeAt(i)),
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Remove',
                        ),
                      ]),
                  ]),
                ),
                SectionCard(
                  title: 'Tax',
                  child: Column(children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Charge GST @ ${_gstRate.toStringAsFixed(_gstRate % 1 == 0 ? 0 : 1)}%'),
                      subtitle: const Text('Off = simple bill without GST'),
                      value: _gst,
                      onChanged: (v) => setState(() => _gst = v),
                    ),
                    KV('Subtotal', money(_subtotal)),
                    if (_gst) KV('GST', money(_gstAmount)),
                    KV('Total', money(_total)),
                    if ((_c?.received ?? 0) > 0) KV('Already received', money(_c!.received)),
                    const SizedBox(height: 4),
                    const Text('Your photo, @handle, address, UPI QR and PAN come from Profile.',
                        style: TextStyle(color: kMuted, fontSize: 12)),
                  ]),
                ),
                SectionCard(child: textField(notes, 'Notes on invoice', maxLines: 3, keyboard: TextInputType.multiline, hint: 'Bank details, terms…')),
              ]),
            ),
    );
  }
}
