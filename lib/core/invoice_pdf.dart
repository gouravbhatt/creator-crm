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

class InvoicePdf {
  static Future<File> build({
    required Rec invoice,
    required Rec brand,
    required String collabTitle,
    required double alreadyReceived,
  }) async {
    final st = await Repo.settings();
    final name = st['profile_name'] ?? '';
    final upi = st['profile_upi'] ?? '';
    final items = invoiceItems(invoice);
    final subtotal = toD(invoice['subtotal']);
    final gstRate = toD(invoice['gst_rate']);
    final gst = toD(invoice['gst_amount']);
    final total = toD(invoice['total']);
    final balance = (total - alreadyReceived) < 0 ? 0.0 : total - alreadyReceived;

    Uint8List? signature;
    final sig = st['signature_file'] ?? '';
    if (sig.isNotEmpty) {
      final f = await Media.file(sig);
      if (await f.exists()) signature = await f.readAsBytes();
    }

    final doc = pw.Document(title: str(invoice['number']), author: name);
    final small = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
    const bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

    pw.Widget party(String label, List<String> lines) => pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: small),
            pw.SizedBox(height: 2),
            ...lines.where((l) => l.trim().isNotEmpty).map((l) => pw.Text(l, style: const pw.TextStyle(fontSize: 10))),
          ]),
        );

    pw.Widget totalRow(String k, String v, {bool strong = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(k, style: strong ? bold : null),
            pw.Text(v, style: strong ? bold : null),
          ]),
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(gstRate > 0 ? 'TAX INVOICE' : 'INVOICE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('No. ${str(invoice['number'])}', style: bold),
            pw.Text('Date: ${showDate(invoice['invoice_date'])}'),
            if (str(invoice['due_date']).isNotEmpty) pw.Text('Due: ${showDate(invoice['due_date'])}'),
          ]),
        ]),
        pw.SizedBox(height: 18),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          party('From', [
            name,
            st['profile_address'] ?? '',
            if ((st['profile_gstin'] ?? '').isNotEmpty) 'GSTIN: ${st['profile_gstin']}',
            if ((st['profile_pan'] ?? '').isNotEmpty) 'PAN: ${st['profile_pan']}',
            st['profile_email'] ?? '',
            st['profile_phone'] ?? '',
          ]),
          pw.SizedBox(width: 24),
          party('Bill to', [
            str(brand['name']),
            str(brand['address']),
            if (str(brand['gstin']).isNotEmpty) 'GSTIN: ${str(brand['gstin'])}',
            str(brand['email']),
          ]),
        ]),
        pw.SizedBox(height: 14),
        pw.Text('Campaign: $collabTitle', style: small),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['#', 'Description', 'Amount'],
          data: [
            for (var i = 0; i < items.length; i++) ['${i + 1}', str(items[i]['desc']), _rs(toD(items[i]['amount']))],
          ],
          headerStyle: bold,
          cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight},
          columnWidths: {0: const pw.FixedColumnWidth(24), 1: const pw.FlexColumnWidth(), 2: const pw.FixedColumnWidth(100)},
        ),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          pw.Spacer(),
          pw.SizedBox(
            width: 230,
            child: pw.Column(children: [
              totalRow('Subtotal', _rs(subtotal)),
              if (gstRate > 0) totalRow('GST @ ${gstRate.toStringAsFixed(gstRate % 1 == 0 ? 0 : 1)}%', _rs(gst)),
              totalRow('Total', _rs(total), strong: true),
              if (alreadyReceived > 0) totalRow('Less: received', '- ${_rs(alreadyReceived)}'),
              if (alreadyReceived > 0) totalRow('Balance payable', _rs(balance), strong: true),
            ]),
          ),
        ]),
        pw.SizedBox(height: 24),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          if (upi.isNotEmpty && balance > 0)
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: upiUri(upiId: upi, name: name, amount: balance, note: str(invoice['number'])),
                width: 96,
                height: 96,
              ),
              pw.SizedBox(height: 4),
              pw.Text('Scan to pay via UPI: $upi', style: small),
            ]),
          pw.Spacer(),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            if (signature != null) pw.Image(pw.MemoryImage(signature), width: 120, height: 50, fit: pw.BoxFit.contain),
            pw.Text(name, style: bold),
            pw.Text('Authorised signatory', style: small),
          ]),
        ]),
        if (str(invoice['notes']).isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text('Notes', style: small),
          pw.Text(str(invoice['notes']), style: const pw.TextStyle(fontSize: 10)),
        ],
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
