import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/earnings.dart';
import '../core/format.dart';
import '../core/repo.dart';
import '../core/snapshot.dart';
import 'backup_screen.dart';
import 'dashboard_screen.dart' show incomeBarChart;
import 'v2_widgets.dart';
import 'widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with AutoReload {
  Snapshot? _s;
  String _view = 'Overview';
  String _period = 'This FY';
  String _type = 'All';
  String? _brand;
  String? _source;
  static const _views = ['Overview', 'Month-wise', 'Sources', 'Brands', 'Tax'];

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
            child: FilledButton.tonalIcon(
              onPressed: () => push(context, const BackupScreen()),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Export'),
            ),
          ),
        ],
      ),
      body: s == null ? const Center(child: CircularProgressIndicator()) : _body(s),
    );
  }

  Widget _filters(Snapshot s) {
    Widget drop<T>(String label, T? value, List<DropdownMenuItem<T?>> items, ValueChanged<T?> on) => Expanded(
          child: DropdownButtonFormField<T?>(
            value: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true),
            items: items,
            onChanged: on,
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PillRow(options: _views, value: _view, onChanged: (v) => setState(() => _view = v)),
      const SizedBox(height: 10),
      Row(children: [
        drop<String>('Period', _period, [for (final p in Period.keys) DropdownMenuItem(value: p, child: Text(p))], (v) => setState(() => _period = v ?? 'This FY')),
        const SizedBox(width: 8),
        drop<String>('Type', _type, [for (final t in kTypeFilters) DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))],
            (v) => setState(() => _type = v ?? 'All')),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        drop<String>('Brand', _brand, [
          const DropdownMenuItem(value: null, child: Text('All brands')),
          for (final b in s.brands) DropdownMenuItem(value: str(b['id']), child: Text(str(b['name']), overflow: TextOverflow.ellipsis)),
        ], (v) => setState(() => _brand = v)),
        const SizedBox(width: 8),
        drop<String>('Source', _source, [
          const DropdownMenuItem(value: null, child: Text('All sources')),
          for (final x in kSources) DropdownMenuItem(value: x, child: Text(x)),
        ], (v) => setState(() => _source = v)),
      ]),
      const SizedBox(height: 12),
    ]);
  }

  Widget _body(Snapshot s) {
    final p = Period.of(_period);
    final list = filterCollabs(s, type: _type, brandId: _brand, source: _source);
    final collabFiltered = _type != 'All' || _brand != null || _source != null;
    final e = computeEarnings(list, p, income: s.income, includeIncome: !collabFiltered);
    final prev = computeEarnings(list, p.previous(), income: s.income, includeIncome: !collabFiltered);
    final change = (p.key == 'All time' || prev.total <= 0) ? null : (e.total - prev.total) * 100 / prev.total;

    final children = <Widget>[
      _filters(s),
      _totalCard(e, change, collabFiltered),
    ];
    switch (_view) {
      case 'Month-wise':
        children.addAll([
          Panel(title: 'Income by month', child: SizedBox(height: 180, child: incomeBarChart(monthlySeries(list, p, income: collabFiltered ? const [] : s.income)))),
          Panel(title: 'Month-wise table', child: _monthTable(list, p, collabFiltered ? const [] : s.income)),
        ]);
        break;
      case 'Sources':
        children.addAll([
          Panel(title: 'Where collabs come from', child: _sources(list, p)),
          Panel(title: 'By collab type', child: _byType(list, p)),
          if (!collabFiltered) Panel(title: 'Affiliate & other by platform', child: _platforms(s, p)),
        ]);
        break;
      case 'Brands':
        children.addAll([
          Panel(title: 'Top brands', child: _topBrands(list, p)),
          Panel(title: 'Brand scorecard', child: _scorecard(list)),
        ]);
        break;
      case 'Tax':
        children.addAll([
          Panel(title: 'TDS by deductor (for ITR / 26AS)', child: _tds(list, collabFiltered ? const [] : s.income, p)),
          Panel(
            title: 'Summary',
            child: Column(children: [
              KV('Income (gross)', money(e.total)),
              KV('of which barter / products', money(e.barter)),
              KV('TDS deducted (all)', money(e.allTds)),
              KV('GST billed on invoices', money(list.fold<double>(0, (a, c) => a + c.invoices.where((i) => p.hasStr(i['invoice_date'])).fold<double>(0, (x, i) => x + toD(i['gst_amount']))))),
              KV('Expenses', money(e.expenses)),
              const SizedBox(height: 4),
              const Text('Reference only — confirm with your CA. Export CSV from Backup & export.', style: TextStyle(fontSize: 11, color: kMuted)),
            ]),
          ),
        ]);
        break;
      default:
        children.addAll([
          _cashFlow(s, list, e),
          Panel(title: 'Income by month', child: SizedBox(height: 170, child: incomeBarChart(monthlySeries(list, p, income: collabFiltered ? const [] : s.income)))),
          Panel(title: 'Where collabs come from', child: _sources(list, p)),
          Panel(title: 'Content', child: _content(s, list, p, e)),
        ]);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: children);
  }

  Widget _totalCard(Earnings e, double? change, bool collabOnly) {
    final rows = [
      ('Collab fees', e.cash - e.ugc, kPrimary),
      ('UGC', e.ugc, kBlue),
      ('Barter / products kept', e.barter, kBarterBar),
      if (!collabOnly) ('Affiliate', e.affiliate, kMint),
      if (!collabOnly) ('Other income', e.other, kAmber),
    ];
    final maxV = rows.fold<double>(1, (a, r) => r.$2 > a ? r.$2 : a);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(collabOnly ? 'Collab income (filtered)' : 'Total income', style: const TextStyle(fontSize: 13, color: kMuted)),
          const Spacer(),
          if (change != null)
            Text('${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: change >= 0 ? kMintDark : kDanger)),
        ]),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(money(e.total), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
        ),
        Text('Net after expenses ${money(e.net)}', style: const TextStyle(fontSize: 12, color: kMuted)),
        const SizedBox(height: 10),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: r.$3, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Expanded(child: Text(r.$1, style: const TextStyle(fontSize: 13))),
                Text(money(r.$2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                SizedBox(
                  width: 44,
                  child: Text(e.total <= 0 ? '' : '${(r.$2 * 100 / e.total).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: kMuted)),
                ),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: r.$2 / maxV, minHeight: 8, color: r.$3, backgroundColor: const Color(0xFFF1EFF7)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _cashFlow(Snapshot s, List<CollabView> list, Earnings e) {
    final owed = list.fold<double>(0, (a, c) => a + c.pendingFee);
    final out = list.fold<double>(0, (a, c) => a + c.moneyOut);
    Widget box(String l, String v, Color fg, Color bg) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
            FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
        );
    return Panel(
      title: 'Cash flow',
      child: Column(children: [
        Row(children: [
          Expanded(child: box('Cash in bank', money(e.cashInBank), kMintDark, kMintTint)),
          const SizedBox(width: 8),
          Expanded(child: box('Brands owe you', money(owed), kDanger, kDangerTint)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: box('Your money out (refunds)', money(out), kAmberDark, kAmberTint)),
          const SizedBox(width: 8),
          Expanded(child: box('Expenses + agency cuts', money(e.expenses + e.agencyCuts), kBody, const Color(0xFFF1EFF7))),
        ]),
      ]),
    );
  }

  Widget _monthTable(List<CollabView> list, Period p, List<Rec> income) {
    final series = monthlySeries(list, p, income: income).reversed.toList();
    TextStyle h = const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w700);
    Widget cell(String t, {bool bold = false, TextAlign a = TextAlign.right}) =>
        Expanded(child: Text(t, textAlign: a, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)));
    return Column(children: [
      Row(children: [
        SizedBox(width: 64, child: Text('Month', style: h)),
        Expanded(child: Text('Cash', textAlign: TextAlign.right, style: h)),
        Expanded(child: Text('Barter', textAlign: TextAlign.right, style: h)),
        Expanded(child: Text('Affiliate', textAlign: TextAlign.right, style: h)),
        Expanded(child: Text('Total', textAlign: TextAlign.right, style: h)),
      ]),
      const Divider(),
      for (final m in series)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 64, child: Text('${monthLabel(m.$1)} ${m.$1.year % 100}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            cell(plainNum(m.$2.round())),
            cell(plainNum(m.$3.round())),
            cell(plainNum(m.$4.round())),
            cell(plainNum((m.$2 + m.$3 + m.$4).round()), bold: true),
          ]),
        ),
    ]);
  }

  Widget _sources(List<CollabView> list, Period p) {
    final by = <String, List<CollabView>>{};
    for (final c in list) {
      by.putIfAbsent(c.source.isEmpty ? 'Not set' : c.source, () => []).add(c);
    }
    final rows = by.entries.map((e) {
      final x = computeEarnings(e.value, p, includeIncome: false);
      final cut = e.value.fold<double>(0, (a, c) => a + c.agencyCut);
      return (e.key, e.value.length, x.total, cut);
    }).toList()
      ..sort((a, b) => b.$3.compareTo(a.$3));
    if (rows.isEmpty) return const Text('No collabs yet.', style: TextStyle(color: kMuted));
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Expanded(child: Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('${r.$2}', style: const TextStyle(color: kMuted)),
            SizedBox(width: 96, child: Text(money(r.$3), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
        ),
      if (rows.any((r) => r.$4 > 0))
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Agency / platform cuts: ${money(rows.fold<double>(0, (a, r) => a + r.$4))}', style: const TextStyle(fontSize: 12, color: kMuted)),
        ),
    ]);
  }

  Widget _byType(List<CollabView> list, Period p) {
    final rows = <(String, double, int)>[];
    for (final t in kDealTypes) {
      final l = list.where((c) => c.kind == t).toList();
      if (l.isEmpty) continue;
      final e = computeEarnings(l, p, includeIncome: false);
      rows.add((t, e.total, l.length));
    }
    if (rows.isEmpty) return const Text('No collabs yet.', style: TextStyle(color: kMuted));
    final maxV = rows.fold<double>(1, (a, r) => r.$2 > a ? r.$2 : a);
    return Column(children: [
      for (final r in rows) BarLine(label: '${r.$1} (${r.$3})', fraction: r.$2 / maxV, value: money(r.$2), color: typeColor(r.$1)),
    ]);
  }

  Widget _platforms(Snapshot s, Period p) {
    final by = <String, double>{};
    for (final r in s.income.where((r) => p.has(incomeMonth(r)))) {
      by[str(r['platform'])] = (by[str(r['platform'])] ?? 0) + toD(r['gross']);
    }
    if (by.isEmpty) return const Text('No affiliate or other income in this period.', style: TextStyle(color: kMuted));
    final l = by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxV = l.first.value;
    return Column(children: [for (final e in l) BarLine(label: e.key, fraction: e.value / maxV, value: money(e.value), color: kMint)]);
  }

  Widget _topBrands(List<CollabView> list, Period p) {
    final by = <String, List<CollabView>>{};
    for (final c in list) {
      by.putIfAbsent(c.brandName, () => []).add(c);
    }
    final rows = by.entries.map((e) {
      final x = computeEarnings(e.value, p, includeIncome: false);
      return (e.key, x.cash, x.barter, e.value.length);
    }).where((r) => r.$2 + r.$3 > 0).toList()
      ..sort((a, b) => (b.$2 + b.$3).compareTo(a.$2 + a.$3));
    if (rows.isEmpty) return const Text('No brand income in this period.', style: TextStyle(color: kMuted));
    final maxV = rows.first.$2 + rows.first.$3;
    return Column(
      children: rows.take(10).map((r) {
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
                  if (cf + bf < 1) Expanded(flex: ((1 - cf - bf) * 1000).round().clamp(1, 1000).toInt(), child: Container(color: const Color(0xFFF1EFF7))),
                ]),
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }

  Widget _scorecard(List<CollabView> list) {
    final by = <String, List<CollabView>>{};
    for (final c in list) {
      by.putIfAbsent(c.brandName, () => []).add(c);
    }
    if (by.isEmpty) return const Text('No collabs yet.', style: TextStyle(color: kMuted));
    final rows = by.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        headingRowHeight: 36,
        columns: const [
          DataColumn(label: Text('Brand')),
          DataColumn(label: Text('Collabs'), numeric: true),
          DataColumn(label: Text('Earned'), numeric: true),
          DataColumn(label: Text('Avg'), numeric: true),
          DataColumn(label: Text('Owed'), numeric: true),
        ],
        rows: rows.map((e) {
          final l = e.value;
          final earned = l.fold<double>(0, (a, c) => a + c.earned);
          final owed = l.fold<double>(0, (a, c) => a + c.pending);
          return DataRow(cells: [
            DataCell(Text(e.key)),
            DataCell(Text('${l.length}')),
            DataCell(Text(money(earned))),
            DataCell(Text(money(earned / l.length))),
            DataCell(Text(money(owed), style: TextStyle(color: owed > 0 ? kDanger : null))),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _tds(List<CollabView> list, List<Rec> income, Period p) {
    final by = <String, (double, double)>{};
    for (final c in list) {
      for (final r in c.receipts.where((r) => r['kind'] != 'Refund' && p.hasStr(r['received_date']))) {
        final who = c.agencyName.isNotEmpty ? c.agencyName : c.brandName;
        final cur = by[who] ?? (0.0, 0.0);
        by[who] = (cur.$1 + toD(r['amount']) + toD(r['tds']), cur.$2 + toD(r['tds']));
      }
    }
    for (final r in income.where((r) => p.has(incomeMonth(r)))) {
      final who = str(r['platform']);
      final cur = by[who] ?? (0.0, 0.0);
      by[who] = (cur.$1 + toD(r['gross']), cur.$2 + toD(r['tds']));
    }
    final rows = by.entries.where((e) => e.value.$1 > 0).toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    if (rows.isEmpty) return const Text('No payments in this period.', style: TextStyle(color: kMuted));
    final totalTds = rows.fold<double>(0, (a, e) => a + e.value.$2);
    return Column(children: [
      const Row(children: [
        Expanded(child: Text('Deducted by', style: TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w700))),
        SizedBox(width: 90, child: Text('Gross', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w700))),
        SizedBox(width: 80, child: Text('TDS', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w700))),
      ]),
      const Divider(),
      for (final e in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(e.key, style: const TextStyle(fontSize: 13))),
            SizedBox(width: 90, child: Text(money(e.value.$1), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
            SizedBox(width: 80, child: Text(money(e.value.$2), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
          ]),
        ),
      const Divider(),
      Row(children: [
        const Expanded(child: Text('Total TDS', style: TextStyle(fontWeight: FontWeight.w800))),
        Text(money(totalTds), style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    ]);
  }

  Widget _content(Snapshot s, List<CollabView> list, Period p, Earnings e) {
    final ids = list.map((c) => c.id).toSet();
    final dels = s.deliverables.where((d) => ids.contains(d['collab_id']) && (p.hasStr(d['live_date']) || p.hasStr(d['due_date']))).toList();
    final live = dels.where((d) => d['status'] == 'Live').toList();
    int count(bool Function(Rec) f) => live.where(f).length;
    final onTime = live.where((d) {
      final due = parseDate(d['due_date']);
      final ld = parseDate(d['live_date']);
      return due == null || ld == null || !ld.isAfter(due.add(const Duration(days: 1)));
    }).length;
    final inPeriod = list.where((c) => e.collabIds.contains(c.id)).toList();
    final collabIncome = e.cash + e.barter;
    return Column(children: [
      KV('Collabs with income', '${inPeriod.length}'),
      KV('Reels · stories · posts', '${count((d) => d['type'] == 'Reel')} · ${count((d) => d['type'] == 'Story')} · ${count((d) => d['type'] == 'Post' || d['type'] == 'Carousel')}'),
      KV('UGC videos delivered', '${count((d) => isUgcDeliverable(d))}'),
      KV('On time', live.isEmpty ? '—' : '${(onTime * 100 / live.length).toStringAsFixed(0)}%'),
      KV('Avg earned per collab', inPeriod.isEmpty ? '—' : money(collabIncome / inPeriod.length)),
    ]);
  }
}
