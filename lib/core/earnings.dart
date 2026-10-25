import 'constants.dart';
import 'format.dart';
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
  double cash = 0; // received (credited + TDS) in period
  double barter = 0; // barter value earned in period
  double expenses = 0;
  double tds = 0;
  int paidCollabs = 0;
  int barterCollabs = 0;
  int payments = 0;
  final Set<String> collabIds = {};
  double get total => cash + barter;
  double get net => total - expenses;
}

/// Filters collabs by type ('All', 'Paid', 'Barter', 'Both'), brand and platform.
List<CollabView> filterCollabs(Snapshot s, {String type = 'All', String? brandId, String? platform}) {
  return s.collabs.where((c) {
    if (type == kPaid && c.dealType != kPaid) return false;
    if (type == kBarter && c.dealType != kBarter) return false;
    if ((type == 'Both' || type == kBoth) && c.dealType != kBoth) return false;
    if (brandId != null && c.row['brand_id'] != brandId) return false;
    if (platform != null && !c.deliverables.any((d) => d['platform'] == platform)) return false;
    return true;
  }).toList();
}

Earnings computeEarnings(List<CollabView> collabs, Period p) {
  final e = Earnings();
  for (final c in collabs) {
    var touched = false;
    for (final r in c.receipts) {
      if (p.hasStr(r['received_date'])) {
        e.cash += toD(r['amount']) + toD(r['tds']);
        e.tds += toD(r['tds']);
        e.payments++;
        touched = true;
      }
    }
    if (c.barterEarned > 0 && p.has(c.barterDate)) {
      e.barter += c.barterEarned;
      e.barterCollabs++;
      touched = true;
    }
    for (final x in c.expenses) {
      if (p.hasStr(x['date'])) e.expenses += toD(x['amount']);
    }
    if (touched && c.hasCash && c.receipts.any((r) => p.hasStr(r['received_date']))) e.paidCollabs++;
    if (touched) e.collabIds.add(c.id);
  }
  return e;
}

/// Cash and barter per month for charts.
List<(DateTime, double, double)> monthlySeries(List<CollabView> collabs, Period p) {
  return p.months().map((m) {
    final mp = Period('m', m, DateTime(m.year, m.month + 1, 1));
    final e = computeEarnings(collabs, mp);
    return (m, e.cash, e.barter);
  }).toList();
}
