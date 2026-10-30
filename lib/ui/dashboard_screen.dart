import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/earnings.dart';
import '../core/format.dart';
import '../core/repo.dart';
import '../core/snapshot.dart';
import 'backup_screen.dart';
import 'collabs_screens.dart';
import 'income_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'type_picker.dart';
import 'v2_widgets.dart';
import 'widgets.dart';

class _Todo {
  final String icon;
  final String title;
  final String sub;
  final String when;
  final Color fg;
  final Color bg;
  final Color whenColor;
  final VoidCallback onTap;
  final String sortKey;
  _Todo(this.icon, this.title, this.sub, this.when, this.fg, this.bg, this.whenColor, this.onTap, this.sortKey);
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

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  List<Widget> _body(Snapshot s) {
    final p = Period.of(_period);
    final e = computeEarnings(s.collabs, p, income: s.income);
    final prev = computeEarnings(s.collabs, p.previous(), income: s.income);
    final change = (p.key == 'All time' || prev.total <= 0) ? null : (e.total - prev.total) * 100 / prev.total;
    final owedFees = s.collabs.fold<double>(0, (a, c) => a + c.pendingFee);
    final overdue = s.collabs.where((c) => c.paymentStatus == 'Overdue').length;
    final refunds = s.collabs.fold<double>(0, (a, c) => a + c.moneyOut);
    final affPending = s.income.where((r) => r['status'] != 'Paid').fold<double>(0, (a, r) => a + toD(r['gross']) - toD(r['tds']));
    final affPlatforms = s.income.where((r) => r['status'] != 'Paid').map((r) => r['platform']).toSet().length;
    final toPost = s.collabs.where((c) => !c.cancelled).fold<int>(0, (a, c) => a + c.deliverables.where((d) => d['status'] != 'Live').length);
    final dueWeek = s.collabs.where((c) => !c.cancelled).fold<int>(0, (a, c) => a + c.deliverables.where((d) {
          final n = daysFromToday(d['due_date']);
          return d['status'] != 'Live' && n >= 0 && n <= 7;
        }).length);
    final active = s.collabs.where((c) => c.active).toList()..sort((a, b) => str(b.row['updated_at']).compareTo(str(a.row['updated_at'])));
    final handle = (_profile['profile_handle'] ?? '').replaceFirst('@', '');
    final name = _profile['profile_name'] ?? '';
    final photo = _profile['profile_photo'] ?? '';
    final todos = _todos(s);

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => push(context, const ProfileScreen()),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kPrimary, width: 2)),
              child: ClipOval(
                child: photo.isEmpty
                    ? Container(color: kPrimaryTint, child: const Icon(Icons.person_outline, color: kPrimary))
                    : ProductThumb(fileName: photo, type: kPaid, size: 46, radius: 23),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => push(context, const ProfileScreen()),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isEmpty ? _greeting : '$_greeting, ${name.split(' ').first}', style: const TextStyle(fontSize: 12, color: kMuted)),
                Text(handle.isEmpty ? 'Tap to set up your profile' : '@$handle', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
          IconButton(
            style: IconButton.styleFrom(backgroundColor: Colors.white, fixedSize: const Size(44, 44)),
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => push(context, const SearchScreen()),
          ),
          const SizedBox(width: 4),
          IconButton(
            style: IconButton.styleFrom(backgroundColor: Colors.white, fixedSize: const Size(44, 44)),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Profile & settings',
            onPressed: () => push(context, const ProfileScreen()),
          ),
        ]),
      ),
      PillRow(options: Period.keys, value: _period, onChanged: (v) => setState(() => _period = v), padding: const EdgeInsets.symmetric(horizontal: 16)),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _hero(e, change),
          const SizedBox(height: 12),
          StatGrid(children: [
            _tile('Brands owe you', money(owedFees), overdue > 0 ? '$overdue overdue' : 'fees pending', overdue > 0 ? kDanger : kMuted, kDanger,
                () => widget.onOpenTab(2)),
            _tile('Refunds due', money(refunds), 'your money out', kAmberDark, kAmber, () => widget.onOpenTab(2)),
            _tile('Affiliate pending', money(affPending), '$affPlatforms platform${affPlatforms == 1 ? '' : 's'}', kMintDark, kMint,
                () => widget.onOpenTab(2)),
            _tile('To post', '$toPost', '$dueWeek due this week', kPrimaryDark, kPrimary, () => widget.onOpenTab(1)),
          ]),
          if (s.collabs.isEmpty && s.income.isEmpty) _welcome(),
          if (todos.isNotEmpty)
            Panel(
              title: 'To do',
              trailing: Text('${todos.length} item${todos.length == 1 ? '' : 's'}', style: const TextStyle(color: kMuted, fontSize: 12)),
              child: Column(children: todos.take(6).map(_todoRow).toList()),
            ),
          Panel(title: 'Monthly income', trailing: _legend(), child: SizedBox(height: 170, child: _chart(s, p))),
          if (active.isNotEmpty) ...[
            Row(children: [
              const Expanded(child: Text('Active collabs', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              TextButton(onPressed: () => widget.onOpenTab(1), child: const Text('See all')),
            ]),
            for (final c in active.take(5)) ...[
              CollabRow(c: c, thumb: 56, onTap: () => push(context, CollabDetailScreen(collabId: c.id))),
              const SizedBox(height: 8),
            ],
          ],
        ]),
      ),
    ];
  }

  Widget _welcome() => Panel(
        child: Column(children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/logo.png', width: 52, height: 52)),
          const SizedBox(height: 10),
          const Text('Welcome to $kAppName', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Add your first collab — paid, barter, order & refund, UGC and more.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => showAddSheet(context), icon: const Icon(Icons.add), label: const Text('Add first collab')),
          TextButton.icon(
            onPressed: () => push(context, const BackupScreen()),
            icon: const Icon(Icons.settings_backup_restore),
            label: const Text('Restore from a backup (.ccrm)'),
          ),
        ]),
      );

  Widget _hero(Earnings e, double? change) {
    final total = e.total <= 0 ? 1.0 : e.total;
    final parts = [
      (e.cash + e.other, const Color(0xFF9D87FF), 'Cash'),
      (e.barter, const Color(0xFFFF8FB4), 'Barter'),
      (e.affiliate, const Color(0xFF7EE0B5), 'Affiliate'),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(26)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 104,
            height: 104,
            child: CustomPaint(painter: _RingPainter([for (final p in parts) (e.total <= 0 ? 0.0 : p.$1 / total, p.$2)])),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total income · $_period', style: const TextStyle(color: Color(0xFFC9C5DC), fontSize: 12)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money(e.total), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              ),
              if (change != null)
                Text('${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(0)}% vs previous',
                    style: TextStyle(color: change >= 0 ? const Color(0xFF9CF2C6) : const Color(0xFFFFB4A8), fontSize: 12, fontWeight: FontWeight.w700)),
              Text('Net after expenses ${money(e.net)}', style: const TextStyle(color: Color(0xFFC9C5DC), fontSize: 11)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 4, backgroundColor: parts[i].$2),
                    const SizedBox(width: 6),
                    Text(parts[i].$3, style: const TextStyle(color: Color(0xFFC9C5DC), fontSize: 11)),
                  ]),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(money(parts[i].$1), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _tile(String label, String value, String sub, Color subColor, Color dot, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: kMuted))),
              CircleAvatar(radius: 4, backgroundColor: dot),
            ]),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            Text(sub, style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  List<_Todo> _todos(Snapshot s) {
    final out = <_Todo>[];
    void open(CollabView c) => push(context, CollabDetailScreen(collabId: c.id));
    for (final c in s.collabs.where((c) => !c.cancelled)) {
      if (c.pendingFee > 0.5 && c.paymentStatus == 'Overdue') {
        final late = -daysFromToday(c.dueDate);
        out.add(_Todo('₹', '${c.brandName} payment overdue', '${money(c.pendingFee)} · tap to remind', '${late}d late', kDanger, kDangerTint,
            kDanger, () => open(c), '0${c.dueDate}'));
      }
      if (c.pendingRefund > 0.5 && c.orderPlaced) {
        final d = c.dueDate;
        out.add(_Todo('↺', 'Refund due from ${c.brandName}', 'You paid ${money(c.refundAmount)}', d == null ? '' : _when(d), kAmberDark, kAmberTint,
            kAmberDark, () => open(c), '1${d ?? '9999'}'));
      }
      for (final dl in c.deliverables) {
        final st = str(dl['status']);
        if (st != 'Live' && str(dl['due_date']).isNotEmpty) {
          final n = daysFromToday(dl['due_date']);
          if (n <= 7) {
            out.add(_Todo(isUgcDeliverable(dl) ? '▶' : '◎', '${isUgcDeliverable(dl) ? 'Deliver' : 'Post'} ${str(dl['type']).toLowerCase()} · ${c.brandName}',
                st == 'Planned' ? 'Not started' : st, _when(str(dl['due_date'])), kPrimaryDark, kPrimaryTint, n < 0 ? kDanger : kPrimaryDark,
                () => open(c), '2${str(dl['due_date'])}'));
          }
        }
        if (st == 'Live' && str(dl['live_link']).isEmpty) {
          out.add(_Todo('↗', 'Add ${isUgcDeliverable(dl) ? 'file' : 'live'} link', '${c.brandName} · ${str(dl['type'])}', '', kMintDark, kMintTint, kMuted,
              () => open(c), '3'));
        }
      }
    }
    for (final r in s.income.where((r) => r['status'] != 'Paid')) {
      final m = incomeMonth(r);
      if (m != null && DateTime.now().difference(m).inDays > 75) {
        out.add(_Todo('A', '${str(r['platform'])} payout pending', '${str(r['month'])} · ${money(toD(r['gross']))}', '', kMintDark, kMintTint, kMuted,
            () => incomeDialog(context, sourceType: str(r['source_type']), existing: r), '4'));
      }
    }
    out.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return out;
  }

  String _when(String iso) {
    final n = daysFromToday(iso);
    if (n == 0) return 'Today';
    if (n == 1) return 'Tomorrow';
    if (n < 0) return '${-n}d late';
    if (n < 7) return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][parseDate(iso)!.weekday - 1];
    return showDate(iso).replaceAll(RegExp(r' \d{4}$'), '');
  }

  Widget _todoRow(_Todo t) => InkWell(
        onTap: t.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(12)),
              child: Text(t.icon, style: TextStyle(color: t.fg, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(t.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kMuted)),
              ]),
            ),
            if (t.when.isNotEmpty) Text(t.when, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: t.whenColor)),
          ]),
        ),
      );

  Widget _legend() => const Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 4, backgroundColor: kPrimary),
        SizedBox(width: 4),
        Text('Cash', style: TextStyle(fontSize: 10, color: kMuted)),
        SizedBox(width: 8),
        CircleAvatar(radius: 4, backgroundColor: kBarterBar),
        SizedBox(width: 4),
        Text('Barter', style: TextStyle(fontSize: 10, color: kMuted)),
        SizedBox(width: 8),
        CircleAvatar(radius: 4, backgroundColor: kMint),
        SizedBox(width: 4),
        Text('Affiliate', style: TextStyle(fontSize: 10, color: kMuted)),
      ]);

  Widget _chart(Snapshot s, Period p) {
    final series = monthlySeries(s.collabs, p, income: s.income);
    return incomeBarChart(series);
  }
}

/// Stacked monthly bars: cash (violet), barter (pink), affiliate/other (mint).
Widget incomeBarChart(List<(DateTime, double, double, double)> series) {
  final maxV = series.fold<double>(0, (a, e) => math.max(a, e.$2 + e.$3 + e.$4));
  return BarChart(BarChartData(
    maxY: maxV <= 0 ? 1 : maxV * 1.15,
    gridData: const FlGridData(show: false),
    borderData: FlBorderData(show: false),
    barTouchData: BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
          '${monthLabel(series[g.x].$1)}\nCash ${money(series[g.x].$2)}\nBarter ${money(series[g.x].$3)}\nAffiliate ${money(series[g.x].$4)}',
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
            toY: series[i].$2 + series[i].$3 + series[i].$4,
            width: series.length > 7 ? 12 : 22,
            borderRadius: BorderRadius.circular(6),
            color: Colors.transparent,
            rodStackItems: [
              BarChartRodStackItem(0, series[i].$2, kPrimary),
              BarChartRodStackItem(series[i].$2, series[i].$2 + series[i].$3, kBarterBar),
              BarChartRodStackItem(series[i].$2 + series[i].$3, series[i].$2 + series[i].$3 + series[i].$4, kMint),
            ],
          ),
        ]),
    ],
  ));
}

class _RingPainter extends CustomPainter {
  final List<(double, Color)> parts;
  _RingPainter(this.parts);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 15.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withOpacity(0.12);
    canvas.drawArc(rect, 0, math.pi * 2, false, bg);
    var start = -math.pi / 2;
    for (final p in parts) {
      if (p.$1 <= 0) continue;
      final sweep = p.$1 * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = p.$2;
      canvas.drawArc(rect, start, math.max(0.0, sweep - 0.04), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => true;
}
