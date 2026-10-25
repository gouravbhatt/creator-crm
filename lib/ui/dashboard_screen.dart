import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/snapshot.dart';
import 'collabs_screens.dart';
import 'search_screen.dart';
import 'widgets.dart';

class _Attention {
  final String label;
  final Color color;
  final List<CollabView> items;
  _Attention(this.label, this.color, this.items);
}

class DashboardScreen extends StatefulWidget {
  final ValueChanged<int> onOpenTab;
  const DashboardScreen({super.key, required this.onOpenTab});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with AutoReload {
  Snapshot? _s;

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    if (mounted) setState(() => _s = s);
  }

  List<_Attention> _attention(Snapshot s) {
    bool anyDel(CollabView c, bool Function(Map<String, dynamic>) f) => c.deliverables.any(f);
    final active = s.collabs.where((c) => c.stage != kCancelled).toList();
    return [
      _Attention('Payments overdue', kDanger, active.where((c) => c.paymentStatus == 'Overdue').toList()),
      _Attention('Deliverables due in 3 days', kWarn, active.where((c) => anyDel(c, (d) {
            final st = str(d['status']);
            final days = daysFromToday(d['due_date']);
            return st != 'Live' && st != 'Approved' && days >= 0 && days <= 3;
          })).toList()),
      _Attention('Revisions requested', kWarn, active.where((c) => anyDel(c, (d) => d['status'] == 'Revision')).toList()),
      _Attention('Live but link missing', kPrimary,
          active.where((c) => anyDel(c, (d) => d['status'] == 'Live' && str(d['live_link']).isEmpty)).toList()),
      _Attention('7-day metrics not logged', kMuted, active.where((c) => anyDel(c, (d) {
            if (d['status'] != 'Live') return false;
            final days = daysFromToday(d['live_date']);
            return days <= -7 && Snapshot.bestMetric(c.metricsFor(str(d['id']))) == null;
          })).toList()),
      _Attention('Usage rights end in 15 days', kMuted, s.collabs.where((c) {
        final d = daysFromToday(c.row['usage_rights_until']);
        return d >= 0 && d <= 15;
      }).toList()),
      _Attention('Renewals due in 30 days', kOk, s.collabs.where((c) {
        final d = daysFromToday(c.row['renewal_date']);
        return d >= 0 && d <= 30;
      }).toList()),
    ].where((a) => a.items.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.search), tooltip: 'Search', onPressed: () => push(context, const SearchScreen())),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_dashboard',
        onPressed: () => push(context, const CollabFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('New collab'),
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: _body(s)),
            ),
    );
  }

  List<Widget> _body(Snapshot s) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final thisMonth = s.receipts.where((r) {
      final d = parseDate(r['received_date']);
      return d != null && !d.isBefore(monthStart);
    }).fold(0.0, (a, r) => a + toD(r['amount']) + toD(r['tds']));
    final outstanding = s.collabs.fold(0.0, (a, c) => a + c.pending);
    final overdue = s.collabs.where((c) => c.paymentStatus == 'Overdue').length;
    final active = s.collabs.where((c) => c.active).toList();
    final inReview = active.where((c) => c.stage == 'Review').length;
    final liveThisMonth = s.deliverables.where((d) {
      final dt = parseDate(d['live_date']);
      return d['status'] == 'Live' && dt != null && !dt.isBefore(monthStart);
    }).length;
    final totalReceived = s.collabs.fold(0.0, (a, c) => a + c.received);
    final attention = _attention(s);

    return [
      StatGrid(children: [
        StatTile(label: 'Received this month', value: money(thisMonth), sub: 'All time ${money(totalReceived)}'),
        StatTile(label: 'Outstanding', value: money(outstanding), sub: '$overdue overdue', color: overdue > 0 ? kDanger : null),
        StatTile(label: 'Active collabs', value: '${active.length}', sub: '$inReview in review'),
        StatTile(label: 'Live this month', value: '$liveThisMonth', sub: 'deliverables posted'),
      ]),
      SectionCard(
        title: 'Totals',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(label: Text('${s.brands.length} brands')),
          Chip(label: Text('${s.contacts.length} contacts')),
          Chip(label: Text('${s.collabs.length} collabs')),
          Chip(label: Text('${active.length} pending collabs')),
          Chip(label: Text('${s.products.length} products')),
        ]),
      ),
      SectionCard(
        title: 'Needs attention',
        child: attention.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('All clear. Nothing overdue or due soon.', style: TextStyle(color: kMuted)))
            : Column(
                children: attention
                    .map((a) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: CircleAvatar(radius: 5, backgroundColor: a.color),
                          title: Text(a.label),
                          trailing: Text('${a.items.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          onTap: () => _showList(a),
                        ))
                    .toList()),
      ),
      SectionCard(
        title: 'Pipeline by stage',
        trailing: Text(money(active.fold<double>(0.0, (a, c) => a + c.agreed)), style: const TextStyle(color: kMuted, fontSize: 12)),
        child: Builder(builder: (_) {
          final counts = {for (final st in kStages) st: s.collabs.where((c) => c.stage == st).length};
          final maxC = counts.values.fold(1, (a, b) => b > a ? b : a);
          return Column(
              children: kStages
                  .map((st) => BarLine(
                      label: st, fraction: counts[st]! / maxC, value: '${counts[st]}', color: stageColor(st)))
                  .toList());
        }),
      ),
      SectionCard(title: 'Earnings · last 6 months', child: SizedBox(height: 170, child: _earningsChart(s))),
      SectionCard(title: 'Next 7 days', child: _upcoming(s)),
    ];
  }

  Widget _earningsChart(Snapshot s) {
    final now = DateTime.now();
    final months = List.generate(6, (i) => DateTime(now.year, now.month - 5 + i, 1));
    final values = months.map((m) {
      final next = DateTime(m.year, m.month + 1, 1);
      return s.receipts.where((r) {
        final d = parseDate(r['received_date']);
        return d != null && !d.isBefore(m) && d.isBefore(next);
      }).fold(0.0, (a, r) => a + toD(r['amount']) + toD(r['tds']));
    }).toList();
    final maxV = values.fold(0.0, (a, b) => b > a ? b : a);
    return BarChart(BarChartData(
      maxY: maxV <= 0 ? 1 : maxV * 1.15,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, gi, rod, ri) =>
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
            reservedSize: 24,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= months.length) return const SizedBox.shrink();
              return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(monthLabel(months[i]), style: const TextStyle(fontSize: 11, color: kMuted)));
            },
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < values.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
                toY: values[i], width: 22, color: kPrimary, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
          ]),
      ],
    ));
  }

  Widget _upcoming(Snapshot s) {
    final items = <(String, String, String, Color, CollabView)>[];
    for (final c in s.collabs.where((c) => c.stage != kCancelled)) {
      for (final d in c.deliverables) {
        final name = '${str(d['type'])}${str(d['title']).isEmpty ? '' : ' · ${str(d['title'])}'}';
        final st = str(d['status']);
        final dd = daysFromToday(d['due_date']);
        if (st != 'Live' && st != 'Approved' && dd >= 0 && dd <= 7) {
          items.add((str(d['due_date']), '${c.brandName} · $name draft due', 'Draft', kWarn, c));
        }
        final ld = daysFromToday(d['live_date']);
        if (st != 'Live' && ld >= 0 && ld <= 7) items.add((str(d['live_date']), '${c.brandName} · $name go-live', 'Live', kOk, c));
      }
      final due = c.dueDate;
      final pd = daysFromToday(due);
      if (c.pending > 0 && due != null && pd >= 0 && pd <= 7) {
        items.add((due, '${c.brandName} · payment ${money(c.pending)}', 'Pay', kPrimary, c));
      }
      final na = daysFromToday(c.row['next_action_date']);
      if (str(c.row['next_action']).isNotEmpty && na >= 0 && na <= 7) {
        items.add((str(c.row['next_action_date']), '${c.brandName} · ${str(c.row['next_action'])}', 'Todo', kMuted, c));
      }
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    if (items.isEmpty) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nothing scheduled this week.', style: TextStyle(color: kMuted)));
    }
    return Column(
      children: items
          .map((e) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: SizedBox(width: 56, child: Text(showDate(e.$1).replaceAll(RegExp(r' \d{4}$'), ''),
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                title: Text(e.$2, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Pill(e.$3, e.$4),
                onTap: () => push(context, CollabDetailScreen(collabId: e.$5.id)),
              ))
          .toList(),
    );
  }

  void _showList(_Attention a) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(a.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ...a.items.map((cv) => ListTile(
                title: Text(cv.title),
                subtitle: Text('${cv.brandName} · ${cv.stage}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(c);
                  push(context, CollabDetailScreen(collabId: cv.id));
                },
              )),
        ]),
      ),
    );
  }
}
