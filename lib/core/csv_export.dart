import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'format.dart';
import 'repo.dart';
import 'snapshot.dart';

/// RFC 4180 style escaping: quote when the value has a comma, quote, CR or LF.
String csvCell(Object? v) {
  final s = v == null ? '' : v.toString();
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String toCsv(List<String> headers, List<List<Object?>> rows) {
  final b = StringBuffer('﻿'); // BOM so Excel reads UTF-8 (₹)
  b.write(headers.map(csvCell).join(','));
  b.write('\r\n');
  for (final r in rows) {
    b.write(r.map(csvCell).join(','));
    b.write('\r\n');
  }
  return b.toString();
}

class CsvExport {
  static const List<String> sets = ['Brands', 'Contacts', 'Collabs', 'Deliverables', 'Payments', 'Affiliate & other income', 'Products', 'Product links'];

  static Future<List<File>> export(Set<String> which) async {
    final s = await Snapshot.load();
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'csv_${DateTime.now().millisecondsSinceEpoch}'));
    await dir.create(recursive: true);
    final out = <File>[];
    Future<void> write(String name, List<String> h, List<List<Object?>> rows) async {
      final f = File(p.join(dir.path, '${name.toLowerCase().replaceAll(' ', '_')}_${todayIso()}.csv'));
      await f.writeAsString(toCsv(h, rows), encoding: utf8);
      out.add(f);
    }

    String brand(Object? id) => s.brandNames[str(id)] ?? '';

    if (which.contains('Brands')) {
      await write('Brands', ['Name', 'Email', 'Phone', 'Website', 'GSTIN', 'Address', 'Notes'],
          s.brands.map((b) => [b['name'], b['email'], b['phone'], b['website'], b['gstin'], b['address'], b['notes']]).toList());
    }
    if (which.contains('Contacts')) {
      await write('Contacts', ['Name', 'Brand', 'Role', 'Email', 'Phone', 'Notes'],
          s.contacts.map((c) => [c['name'], brand(c['brand_id']), c['role'], c['email'], c['phone'], c['notes']]).toList());
    }
    if (which.contains('Collabs')) {
      await write(
          'Collabs',
          ['Title', 'Brand', 'Type', 'Source', 'Agency', 'Agency %', 'Contact', 'Stage', 'Fee (gross)', 'Fee received', 'TDS',
           'Product value', 'Refund amount', 'Refund received', 'Pending', 'Payment status', 'You earn', 'Expenses',
           'Order #', 'Order date', 'Post by', 'Payment due', 'Usage rights until', 'Deliverables', 'Live', 'Notes'],
          s.collabs
              .map((c) => [
                    c.title, c.brandName, c.kind, c.source, c.agencyName, c.agencyPct, c.contact?['name'], c.stage, c.agreed,
                    c.feeReceived, c.tds, c.hasBarter ? c.barterValue : 0, c.refundAmount, c.refundReceived, c.pending,
                    c.paymentStatus, c.totalValue, c.expenseTotal, c.row['order_no'], c.row['order_date'], c.row['publish_date'],
                    c.dueDate, c.row['usage_rights_until'], c.deliverables.length, c.liveCount, c.row['notes'],
                  ])
              .toList());
    }
    if (which.contains('Deliverables')) {
      await write(
          'Deliverables',
          ['Collab', 'Type', 'Platform', 'Title', 'Status', 'Due', 'Live date', 'Revisions', 'Draft link', 'Live link',
           'Views 7d', 'Likes 7d'],
          s.deliverables.map((d) {
            final m = Snapshot.bestMetric(s.metrics.where((x) => x['deliverable_id'] == d['id']).toList());
            return [s.collabTitle(str(d['collab_id'])), d['type'], d['platform'], d['title'], d['status'], d['due_date'],
              d['live_date'], d['revision_count'], d['draft_link'], d['live_link'], m?['views'], m?['likes']];
          }).toList());
    }
    if (which.contains('Payments')) {
      await write('Payments', ['Received date', 'Collab', 'Brand', 'Kind', 'Amount credited', 'TDS', 'Method', 'Reference', 'Notes'],
          s.receipts.map((r) {
            final c = s.collab(str(r['collab_id']));
            return [r['received_date'], c?.title, c?.brandName, r['kind'] ?? 'Fee', r['amount'], r['tds'], r['method'], r['reference'], r['notes']];
          }).toList());
    }
    if (which.contains('Affiliate & other income')) {
      await write('Income', ['Month', 'Type', 'Platform', 'Gross', 'TDS', 'Paid to bank', 'Status', 'Paid on', 'Notes'],
          s.income.map((r) => [r['month'], r['source_type'], r['platform'], r['gross'], r['tds'], r['net_paid'], r['status'], r['paid_date'], r['notes']]).toList());
    }
    if (which.contains('Products')) {
      await write('Products', ['Name', 'Brand', 'Category', 'Purchase price', 'Quantity', 'Description', 'Notes'],
          s.products.map((x) => [x['name'], brand(x['brand_id']), x['category'], x['purchase_price'], x['quantity'],
            x['description'], x['notes']]).toList());
    }
    if (which.contains('Product links')) {
      final links = await Repo.all('product_links', orderBy: 'sort');
      final pn = {for (final x in s.products) str(x['id']): str(x['name'])};
      await write('Product links', ['Product', 'Title', 'Type', 'URL'],
          links.map((l) => [pn[str(l['product_id'])], l['title'], l['link_type'], l['url']]).toList());
    }
    return out;
  }
}
