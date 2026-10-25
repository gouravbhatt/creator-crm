import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/earnings.dart';
import '../core/format.dart';
import '../core/snapshot.dart';
import 'backup_screen.dart';
import 'collabs_screens.dart';
import 'v2_widgets.dart';
import 'widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with AutoReload {
  Snapshot? _s;
  String _period = 'This FY';
  String _type = 'All';
  String? _brand;
  String? _platform;

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonal(onPressed: () => push(context, const BackupScreen()), child: const Text('Export')),
          ),
        ],
      ),
      body: s == null ? const Center(child: CircularProgressIndicator()) : _body(s),
    );
  }

  Widget _filters(Snapshot s) {
    final platforms = s.deliverables.map((d) => str(d['platform'])).where((p) => p.isNotEmpty).toSet().toList()..sort();
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PillRow(options: Period.keys, value: _period, onChanged: (v) => setState(() => _period = v)),
        const SizedBox(height: 10),
        Segmented(options: const ['All', kPaid, kBarter, 'Both'], value: _type, onChanged: (v) => setState(() => _type = v)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _brand,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Brand', isDense: true),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('All brands')),
                ...s.brands.map((b) => DropdownMenuItem<String>(
                    value: str(b['id']), child: Text(str(b['name']), overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => setState(() => _brand = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _platform,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Platform', isDense: true),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('All')),
                ...platforms.map((p) => DropdownMenuItem<String>(value: p, child: Text(p))),
              ],
              onChanged: (v) => setState(() => _platform = v),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('Every number below follows these filters.', style: TextStyle(fontSize: 11, color: kMuted)),
      ]),
    );
  }

  Widget _body(Snapshot s) {
    final p = Period.of(_period);
    final list = filterCollabs(s, type: _type, brandId: _brand, platform: _platform);
    final e = computeEarnings(list, p);
    final prev = computeEarnings(list, p.previous());
    final change = (p.key == 'All time' || prev.total <= 0) ? null : (e.total - prev.total) * 100 / prev.total;
    final pending = list.fold<double>(0, (a, c) => a + c.pending);
    final overdue = list.where((c) => c.paymentStatus == 'Overdue').length;
    final inPeriod = list.where((c) => e.collabIds.contains(c.id)).toList();

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
      _filters(s),
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total earned (cash + barter)', style: TextStyle(color: Color(0xFFDCD4FF), fontSize: 12)),
          FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(money(e.total), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800))),
          Text(
              '${change == null ? '' : '${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(0)}% vs previous · '}net profit ${money(e.net)}',
              style: const TextStyle(color: Color(0xFFDCD4FF), fontSize: 12)),
        ]),
      ),
      StatGrid(children: [
        StatTile(label: 'Cash received', value: money(e.cash), sub: '${e.payments} payments', color: kPrimary),
        StatTile(label: 'Barter value', value: money(e.barter), sub: '${e.barterCollabs} collabs', color: kBarterC),
        StatTile(label: 'Pending now', value: money(pending), sub: '$overdue overdue', color: pending > 0 ? kDanger : null),
        StatTile(label: 'Expenses', value: money(e.expenses), sub: 'editor, props, travel'),
      ]),
      Panel(
        title: 'Cash vs barter by month',
        child: SizedBox(height: 170, child: _chart(list, p)),
      ),
      Panel(title: 'By collab type', child: _byType(list, p)),
      Panel(title: 'Top brands', child: _topBrands(list, p)),
      Panel(title: 'Content', child: _content(s, list, inPeriod, p, e)),
      Panel(title: 'Money owed & tax', child: _owed(list, e)),
      if (_type != kPaid) Panel(title: 'Barter products in this period', child: _barterList(s, list, p)),
    ]);
  }

  Widget _chart(List<CollabView> list, Period p) {
    final series = monthlySeries(list, p);
    final maxV = series.fold<double>(0, (a, e) => (e.$2 + e.$3) > a ? e.$2 + e.$3 : a);
    return BarChart(BarChartData(
      maxY: maxV <= 0 ? 1 : maxV * 1.15,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
            '${monthLabel(series[g.x].$1)}\nCash ${money(series[g.x].$2)}\nBarter ${money(series[g.x].$3)}',
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
          ),
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
              if (i < 0 || i >= series.length) return const SizedBox.shrink();
              final l = monthLabel(series[i].$1);
              return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(series.length > 7 ? l.substring(0, 1) : l, style: const TextStyle(fontSize: 11, color: kMuted)));
            },
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < series.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: series[i].$2 + series[i].$3,
              width: series.length > 7 ? 12 : 22,
              borderRadius: BorderRadius.circular(5),
              color: Colors.transparent,
              rodStackItems: [
                BarChartRodStackItem(0, series[i].$2, kPrimary),
                BarChartRodStackItem(series[i].$2, series[i].$2 + series[i].$3, kBarterBar),
              ],
            ),
          ]),
      ],
    ));
  }

  Widget _byType(List<CollabView> list, Period p) {
    final m = <String, (double, int)>{};
    for (final t in kDealTypes) {
      final l = list.where((c) => c.dealType == t).toList();
      final e = computeEarnings(l, p);
      m[t] = (e.total, e.collabIds.length);
    }
    final total = m.values.fold<double>(0, (a, v) => a + v.$1);
    if (total <= 0) return const Text('No earnings in this period.', style: TextStyle(color: kMuted));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 14,
          child: Row(children: [
            for (final t in kDealTypes)
              if (m[t]!.$1 > 0) Expanded(flex: (m[t]!.$1 * 1000 / total).round().clamp(1, 1000).toInt(), child: Container(color: typeColor(t))),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      for (final t in kDealTypes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            CircleAvatar(radius: 5, backgroundColor: typeColor(t)),
            const SizedBox(width: 8),
            Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
            Text('${money(m[t]!.$1)} · ${m[t]!.$2}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
    ]);
  }

  Widget _topBrands(List<CollabView> list, Period p) {
    final by = <String, List<CollabView>>{};
    for (final c in list) {
      by.putIfAbsent(c.brandName, () => []).add(c);
    }
    final rows = by.entries.map((e) {
      final x = computeEarnings(e.value, p);
      return (e.key, x.cash, x.barter, x.collabIds.length);
    }).where((r) => r.$2 + r.$3 > 0).toList()
      ..sort((a, b) => (b.$2 + b.$3).compareTo(a.$2 + a.$3));
    if (rows.isEmpty) return const Text('No brand earnings in this period.', style: TextStyle(color: kMuted));
    final maxV = rows.first.$2 + rows.first.$3;
    return Column(
      children: rows.take(8).map((r) {
        final cf = maxV <= 0 ? 0.0 : r.$2 / maxV;
        final bf = maxV <= 0 ? 0.0 : r.$3 / maxV;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
              Text(money(r.$2 + r.$3), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              Text('  · ${r.$4}', style: const TextStyle(color: kMuted, fontSize: 12)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(children: [
                  if (cf > 0) Expanded(flex: (cf * 1000).round().clamp(1, 1000).toInt(), child: Container(color: kPrimary)),
                  if (bf > 0) Expanded(flex: (bf * 1000).round().clamp(1, 1000).toInt(), child: Container(color: kBarterBar)),
                  if (cf + bf < 1) Expanded(flex: ((1 - cf - bf) * 1000).round().clamp(1, 1000).toInt(), child: Container(color: kLine)),
                ]),
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }

  Widget _content(Snapshot s, List<CollabView> list, List<CollabView> inPeriod, Period p, Earnings e) {
    final ids = list.map((c) => c.id).toSet();
    final dels = s.deliverables.where((d) => ids.contains(d['collab_id']) && (p.hasStr(d['live_date']) || p.hasStr(d['due_date']))).toList();
    final live = dels.where((d) => d['status'] == 'Live').toList();
    int count(String t) => live.where((d) => d['type'] == t).length;
    final onTime = live.where((d) {
      final due = parseDate(d['due_date']);
      final ld = parseDate(d['live_date']);
      return due == null || ld == null || !ld.isAfter(due.add(const Duration(days: 1)));
    }).length;
    final views = <int>[];
    for (final d in live) {
      final m = Snapshot.bestMetric(s.metrics.where((x) => x['deliverable_id'] == d['id']).toList());
      if (m != null) views.add(toI(m['views']));
    }
    views.sort();
    final done = list.where((c) => c.stage == 'Done' && e.collabIds.contains(c.id)).length;
    return Column(children: [
      KV('Collabs with earnings', '${inPeriod.length}'),
      KV('Collabs completed', '$done'),
      KV('Reels / posts / stories', '${count('Reel')} / ${count('Post') + count('Carousel')} / ${count('Story')}'),
      KV('Posted on time', live.isEmpty ? '—' : '${(onTime * 100 / live.length).toStringAsFixed(0)}%'),
      KV('Median 7-day views', views.isEmpty ? '—' : plainNum(views[views.length ~/ 2])),
      KV('Avg earned per collab', inPeriod.isEmpty ? '—' : money(e.total / inPeriod.length)),
    ]);
  }

  Widget _owed(List<CollabView> list, Earnings e) {
    var notDue = 0.0, d30 = 0.0, d30p = 0.0;
    for (final c in list) {
      if (c.pending <= 0) continue;
      final over = -daysFromToday(c.dueDate);
      if (c.dueDate == null || over <= 0) {
        notDue += c.pending;
      } else if (over <= 30) {
        d30 += c.pending;
      } else {
        d30p += c.pending;
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KV('Not yet due', money(notDue)),
      KV('Overdue 1–30 days', money(d30)),
      KV('Overdue 30+ days', money(d30p)),
      KV('TDS deducted (period)', money(e.tds)),
      const SizedBox(height: 4),
      const Text('For reference — check TDS against Form 26AS with your CA.', style: TextStyle(fontSize: 11, color: kMuted)),
    ]);
  }

  Widget _barterList(Snapshot s, List<CollabView> list, Period p) {
    final l = list.where((c) => c.barterEarned > 0 && p.has(c.barterDate)).toList();
    if (l.isEmpty) return const Text('No barter in this period.', style: TextStyle(color: kMuted));
    return Column(children: [
      for (final c in l) ...[
        CollabRow(c: c, thumb: 48, onTap: () => push(context, CollabDetailScreen(collabId: c.id))),
        const SizedBox(height: 8),
      ],
    ]);
  }
}
