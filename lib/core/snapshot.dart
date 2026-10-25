import 'dart:convert';
import 'dart:math';

import 'constants.dart';
import 'format.dart';
import 'repo.dart';

/// A collab with its children and derived money/delivery state.
class CollabView {
  final Rec row;
  final String brandName;
  final List<Rec> deliverables;
  final List<Rec> receipts;
  final List<Rec> invoices;
  final List<Rec> expenses;
  final Map<String, List<Rec>> metricsByDeliverable;
  final List<Rec> products;
  final String? coverImage;

  CollabView(this.row, this.brandName, this.deliverables, this.receipts, this.invoices, this.expenses,
      this.metricsByDeliverable, this.products, this.coverImage);

  String get id => str(row['id']);
  String get title => str(row['title']);
  String get stage => str(row['stage']);
  String get dealType => str(row['deal_type']);
  bool get active => isActiveStage(stage);
  double get agreed => toD(row['agreed_amount']);
  bool get hasBarter => dealType != kPaid;
  bool get hasCash => dealType != kBarter;

  /// Barter value = linked products (price × qty) when any, otherwise the value typed on the collab.
  double get barterValue {
    if (!hasBarter) return 0;
    if (products.isNotEmpty) {
      return products.fold(0.0, (a, p) => a + toD(p['purchase_price']) * (toI(p['quantity']) <= 0 ? 1 : toI(p['quantity'])));
    }
    return toD(row['barter_value']);
  }

  /// Barter counts as earned once the deal is confirmed (and not cancelled).
  double get barterEarned => (stage == 'Talking' || stage == kCancelled) ? 0 : barterValue;

  /// Date used to place barter earnings in a period: posted date, else start date, else created.
  DateTime? get barterDate =>
      parseDate(postedDate) ?? parseDate(row['start_date']) ?? parseDate(str(row['created_at']).split('T').first);

  double get totalValue => (hasCash ? agreed : 0) + barterValue;
  double get earned => received + barterEarned;
  double get netReceived => receipts.fold(0.0, (a, r) => a + toD(r['amount']));
  double get tds => receipts.fold(0.0, (a, r) => a + toD(r['tds']));

  /// Settled = credited + TDS deducted at source.
  double get received => netReceived + tds;
  double get pending => (stage == kCancelled || !hasCash) ? 0 : max(0.0, agreed - received);
  double get expenseTotal => expenses.fold(0.0, (a, r) => a + toD(r['amount']));
  double get profit => received + barterEarned - expenseTotal;
  double get gstBilled => invoices.fold(0.0, (a, r) => a + toD(r['gst_amount']));

  bool get isBarter => dealType == kBarter;

  /// Date the first reel/post of this collab went live (null if nothing posted yet).
  String? get postedDate {
    final l = deliverables
        .where((d) => d['status'] == 'Live' && str(d['live_date']).isNotEmpty)
        .map((d) => str(d['live_date']))
        .toList()
      ..sort();
    return l.isEmpty ? null : l.first;
  }

  int get liveCount => deliverables.where((d) => d['status'] == 'Live').length;
  int get approvedOrLive => deliverables.where((d) => d['status'] == 'Approved' || d['status'] == 'Live').length;

  String? get dueDate {
    final d = str(row['payment_due_date']);
    if (d.isNotEmpty) return d;
    final inv = invoices.map((e) => str(e['due_date'])).where((e) => e.isNotEmpty).toList()..sort();
    return inv.isEmpty ? null : inv.first;
  }

  String get paymentStatus {
    if (stage == kCancelled) return 'Cancelled';
    if (!hasCash) return 'Barter';
    if (agreed <= 0) return 'No amount';
    if (received >= agreed - 0.5) return 'Paid';
    if (dueDate != null && daysFromToday(dueDate) < 0) return 'Overdue';
    if (received > 0) return 'Partial';
    return 'Unpaid';
  }

  List<Rec> metricsFor(String deliverableId) => metricsByDeliverable[deliverableId] ?? const [];

  /// The next dated thing to do on this collab.
  (String, String)? get nextAction {
    final items = <(String, String)>[];
    final na = str(row['next_action']);
    final nad = str(row['next_action_date']);
    if (na.isNotEmpty && nad.isNotEmpty) items.add((na, nad));
    for (final d in deliverables) {
      final name = '${str(d['type'])}${str(d['title']).isEmpty ? '' : ' · ${str(d['title'])}'}';
      final st = str(d['status']);
      if (st != 'Live' && st != 'Approved' && str(d['due_date']).isNotEmpty) {
        items.add(('$name draft due', str(d['due_date'])));
      }
      if (st != 'Live' && str(d['live_date']).isNotEmpty) items.add(('$name go-live', str(d['live_date'])));
    }
    if (pending > 0 && dueDate != null) items.add(('Payment due', dueDate!));
    if (items.isEmpty) return na.isEmpty ? null : (na, '');
    items.sort((a, b) => a.$2.compareTo(b.$2));
    return items.first;
  }

  List<bool> checklistOf(Rec d) {
    try {
      final l = jsonDecode(str(d['checklist'])) as List;
      return List<bool>.generate(kChecklist.length, (i) => i < l.length && l[i] == true);
    } catch (_) {
      return List<bool>.filled(kChecklist.length, false);
    }
  }
}

/// Everything loaded into memory for dashboards, lists and reports.
/// A creator's dataset is small, so one load per screen keeps logic simple and consistent.
class Snapshot {
  final List<Rec> brands;
  final List<Rec> contacts;
  final List<CollabView> collabs;
  final List<Rec> deliverables;
  final List<Rec> metrics;
  final List<Rec> receipts;
  final List<Rec> invoices;
  final List<Rec> products;
  final Map<String, String> brandNames;
  final Map<String, String> productImage;

  Snapshot(this.brands, this.contacts, this.collabs, this.deliverables, this.metrics, this.receipts, this.invoices,
      this.products, this.brandNames, this.productImage);

  static Future<Snapshot> load() async {
    final brands = await Repo.all('brands', orderBy: 'name COLLATE NOCASE');
    final contacts = await Repo.all('contacts', orderBy: 'name COLLATE NOCASE');
    final collabs = await Repo.all('collabs', orderBy: 'updated_at DESC');
    final dels = await Repo.all('deliverables', orderBy: 'due_date');
    final metrics = await Repo.all('metrics', orderBy: 'captured_at');
    final pays = await Repo.all('payments', orderBy: 'received_date DESC');
    final invs = await Repo.all('invoices', orderBy: 'invoice_date DESC');
    final exps = await Repo.all('expenses', orderBy: 'date DESC');
    final products = await Repo.all('products', orderBy: 'name COLLATE NOCASE');
    final images = await Repo.all('product_images', orderBy: 'sort, created_at');
    final firstImage = <String, String>{};
    for (final i in images) {
      firstImage.putIfAbsent(str(i['product_id']), () => str(i['file_name']));
    }

    final names = {for (final b in brands) str(b['id']): str(b['name'])};
    List<Rec> by(List<Rec> l, String id) => l.where((e) => e['collab_id'] == id).toList();
    final mByD = <String, List<Rec>>{};
    for (final m in metrics) {
      mByD.putIfAbsent(str(m['deliverable_id']), () => []).add(m);
    }
    final views = collabs.map((c) {
      final id = str(c['id']);
      final ds = by(dels, id);
      final mm = {for (final d in ds) str(d['id']): mByD[str(d['id'])] ?? <Rec>[]};
      final ps = by(products, id);
      String? cover;
      for (final p in ps) {
        cover ??= firstImage[str(p['id'])];
      }
      return CollabView(
          c, names[str(c['brand_id'])] ?? 'Unknown brand', ds, by(pays, id), by(invs, id), by(exps, id), mm, ps, cover);
    }).toList();
    return Snapshot(brands, contacts, views, dels, metrics, pays, invs, products, names, firstImage);
  }

  CollabView? collab(String id) {
    for (final c in collabs) {
      if (c.id == id) return c;
    }
    return null;
  }

  String collabTitle(String id) => collab(id)?.title ?? '';

  /// Latest snapshot whose label is 7d (fallback: latest of any label).
  static Rec? bestMetric(List<Rec> ms, [String label = '7d']) {
    if (ms.isEmpty) return null;
    final l = ms.where((m) => m['label'] == label).toList();
    return l.isNotEmpty ? l.last : null;
  }
}
