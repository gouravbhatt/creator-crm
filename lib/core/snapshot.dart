import 'dart:convert';
import 'dart:math';

import 'constants.dart';
import 'format.dart';
import 'repo.dart';

/// A collab with its children and derived money/delivery state.
///
/// Money rules (same everywhere in the app):
/// * Income  = fee received (incl. TDS, after agency cut) + value of products you keep.
/// * Refunds = money back for a product you bought; NOT income.
/// * Pending = (fee after agency cut − fee received) + (refund − refund received).
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
  final Rec? contact;

  CollabView(this.row, this.brandName, this.deliverables, this.receipts, this.invoices, this.expenses,
      this.metricsByDeliverable, this.products, this.coverImage, this.contact);

  String get id => str(row['id']);
  String get title => str(row['title']);
  String get stage => str(row['stage']);
  String get dealType => str(row['deal_type']).isEmpty ? kPaid : str(row['deal_type']);
  String get kind => dealType;
  String get source => str(row['source']);
  String get agencyName => str(row['agency_name']);
  bool get active => isActiveStage(stage);
  bool get cancelled => stage == kCancelled;
  bool get isOrder => kind == kOrder;
  bool get isUgc => kind == kUgc;
  String get feeMode => str(row['fee_mode']).isEmpty ? (isOrder ? kFeeNone : kFeeTop) : str(row['fee_mode']);

  // ---------- add-ons ----------
  List<Map<String, dynamic>> get addons {
    try {
      return (jsonDecode(str(row['addons'])) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  double get addonsTotal => addons.fold(0.0, (a, e) => a + toD(e['amount']));

  // ---------- fee ----------
  double get baseFee => toD(row['agreed_amount']);

  /// Gross fee incl. add-ons (before agency cut).
  double get agreed => baseFee + addonsTotal;
  double get agencyPct => toD(row['agency_pct']);
  double get agencyCut => agreed * agencyPct / 100;
  double get feeNet => agreed - agencyCut;
  bool get hasCash => agreed > 0 || kindHasFee(kind) || (isOrder && feeMode != kFeeNone);

  // ---------- refund (order & refund) ----------
  double get refundAmount => isOrder ? toD(row['refund_amount']) : 0;
  bool get orderPlaced => isOrder && (str(row['order_no']).isNotEmpty || str(row['order_date']).isNotEmpty || stageIndex(stage) >= 1);

  // ---------- receipts ----------
  bool _isRefund(Rec r) => r['kind'] == 'Refund';
  double get feeReceived => receipts.where((r) => !_isRefund(r)).fold(0.0, (a, r) => a + toD(r['amount']) + toD(r['tds']));
  double get refundReceived => receipts.where(_isRefund).fold(0.0, (a, r) => a + toD(r['amount']));
  double get netReceived => receipts.fold(0.0, (a, r) => a + toD(r['amount']));
  double get tds => receipts.fold(0.0, (a, r) => a + toD(r['tds']));

  /// Cash income received (fees incl. TDS). Refunds excluded.
  double get received => feeReceived;
  double get pendingFee => cancelled ? 0 : max(0.0, feeNet - feeReceived);
  double get pendingRefund => max(0.0, ((cancelled && !orderPlaced) ? 0 : refundAmount) - refundReceived);
  double get pending => pendingFee + pendingRefund;

  /// Your own money still out on product purchases.
  double get moneyOut => orderPlaced ? max(0.0, refundAmount - refundReceived) : 0;

  // ---------- products / barter ----------
  bool get hasBarter => kindHasProduct(kind) || products.isNotEmpty || toD(row['barter_value']) > 0;

  double get barterValue {
    if (products.isNotEmpty) {
      return products.fold(0.0, (a, p) => a + toD(p['purchase_price']) * (toI(p['quantity']) <= 0 ? 1 : toI(p['quantity'])));
    }
    if (isOrder) return refundAmount;
    return toD(row['barter_value']);
  }

  /// Product value counted as income: barter once confirmed; order & refund once the refund is in.
  double get barterEarned {
    if (cancelled || stage == 'Lead') return 0;
    if (isOrder) return (refundAmount > 0 && refundReceived >= refundAmount - 0.5) ? barterValue : 0;
    return hasBarter ? barterValue : 0;
  }

  DateTime? get barterDate {
    if (isOrder) {
      final r = receipts.where(_isRefund).map((r) => str(r['received_date'])).toList()..sort();
      if (r.isNotEmpty) return parseDate(r.last);
    }
    return parseDate(postedDate) ?? parseDate(row['start_date']) ?? parseDate(str(row['created_at']).split('T').first);
  }

  /// What the deal is worth to you (fee after agency + product kept).
  double get totalValue => (hasCash ? feeNet : 0) + (hasBarter ? barterValue : 0);
  double get earned => received + barterEarned;
  double get expenseTotal => expenses.fold(0.0, (a, r) => a + toD(r['amount']));
  double get profit => earned - expenseTotal;
  double get gstBilled => invoices.fold(0.0, (a, r) => a + toD(r['gst_amount']));

  bool get isBarter => kind == kBarter || kind == kGifting;

  /// Date the first deliverable went live/was delivered.
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
    if (cancelled && pending <= 0.5) return 'Cancelled';
    if (!hasCash && refundAmount <= 0) return 'Barter';
    if (pending <= 0.5) return 'Paid';
    if (dueDate != null && daysFromToday(dueDate) < 0) return 'Overdue';
    if (feeReceived > 0 || refundReceived > 0) return 'Partial';
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
      final name = '${str(d['type'])}${str(d['title']).isEmpty ? '' : ' ${str(d['title'])}'}';
      if (str(d['status']) != 'Live' && str(d['due_date']).isNotEmpty) {
        items.add(('${isUgcDeliverable(d) ? 'Deliver' : 'Post'} $name', str(d['due_date'])));
      }
    }
    if (pending > 0 && dueDate != null) items.add((pendingRefund > 0 && pendingFee <= 0 ? 'Refund due' : 'Payment due', dueDate!));
    if (str(row['event_date']).isNotEmpty && daysFromToday(row['event_date']) >= 0) items.add(('Event', str(row['event_date'])));
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
class Snapshot {
  final List<Rec> brands;
  final List<Rec> contacts;
  final List<CollabView> collabs;
  final List<Rec> deliverables;
  final List<Rec> metrics;
  final List<Rec> receipts;
  final List<Rec> invoices;
  final List<Rec> products;
  final List<Rec> income;
  final Map<String, String> brandNames;
  final Map<String, String> productImage;

  Snapshot(this.brands, this.contacts, this.collabs, this.deliverables, this.metrics, this.receipts, this.invoices,
      this.products, this.income, this.brandNames, this.productImage);

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
    final income = await Repo.all('income', orderBy: 'month DESC, platform');
    final images = await Repo.all('product_images', orderBy: 'sort, created_at');
    final firstImage = <String, String>{};
    for (final i in images) {
      firstImage.putIfAbsent(str(i['product_id']), () => str(i['file_name']));
    }

    final names = {for (final b in brands) str(b['id']): str(b['name'])};
    final contactById = {for (final c in contacts) str(c['id']): c};
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
      return CollabView(c, names[str(c['brand_id'])] ?? 'Unknown brand', ds, by(pays, id), by(invs, id), by(exps, id), mm, ps,
          cover, contactById[str(c['contact_id'])]);
    }).toList();
    return Snapshot(brands, contacts, views, dels, metrics, pays, invs, products, income, names, firstImage);
  }

  CollabView? collab(String id) {
    for (final c in collabs) {
      if (c.id == id) return c;
    }
    return null;
  }

  String collabTitle(String id) => collab(id)?.title ?? '';

  /// Latest snapshot with the given label.
  static Rec? bestMetric(List<Rec> ms, [String label = '7d']) {
    if (ms.isEmpty) return null;
    final l = ms.where((m) => m['label'] == label).toList();
    return l.isNotEmpty ? l.last : null;
  }
}
