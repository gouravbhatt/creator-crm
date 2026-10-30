import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'format.dart';
import 'media.dart';
import 'repo.dart';
import 'snapshot.dart';

/// PDF uses the built-in Helvetica font, which has no ₹ glyph, so amounts print as "Rs.".
String _rs(num v) => 'Rs. ${plainNum(v.round())}';

List<Map<String, dynamic>> invoiceItems(Rec inv) {
  try {
    return (jsonDecode(str(inv['items'])) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (_) {
    return [];
  }
}

String upiUri({required String upiId, required String name, required double amount, required String note}) {
  final q = {
    'pa': upiId,
    'pn': name,
    'am': amount.toStringAsFixed(2),
    'cu': 'INR',
    'tn': note,
  };
  return 'upi://pay?${q.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
}

/// Creator-style invoice: photo, name, @handle and address in the header.
class InvoicePdf {
  static final PdfColor _violet = PdfColor.fromHex('#5B3FD6');
  static final PdfColor _violetSoft = PdfColor.fromHex('#DCD4FF');
  static final PdfColor _ink = PdfColor.fromHex('#17142B');
  static final PdfColor _muted = PdfColor.fromHex('#5E5A75');
  static final PdfColor _line = PdfColor.fromHex('#ECEAF4');
  static final PdfColor _bg = PdfColor.fromHex('#F6F5FB');
  static final PdfColor _pinkSoft = PdfColor.fromHex('#FFF6F9');
  static final PdfColor _pink = PdfColor.fromHex('#A3194E');

  static Future<Uint8List?> _img(String? name) async {
    if (name == null || name.isEmpty) return null;
    final f = await Media.file(name);
    return await f.exists() ? await f.readAsBytes() : null;
  }

  static Future<File> build({
    required Rec invoice,
    required Rec brand,
    required CollabView collab,
    Rec? contact,
  }) async {
    final st = await Repo.settings();
    final name = st['profile_name'] ?? '';
    final handle = (st['profile_handle'] ?? '').replaceFirst('@', '');
    final niche = st['profile_niche'] ?? '';
    final address = st['profile_address'] ?? '';
    final email = st['profile_email'] ?? '';
    final phone = st['profile_phone'] ?? '';
    final upi = st['profile_upi'] ?? '';
    final pan = st['profile_pan'] ?? '';
    final bank = st['profile_bank'] ?? '';
    final gstin = st['profile_gstin'] ?? '';
    final items = invoiceItems(invoice);
    final subtotal = toD(invoice['subtotal']);
    final gstRate = toD(invoice['gst_rate']);
    final gst = toD(invoice['gst_amount']);
    final total = toD(invoice['total']);
    final received = collab.feeReceived + collab.refundReceived;
    final refundTotal = items.where((it) => str(it['group']) == 'refund').fold<double>(0, (a, it) => a + toD(it['amount']));
    final due = (total - received) < 0 ? 0.0 : total - received;
    final photo = await _img(st['profile_photo']);
    final signature = await _img(st['signature_file']);

    final doc = pw.Document(title: str(invoice['number']), author: name);
    pw.TextStyle t(double size, {PdfColor? c, bool bold = false}) =>
        pw.TextStyle(fontSize: size, color: c ?? _ink, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);

    pw.Widget avatar() {
      final initials = name.trim().isEmpty
          ? '?'
          : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
      return pw.Container(
        width: 64,
        height: 64,
        decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: _violetSoft, border: pw.Border.all(color: PdfColors.white, width: 3)),
        child: photo != null
            ? pw.ClipOval(child: pw.Image(pw.MemoryImage(photo), fit: pw.BoxFit.cover, width: 64, height: 64))
            : pw.Center(child: pw.Text(initials, style: t(20, c: _violet, bold: true))),
      );
    }

    pw.Widget totalRow(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(k, style: t(11, c: _muted)),
            pw.Text(v, style: t(11)),
          ]),
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        // ---------- header ----------
        pw.Container(
          color: _violet,
          padding: const pw.EdgeInsets.fromLTRB(36, 28, 36, 26),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            avatar(),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(name.isEmpty ? 'Creator' : name, style: t(20, c: PdfColors.white, bold: true)),
                if (handle.isNotEmpty || niche.isNotEmpty)
                  pw.Text([if (handle.isNotEmpty) '@$handle', if (niche.isNotEmpty) niche].join('  ·  '),
                      style: t(11, c: _violetSoft, bold: true)),
                if (address.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(address, style: t(10, c: PdfColors.white)),
                ],
                if (email.isNotEmpty || phone.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text([email, phone].where((x) => x.isNotEmpty).join('  ·  '), style: t(10, c: _violetSoft)),
                ],
                if (gstin.isNotEmpty) pw.Text('GSTIN: $gstin', style: t(10, c: _violetSoft)),
              ]),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(gstRate > 0 ? 'TAX INVOICE' : 'INVOICE', style: t(22, c: PdfColors.white, bold: true)),
              pw.SizedBox(height: 2),
              pw.Text('No. ${str(invoice['number'])}', style: t(10, c: _violetSoft)),
            ]),
          ]),
        ),
        // ---------- body ----------
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(36, 24, 36, 0),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('BILL TO', style: t(9, c: _muted, bold: true)),
                    pw.SizedBox(height: 4),
                    pw.Text(str(brand['name']), style: t(14, bold: true)),
                    if (contact != null && str(contact['name']).isNotEmpty) pw.Text(str(contact['name']), style: t(10, c: _muted)),
                    if (str(brand['address']).isNotEmpty) pw.Text(str(brand['address']), style: t(10, c: _muted)),
                    if (str(brand['gstin']).isNotEmpty) pw.Text('GSTIN: ${str(brand['gstin'])}', style: t(10, c: _muted)),
                    if (str(brand['email']).isNotEmpty) pw.Text(str(brand['email']), style: t(10, c: _muted)),
                  ]),
                ),
                pw.Table(columnWidths: {0: const pw.IntrinsicColumnWidth(), 1: const pw.IntrinsicColumnWidth()}, children: [
                  for (final r in [
                    ('Date', showDate(invoice['invoice_date'])),
                    if (str(invoice['due_date']).isNotEmpty) ('Due', showDate(invoice['due_date'])),
                    ('Campaign', collab.title),
                  ])
                    pw.TableRow(children: [
                      pw.Padding(padding: const pw.EdgeInsets.only(right: 12, bottom: 4), child: pw.Text(r.$1, style: t(10, c: _muted))),
                      pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 4),
                          child: pw.ConstrainedBox(
                              constraints: const pw.BoxConstraints(maxWidth: 180), child: pw.Text(r.$2, style: t(10, bold: true)))),
                    ]),
                ]),
              ]),
              pw.SizedBox(height: 20),
              pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(10)),
                child: pw.Column(children: [
                  pw.Container(
                    color: _bg,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: pw.Row(children: [
                      pw.Expanded(child: pw.Text('ITEM', style: t(9, c: _muted, bold: true))),
                      pw.SizedBox(width: 90, child: pw.Text('DATE', style: t(9, c: _muted, bold: true))),
                      pw.SizedBox(width: 90, child: pw.Text('AMOUNT', textAlign: pw.TextAlign.right, style: t(9, c: _muted, bold: true))),
                    ]),
                  ),
                  for (final g in ['fee', 'refund'])
                    if (items.any((it) => (str(it['group']).isEmpty ? 'fee' : str(it['group'])) == g)) ...[
                      if (items.any((it) => str(it['group']) == 'refund'))
                        pw.Container(
                          alignment: pw.Alignment.centerLeft,
                          decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line))),
                          padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: pw.Text(g == 'fee' ? 'CONTENT & RIGHTS' : 'PRODUCT REIMBURSEMENT',
                              style: t(8, c: g == 'fee' ? _violet : PdfColor.fromHex('#B54708'), bold: true)),
                        ),
                      for (final it in items.where((it) => (str(it['group']).isEmpty ? 'fee' : str(it['group'])) == g))
                        pw.Container(
                          decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line))),
                          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                            pw.Expanded(
                              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                                pw.Text(str(it['desc']), style: t(11, bold: true)),
                                if (str(it['link']).isNotEmpty) pw.Text(str(it['link']), style: t(8, c: g == 'fee' ? _violet : _muted)),
                              ]),
                            ),
                            pw.SizedBox(width: 90, child: pw.Text(str(it['posted']).isEmpty ? '-' : showDate(it['posted']), style: t(10, c: _muted))),
                            pw.SizedBox(width: 90, child: pw.Text(_rs(toD(it['amount'])), textAlign: pw.TextAlign.right, style: t(11, bold: true))),
                          ]),
                        ),
                    ],
                ]),
              ),
              pw.SizedBox(height: 14),
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(
                  child: collab.hasBarter && collab.products.isNotEmpty && !collab.isOrder
                      ? pw.Container(
                          padding: const pw.EdgeInsets.all(10),
                          decoration: pw.BoxDecoration(color: _pinkSoft, borderRadius: pw.BorderRadius.circular(8)),
                          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                            pw.Text('Barter (not billed)', style: t(10, c: _pink, bold: true)),
                            pw.SizedBox(height: 2),
                            pw.Text(
                                '${collab.products.map((x) => str(x['name'])).join(', ')}, value ${_rs(collab.barterValue)}',
                                style: t(9, c: _muted)),
                          ]),
                        )
                      : (refundTotal > 0
                          ? pw.Container(
                              padding: const pw.EdgeInsets.all(10),
                              decoration: pw.BoxDecoration(color: PdfColor.fromHex('#FFF1E5'), borderRadius: pw.BorderRadius.circular(8)),
                              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                                pw.Text('Reimbursement is not a fee', style: t(10, c: PdfColor.fromHex('#8A3A06'), bold: true)),
                                pw.SizedBox(height: 2),
                                pw.Text('It repays the product cost paid by the creator. GST, if any, applies to fees only.', style: t(9, c: _muted)),
                              ]),
                            )
                          : pw.SizedBox()),
                ),
                pw.SizedBox(width: 20),
                pw.SizedBox(
                  width: 220,
                  child: pw.Column(children: [
                    if (refundTotal > 0) totalRow('Fee & rights', _rs(subtotal - refundTotal)),
                    if (refundTotal > 0) totalRow('Reimbursement', _rs(refundTotal)) else totalRow('Subtotal', _rs(subtotal)),
                    if (gstRate > 0) totalRow('GST @ ${gstRate.toStringAsFixed(gstRate % 1 == 0 ? 0 : 1)}%', _rs(gst)),
                    if (received > 0) totalRow('Received', '- ${_rs(received)}'),
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: pw.BoxDecoration(color: _ink, borderRadius: pw.BorderRadius.circular(8)),
                      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                        pw.Text('Amount due', style: t(12, c: PdfColors.white, bold: true)),
                        pw.Text(_rs(due), style: t(12, c: PdfColors.white, bold: true)),
                      ]),
                    ),
                  ]),
                ),
              ]),
              pw.SizedBox(height: 20),
              pw.Container(height: 1, color: _line),
              pw.SizedBox(height: 16),
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                if (upi.isNotEmpty && due > 0) ...[
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(8)),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: upiUri(upiId: upi, name: name, amount: due, note: str(invoice['number'])),
                      width: 92,
                      height: 92,
                    ),
                  ),
                  pw.SizedBox(width: 14),
                ],
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(upi.isNotEmpty && due > 0 ? 'Scan to pay with any UPI app' : 'Payment details', style: t(12, bold: true)),
                    pw.SizedBox(height: 4),
                    if (upi.isNotEmpty) pw.Text('UPI: $upi', style: t(10, c: _muted)),
                    if (pan.isNotEmpty) pw.Text('PAN: $pan', style: t(10, c: _muted)),
                    if (bank.isNotEmpty) pw.Text('Bank: $bank', style: t(10, c: _muted)),
                    if (str(invoice['notes']).isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(str(invoice['notes']), style: t(9, c: _muted)),
                    ],
                  ]),
                ),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                  if (signature != null) pw.Image(pw.MemoryImage(signature), width: 110, height: 44, fit: pw.BoxFit.contain),
                  pw.Container(width: 120, height: 1, color: _ink),
                  pw.SizedBox(height: 3),
                  pw.Text(name, style: t(9, c: _muted)),
                ]),
              ]),
            ]),
          ),
        ),
        // ---------- footer ----------
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(36, 0, 36, 24),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Thank you for collaborating!', style: t(10, c: _muted)),
            if (handle.isNotEmpty) pw.Text('@$handle', style: t(10, c: _violet, bold: true)),
          ]),
        ),
      ]),
    ));

    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final safe = str(invoice['number']).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final f = File(p.join(dir.path, 'Invoice_$safe.pdf'));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }
}
