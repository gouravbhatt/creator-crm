import 'constants.dart';
import 'format.dart';
import 'repo.dart';
import 'snapshot.dart';

/// Date range filter shared by Dashboard and Reports.
class Period {
  final String key;
  final DateTime start; // inclusive
  final DateTime end; // exclusive
  const Period(this.key, this.start, this.end);

  static const List<String> keys = ['This month', 'Quarter', 'This FY', 'Last FY', 'All time'];

  static Period of(String key, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final fy = fyStart(n);
    switch (key) {
      case 'This month':
        return Period(key, DateTime(n.year, n.month, 1), DateTime(n.year, n.month + 1, 1));
      case 'Quarter':
        final qm = ((n.month - 1) ~/ 3) * 3 + 1;
        return Period(key, DateTime(n.year, qm, 1), DateTime(n.year, qm + 3, 1));
      case 'Last FY':
        return Period(key, DateTime(fy.year - 1, 4, 1), fy);
      case 'All time':
        return Period(key, DateTime(2000), DateTime(n.year + 5));
      default:
        return Period('This FY', fy, DateTime(fy.year + 1, 4, 1));
    }
  }

  /// Length-equal previous window (for "vs previous period").
  Period previous() {
    if (key == 'All time') return this;
    final months = (end.year - start.year) * 12 + end.month - start.month;
    return Period(key, DateTime(start.year, start.month - months, 1), start);
  }

  bool has(DateTime? d) => d != null && !d.isBefore(start) && d.isBefore(end);
  bool hasStr(Object? s) => has(parseDate(s));

  /// Up to 12 month starts covered by this period (last 12 for long periods).
  List<DateTime> months() {
    final now = DateTime.now();
    var e = end.isAfter(DateTime(now.year, now.month + 1, 1)) && key == 'All time' ? DateTime(now.year, now.month + 1, 1) : end;
    var s = DateTime(start.year, start.month, 1);
    final out = <DateTime>[];
    while (s.isBefore(e)) {
      out.add(s);
      s = DateTime(s.year, s.month + 1, 1);
    }
    if (key == 'This month') {
      // Show last 6 months for context on the chart.
      return List.generate(6, (i) => DateTime(now.year, now.month - 5 + i, 1));
    }
    return out.length > 12 ? out.sublist(out.length - 12) : out;
  }
}

class Earnings {
  double cash = 0; // collab fees received (credited + TDS) in period
  double ugc = 0; // part of cash from UGC collabs
  double barter = 0; // product value kept in period
  double affiliate = 0; // affiliate gross earned in period
  double other = 0; // other income gross in period
  double expenses = 0;
  double agencyCuts = 0;
  double tds = 0; // brand TDS
  double tdsIncome = 0; // affiliate / other TDS
  double refundsIn = 0; // refunds received (not income)
  double incomeNetPaid = 0; // affiliate/other actually paid to bank
  double incomePending = 0; // affiliate/other not yet paid
  int paidCollabs = 0;
  int barterCollabs = 0;
  int payments = 0;
  final Set<String> collabIds = {};
  double get collabTotal => cash + barter;
  double get total => cash + barter + affiliate + other;
  double get net => total - expenses;
  double get cashInBank => (cash - tds) + refundsIn + incomeNetPaid;
  double get allTds => tds + tdsIncome;
}

/// Type filter values used by Home / Reports.
const List<String> kTypeFilters = ['All', kPaid, kBarter, kBoth, kOrder, kUgc, kCommission, kGifting, kEvent];

List<CollabView> filterCollabs(Snapshot s, {String type = 'All', String? brandId, String? platform, String? source}) {
  return s.collabs.where((c) {
    if (type != 'All' && c.kind != type) return false;
    if (brandId != null && c.row['brand_id'] != brandId) return false;
    if (source != null && c.source != source) return false;
    if (platform != null && !c.deliverables.any((d) => d['platform'] == platform)) return false;
    return true;
  }).toList();
}

/// Month key yyyy-MM of an income row as a date (1st of month).
DateTime? incomeMonth(Rec r) => parseDate('${str(r['month'])}-01');

Earnings computeEarnings(List<CollabView> collabs, Period p, {List<Rec> income = const [], bool includeIncome = true}) {
  final e = Earnings();
  for (final c in collabs) {
    var touched = false;
    var cashHere = false;
    for (final r in c.receipts) {
      if (!p.hasStr(r['received_date'])) continue;
      if (r['kind'] == 'Refund') {
        e.refundsIn += toD(r['amount']);
        continue;
      }
      final v = toD(r['amount']) + toD(r['tds']);
      e.cash += v;
      if (c.isUgc) e.ugc += v;
      e.tds += toD(r['tds']);
      e.payments++;
      touched = true;
      cashHere = true;
    }
    if (c.barterEarned > 0 && p.has(c.barterDate)) {
      e.barter += c.barterEarned;
      e.barterCollabs++;
      touched = true;
    }
    for (final x in c.expenses) {
      if (p.hasStr(x['date'])) e.expenses += toD(x['amount']);
    }
    if (cashHere) {
      e.paidCollabs++;
      e.agencyCuts += c.agencyCut * (c.agreed <= 0 ? 0 : (c.feeReceived / (c.feeNet <= 0 ? 1 : c.feeNet)).clamp(0, 1));
    }
    if (touched) e.collabIds.add(c.id);
  }
  if (includeIncome) {
    for (final r in income) {
      if (!p.has(incomeMonth(r))) continue;
      final g = toD(r['gross']);
      if (r['source_type'] == 'Affiliate') {
        e.affiliate += g;
      } else {
        e.other += g;
      }
      e.tdsIncome += toD(r['tds']);
      if (r['status'] == 'Paid') {
        e.incomeNetPaid += toD(r['net_paid']) > 0 ? toD(r['net_paid']) : g - toD(r['tds']);
      } else {
        e.incomePending += g - toD(r['tds']);
      }
    }
  }
  return e;
}

/// Cash, barter and affiliate/other per month for charts.
List<(DateTime, double, double, double)> monthlySeries(List<CollabView> collabs, Period p, {List<Rec> income = const []}) {
  return p.months().map((m) {
    final mp = Period('m', m, DateTime(m.year, m.month + 1, 1));
    final e = computeEarnings(collabs, mp, income: income);
    return (m, e.cash, e.barter, e.affiliate + e.other);
  }).toList();
}
