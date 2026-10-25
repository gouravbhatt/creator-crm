import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/earnings.dart';
import '../core/format.dart';
import '../core/repo.dart';
import '../core/snapshot.dart';
import 'collabs_screens.dart';
import 'payments_screen.dart';
import 'search_screen.dart';
import 'v2_widgets.dart';
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
  Map<String, String> _profile = {};
  String _period = 'This FY';
  String _type = 'All';

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    final st = await Repo.settings();
    if (mounted) {
      setState(() {
        _s = s;
        _profile = st;
      });
    }
  }

  List<_Attention> _attention(List<CollabView> list) {
    bool anyDel(CollabView c, bool Function(Map<String, dynamic>) f) => c.deliverables.any(f);
    final live = list.where((c) => c.stage != kCancelled).toList();
    return [
      _Attention('Payments overdue', kDanger, live.where((c) => c.paymentStatus == 'Overdue').toList()),
      _Attention('Posts due in 7 days', kWarn, live.where((c) => anyDel(c, (d) {
            final days = daysFromToday(d['due_date']);
            return d['status'] != 'Live' && days >= 0 && days <= 7;
          })).toList()),
      _Attention('Posted, link missing', kPrimary,
          live.where((c) => anyDel(c, (d) => d['status'] == 'Live' && str(d['live_link']).isEmpty)).toList()),
      _Attention('Revisions asked', kWarn, live.where((c) => anyDel(c, (d) => d['status'] == 'Revision')).toList()),
      _Attention('Rights end in 15 days', kMuted, live.where((c) {
        final d = daysFromToday(c.row['usage_rights_until']);
        return d >= 0 && d <= 15;
      }).toList()),
    ].where((a) => a.items.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      body: SafeArea(
        child: s == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(onRefresh: reload, child: ListView(padding: const EdgeInsets.only(bottom: 24), children: _body(s))),
      ),
    );
  }

  List<Widget> _body(Snapshot s) {
    final list = filterCollabs(s, type: _type);
    final p = Period.of(_period);
    final e = computeEarnings(list, p);
    final pending = list.fold<double>(0, (a, c) => a + c.pending);
    final overdue = list.where((c) => c.paymentStatus == 'Overdue').length;
    final posted = s.deliverables.where((d) => d['status'] == 'Live' && p.hasStr(d['live_date']) && list.any((c) => c.id == d['collab_id'])).length;
    final toPost = list
        .where((c) => c.stage != kCancelled)
        .fold<int>(0, (a, c) => a + c.deliverables.where((d) => d['status'] != 'Live').length);
    final barterCount = list.where((c) => c.hasBarter && c.barterEarned > 0 && p.has(c.barterDate)).length;
    final cashFrac = e.total <= 0 ? 0.5 : e.cash / e.total;
    final recent = [...list]..sort((a, b) => str(b.row['updated_at']).compareTo(str(a.row['updated_at'])));
    final attention = _attention(list);
    final name = _profile['profile_name'] ?? '';
    final handle = _profile['profile_handle'] ?? '';
    final photo = _profile['profile_photo'] ?? '';

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kPrimary, width: 2)),
            child: ClipOval(
              child: photo.isEmpty
                  ? Container(color: kPrimaryTint, child: const Icon(Icons.person_outline, color: kPrimary))
                  : ProductThumb(fileName: photo, type: kPaid, size: 46, radius: 23),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isEmpty ? 'Hi there' : 'Hi ${name.split(' ').first}', style: const TextStyle(fontSize: 13, color: kMuted)),
              Text(handle.isEmpty ? 'Set your @handle in Profile' : '@${handle.replaceFirst('@', '')}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
          ),
          IconButton(
            style: IconButton.styleFrom(backgroundColor: Colors.white),
            icon: const Icon(Icons.search),
            onPressed: () => push(context, const SearchScreen()),
          ),
        ]),
      ),
      PillRow(options: Period.keys, value: _period, onChanged: (v) => setState(() => _period = v), padding: const EdgeInsets.symmetric(horizontal: 16)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Segmented(options: const ['All', kPaid, kBarter, 'Both'], value: _type, onChanged: (v) => setState(() => _type = v)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _hero(e, cashFrac, p),
          const SizedBox(height: 12),
          StatGrid(children: [
            _tile('₹', 'Cash received', money(e.cash), 'from ${e.paidCollabs} paid collab${e.paidCollabs == 1 ? '' : 's'}', kPrimaryTint, kPrimary),
            _tile('◆', 'Barter value till now', money(e.barter), 'from $barterCount barter collab${barterCount == 1 ? '' : 's'}', kBarterTint, kBarterC),
            _tile('⏳', 'Pending payments', money(pending), '$overdue overdue', kWarnTint, kWarn,
                subColor: overdue > 0 ? kDanger : kMuted, onTap: () => push(context, const PaymentsScreen())),
            _tile('▶', 'Reels posted', '$posted', '$toPost still to post', kBothTint, kBothC),
          ]),
          Panel(title: 'Earnings by month', trailing: _legend(), child: SizedBox(height: 160, child: _chart(list, p))),
          if (attention.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 2, 0, 8),
              child: Text('Needs attention', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: attention.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final a = attention[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _showList(a),
                    child: Container(
                      width: 150,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${a.items.length}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: a.color)),
                        Text(a.label, style: const TextStyle(fontSize: 12, color: Color(0xFF3B3753))),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(children: [
            const Expanded(child: Text('Recent collabs', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            TextButton(onPressed: () => widget.onOpenTab(1), child: const Text('See all')),
          ]),
          if (recent.isEmpty)
            Panel(
              child: Column(children: [
                const Text('No collabs yet', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Add your first brand deal — barter, paid or both.', style: TextStyle(color: kMuted)),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => push(context, const CollabFormScreen()), child: const Text('+ New collab')),
              ]),
            ),
          for (final c in recent.take(5)) ...[
            CollabRow(c: c, thumb: 56, onTap: () => push(context, CollabDetailScreen(collabId: c.id))),
            const SizedBox(height: 8),
          ],
        ]),
      ),
    ];
  }

  Widget _hero(Earnings e, double cashFrac, Period p) {
    final prev = computeEarnings(filterCollabs(_s!, type: _type), p.previous());
    final change = (p.key == 'All time' || prev.total <= 0) ? null : ((e.total - prev.total) * 100 / prev.total);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Total earned · ${p.key}', style: const TextStyle(color: Color(0xFFDCD4FF), fontSize: 13))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Text('${e.collabIds.length} collabs', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(money(e.total), style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1)),
        ),
        if (change != null)
          Text('${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(0)}% vs previous',
              style: TextStyle(color: change >= 0 ? const Color(0xFFB8F5D6) : const Color(0xFFFFC2CF), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              Expanded(flex: (cashFrac * 1000).round().clamp(1, 999).toInt(), child: Container(color: Colors.white)),
              Expanded(flex: ((1 - cashFrac) * 1000).round().clamp(1, 999).toInt(), child: Container(color: const Color(0xFFFF8FB4))),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _heroPart('Cash received', money(e.cash), Colors.white)),
          Expanded(child: _heroPart('Barter value', money(e.barter), const Color(0xFFFF8FB4))),
        ]),
        const Divider(color: Color(0x26FFFFFF), height: 22),
        Text('Net profit after expenses  ${money(e.net)}', style: const TextStyle(color: Color(0xFFDCD4FF), fontSize: 12)),
      ]),
    );
  }

  Widget _heroPart(String k, String v, Color dot) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 4, backgroundColor: dot),
          const SizedBox(width: 6),
          Text(k, style: const TextStyle(color: Color(0xFFDCD4FF), fontSize: 12)),
        ]),
        Text(v, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      ]);

  Widget _tile(String icon, String label, String value, String sub, Color tint, Color c,
      {Color subColor = kMuted, VoidCallback? onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
              child: Text(icon, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: kMuted)),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            Text(sub, style: TextStyle(fontSize: 11, color: subColor)),
          ]),
        ),
      ),
    );
  }

  Widget _legend() => const Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 4, backgroundColor: kPrimary),
        SizedBox(width: 4),
        Text('Cash', style: TextStyle(fontSize: 11, color: kMuted)),
        SizedBox(width: 10),
        CircleAvatar(radius: 4, backgroundColor: kBarterBar),
        SizedBox(width: 4),
        Text('Barter', style: TextStyle(fontSize: 11, color: kMuted)),
      ]);

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
            'Cash ${money(series[g.x].$2)}\nBarter ${money(series[g.x].$3)}',
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
                child: Text(series.length > 7 ? l.substring(0, 1) : l, style: const TextStyle(fontSize: 11, color: kMuted)),
              );
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
              borderRadius: BorderRadius.circular(6),
              rodStackItems: [
                BarChartRodStackItem(0, series[i].$2, kPrimary),
                BarChartRodStackItem(series[i].$2, series[i].$2 + series[i].$3, kBarterBar),
              ],
              color: Colors.transparent,
            ),
          ]),
      ],
    ));
  }

  void _showList(_Attention a) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(a.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          for (final cv in a.items) ...[
            CollabRow(c: cv, thumb: 48, onTap: () {
              Navigator.pop(c);
              push(context, CollabDetailScreen(collabId: cv.id));
            }),
            const SizedBox(height: 8),
          ],
        ]),
      ),
    );
  }
}
