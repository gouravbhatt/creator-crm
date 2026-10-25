import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/snapshot.dart';
import 'widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with AutoReload {
  Snapshot? _s;
  String _period = 'This FY';
  static const _periods = ['This FY', 'Last FY', 'Last 12 months', 'All time'];

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    if (mounted) setState(() => _s = s);
  }

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    final fy = fyStart(now);
    switch (_period) {
      case 'Last FY':
        return (DateTime(fy.year - 1, 4, 1), fy);
      case 'Last 12 months':
        return (DateTime(now.year - 1, now.month + 1, 1), DateTime(now.year, now.month + 1, 1));
      case 'All time':
        return (DateTime(2000), DateTime(now.year + 5));
      default:
        return (fy, DateTime(fy.year + 1, 4, 1));
    }
  }

  bool _in(Object? date, (DateTime, DateTime) r) {
    final d = parseDate(date);
    return d != null && !d.isBefore(r.$1) && d.isBefore(r.$2);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _period = v),
            itemBuilder: (_) => _periods.map((p) => CheckedPopupMenuItem(value: p, checked: p == _period, child: Text(p))).toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [Text(_period), const Icon(Icons.arrow_drop_down)]),
            ),
          ),
        ],
      ),
      body: s == null ? const Center(child: CircularProgressIndicator()) : _body(s),
    );
  }

  Widget _body(Snapshot s) {
    final r = _range();
    final receipts = s.receipts.where((x) => _in(x['received_date'], r)).toList();
    final received = receipts.fold(0.0, (a, x) => a + toD(x['amount']) + toD(x['tds']));
    final tds = receipts.fold(0.0, (a, x) => a + toD(x['tds']));
    final collabs = s.collabs.where((c) => _in(c.row['created_at'], r)).toList();
    final won = collabs.where((c) => c.stage != kCancelled && stageIndex(c.stage) >= stageIndex('Contract')).toList();
    final decided = collabs.where((c) => c.stage == kCancelled || stageIndex(c.stage) >= stageIndex('Contract')).length;
    final winRate = decided == 0 ? 0.0 : won.length * 100 / decided;
    final avgDeal = won.isEmpty ? 0.0 : won.fold(0.0, (a, c) => a + c.agreed) / won.length;
    final outstanding = s.collabs.fold(0.0, (a, c) => a + c.pending);
    final gst = s.invoices.where((i) => _in(i['invoice_date'], r)).fold(0.0, (a, i) => a + toD(i['gst_amount']));
    final barter = collabs.fold(0.0, (a, c) => a + c.barterValue);
    final expenses = collabs.fold(0.0, (a, c) => a + c.expenseTotal);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      StatGrid(children: [
        StatTile(label: 'Received', value: money(received)),
        StatTile(label: 'Avg deal size', value: money(avgDeal), sub: '${won.length} confirmed'),
        StatTile(label: 'Win rate', value: '${winRate.toStringAsFixed(0)}%', sub: 'Contract or later vs cancelled'),
        StatTile(label: 'Outstanding (now)', value: money(outstanding)),
      ]),
      SectionCard(title: 'Revenue by month', child: SizedBox(height: 180, child: _monthly(s, r))),
      SectionCard(title: 'Top brands by revenue', child: _topBrands(s, receipts)),
      SectionCard(title: 'Receivables aging', child: _aging(s)),
      SectionCard(
        title: 'Tax & costs',
        child: Column(children: [
          KV('TDS deducted', money(tds)),
          KV('GST billed', money(gst)),
          KV('Barter value received', money(barter)),
          KV('Expenses on collabs', money(expenses)),
          const SizedBox(height: 4),
          const Text('For reference only — reconcile with Form 26AS / your CA.', style: TextStyle(fontSize: 11, color: kMuted)),
        ]),
      ),
      SectionCard(title: 'Content & delivery', child: _content(s, r)),
      SectionCard(title: 'Rate card (from your history)', child: _rateCard(s)),
      SectionCard(title: 'Brand scorecard', child: _scorecard(s)),
    ]);
  }

  Widget _monthly(Snapshot s, (DateTime, DateTime) r) {
    final now = DateTime.now();
    var start = _period == 'All time' ? DateTime(now.year, now.month - 11, 1) : DateTime(r.$1.year, r.$1.month, 1);
    final months = <DateTime>[];
    while (start.isBefore(r.$2) && months.length < 12) {
      months.add(start);
      start = DateTime(start.year, start.month + 1, 1);
    }
    final vals = months.map((m) {
      final n = DateTime(m.year, m.month + 1, 1);
      return s.receipts.where((x) {
        final d = parseDate(x['received_date']);
        return d != null && !d.isBefore(m) && d.isBefore(n);
      }).fold(0.0, (a, x) => a + toD(x['amount']) + toD(x['tds']));
    }).toList();
    final maxV = vals.fold(0.0, (a, b) => b > a ? b : a);
    return BarChart(BarChartData(
      maxY: maxV <= 0 ? 1 : maxV * 1.15,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (g, gi, rod, ri) =>
              BarTooltipItem(money(rod.toY), const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= months.length) return const SizedBox.shrink();
              return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(monthLabel(months[i]).substring(0, 1), style: const TextStyle(fontSize: 11, color: kMuted)));
            },
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < vals.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: vals[i],
              width: 14,
              color: months[i].isAfter(now) ? const Color(0xFFC9D2F7) : kPrimary,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ]),
      ],
    ));
  }

  Widget _topBrands(Snapshot s, List<Map<String, dynamic>> receipts) {
    final byBrand = <String, double>{};
    final counts = <String, Set<String>>{};
    for (final x in receipts) {
      final c = s.collab(str(x['collab_id']));
      if (c == null) continue;
      byBrand[c.brandName] = (byBrand[c.brandName] ?? 0.0) + toD(x['amount']) + toD(x['tds']);
      counts.putIfAbsent(c.brandName, () => {}).add(c.id);
    }
    if (byBrand.isEmpty) return const Text('No revenue in this period.', style: TextStyle(color: kMuted));
    final e = byBrand.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = e.take(8).toList();
    final maxV = top.first.value;
    return Column(
        children: top
            .map((x) => BarLine(label: x.key, fraction: maxV == 0 ? 0 : x.value / maxV, value: money(x.value)))
            .toList());
  }

  Widget _aging(Snapshot s) {
    final b = <String, double>{'Not due': 0, '1–30 days': 0, '31–60 days': 0, '60+ days': 0};
    var days = 0.0;
    var paidCount = 0;
    for (final c in s.collabs) {
      if (c.pending > 0) {
        final d = -daysFromToday(c.dueDate);
        final key = c.dueDate == null || d <= 0
            ? 'Not due'
            : d <= 30
                ? '1–30 days'
                : d <= 60
                    ? '31–60 days'
                    : '60+ days';
        b[key] = b[key]! + c.pending;
      }
      if (c.receipts.isNotEmpty && c.pending <= 0) {
        final last = parseDate(c.receipts.first['received_date']);
        final ref = parseDate(c.row['publish_date']) ??
            c.deliverables.map((d) => parseDate(d['live_date'])).whereType<DateTime>().fold<DateTime?>(null, (a, x) => a == null || x.isAfter(a) ? x : a);
        if (last != null && ref != null) {
          days += last.difference(ref).inDays;
          paidCount++;
        }
      }
    }
    final total = b.values.fold(0.0, (a, v) => a + v);
    final colors = [kOk, const Color(0xFFE8A33A), kWarn, kDanger];
    var i = 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...b.entries.map((e) => BarLine(label: e.key, fraction: total == 0 ? 0 : e.value / total, value: money(e.value), color: colors[i++])),
      const SizedBox(height: 6),
      Text(paidCount == 0 ? 'Avg days to get paid: not enough data' : 'Avg days from go-live to full payment: ${(days / paidCount).toStringAsFixed(0)}',
          style: const TextStyle(fontSize: 12, color: kMuted)),
    ]);
  }

  Widget _content(Snapshot s, (DateTime, DateTime) r) {
    final ds = s.deliverables.where((d) => _in(d['due_date'] ?? d['created_at'], r) || _in(d['created_at'], r)).toList();
    final live = ds.where((d) => d['status'] == 'Live').toList();
    final onTime = live.where((d) {
      final due = parseDate(d['due_date']);
      final ld = parseDate(d['live_date']);
      return due == null || ld == null || !ld.isAfter(due.add(const Duration(days: 1)));
    }).length;
    final revs = ds.isEmpty ? 0.0 : ds.fold(0, (a, d) => a + toI(d['revision_count'])) / ds.length;
    final views = <int>[];
    var feeWithViews = 0.0;
    var viewsTotal = 0;
    final seenCollabs = <String>{};
    for (final d in live) {
      final m = Snapshot.bestMetric(s.metrics.where((x) => x['deliverable_id'] == d['id']).toList());
      if (m == null) continue;
      views.add(toI(m['views']));
      viewsTotal += toI(m['views']);
      final c = s.collab(str(d['collab_id']));
      if (c != null && seenCollabs.add(c.id)) feeWithViews += c.agreed;
    }
    views.sort();
    final median = views.isEmpty ? 0 : views[views.length ~/ 2];
    return Column(children: [
      KV('Deliverables live / total', '${live.length} / ${ds.length}'),
      KV('On-time delivery', live.isEmpty ? '—' : '${(onTime * 100 / live.length).toStringAsFixed(0)}%'),
      KV('Avg revisions', revs.toStringAsFixed(1)),
      KV('Median 7-day views', views.isEmpty ? '—' : plainNum(median)),
      KV('Earnings per 1K views', viewsTotal == 0 ? '—' : money(feeWithViews / viewsTotal * 1000)),
    ]);
  }

  Widget _rateCard(Snapshot s) {
    final per = <String, List<double>>{};
    for (final c in s.collabs.where((c) => c.agreed > 0 && c.deliverables.isNotEmpty && c.stage != kCancelled)) {
      final each = c.agreed / c.deliverables.length;
      for (final d in c.deliverables) {
        per.putIfAbsent(str(d['type']), () => []).add(each);
      }
    }
    if (per.isEmpty) return const Text('Add paid collabs with deliverables to see your typical rates.', style: TextStyle(color: kMuted));
    return Column(children: [
      ...per.entries.map((e) {
        final l = e.value..sort();
        final avg = l.fold(0.0, (a, v) => a + v) / l.length;
        return KV(e.key, '${money(avg)} avg · range ${money(l.first)}–${money(l.last)} · ${l.length} done');
      }),
      const SizedBox(height: 4),
      const Text('Fee split equally across deliverables in each collab.', style: TextStyle(fontSize: 11, color: kMuted)),
    ]);
  }

  Widget _scorecard(Snapshot s) {
    final byBrand = <String, List<CollabView>>{};
    for (final c in s.collabs) {
      byBrand.putIfAbsent(c.brandName, () => []).add(c);
    }
    if (byBrand.isEmpty) return const Text('No collabs yet.', style: TextStyle(color: kMuted));
    final rows = byBrand.entries.toList()
      ..sort((a, b) => b.value.fold(0.0, (x, c) => x + c.received).compareTo(a.value.fold(0.0, (x, c) => x + c.received)));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        headingRowHeight: 36,
        columns: const [
          DataColumn(label: Text('Brand')),
          DataColumn(label: Text('Collabs'), numeric: true),
          DataColumn(label: Text('Received'), numeric: true),
          DataColumn(label: Text('Avg deal'), numeric: true),
          DataColumn(label: Text('Revisions'), numeric: true),
          DataColumn(label: Text('Pending'), numeric: true),
        ],
        rows: rows.map((e) {
          final l = e.value;
          final recv = l.fold(0.0, (a, c) => a + c.received);
          final avg = l.fold(0.0, (a, c) => a + c.agreed) / l.length;
          final ds = l.expand((c) => c.deliverables).toList();
          final rev = ds.isEmpty ? 0.0 : ds.fold(0, (a, d) => a + toI(d['revision_count'])) / ds.length;
          final pend = l.fold(0.0, (a, c) => a + c.pending);
          return DataRow(cells: [
            DataCell(Text(e.key)),
            DataCell(Text('${l.length}')),
            DataCell(Text(money(recv))),
            DataCell(Text(money(avg))),
            DataCell(Text(rev.toStringAsFixed(1))),
            DataCell(Text(money(pend), style: TextStyle(color: pend > 0 ? kDanger : null))),
          ]);
        }).toList(),
      ),
    );
  }
}
