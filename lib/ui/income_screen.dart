import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/earnings.dart';
import '../core/format.dart';
import '../core/repo.dart';
import '../core/snapshot.dart';
import 'payments_screen.dart';
import 'v2_widgets.dart';
import 'widgets.dart';

/// Income tab: affiliate payouts and other income, month by month.
class IncomeScreen extends StatefulWidget {
  const IncomeScreen({super.key});
  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> with AutoReload {
  Snapshot? _s;
  String _tab = 'Affiliate';
  String _period = 'This FY';

  @override
  Future<void> reload() async {
    final s = await Snapshot.load();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Income')),
      floatingActionButton: _tab == 'Brand payments'
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab_income',
              backgroundColor: kMintDark,
              foregroundColor: Colors.white,
              onPressed: () => incomeDialog(context, sourceType: _tab == 'Affiliate' ? 'Affiliate' : 'Other'),
              icon: const Icon(Icons.add),
              label: const Text('Add earning', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Segmented(
                  options: const ['Affiliate', 'Other income', 'Brand payments'],
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                ),
              ),
              Expanded(child: _tab == 'Brand payments' ? const PaymentsBody() : _incomeBody(s)),
            ]),
    );
  }

  Widget _incomeBody(Snapshot s) {
    final type = _tab == 'Affiliate' ? 'Affiliate' : 'Other';
    final p = Period.of(_period);
    final rows = s.income.where((r) => r['source_type'] == type).toList();
    final inP = rows.where((r) => p.has(incomeMonth(r))).toList();
    double sum(Iterable<Rec> l, double Function(Rec) f) => l.fold(0.0, (a, r) => a + f(r));
    final gross = sum(inP, (r) => toD(r['gross']));
    final tds = sum(inP, (r) => toD(r['tds']));
    final paid = sum(inP.where((r) => r['status'] == 'Paid'), (r) => toD(r['net_paid']) > 0 ? toD(r['net_paid']) : toD(r['gross']) - toD(r['tds']));
    final pend = sum(inP.where((r) => r['status'] != 'Paid'), (r) => toD(r['gross']) - toD(r['tds']));

    final byPlat = <String, double>{};
    for (final r in inP) {
      byPlat[str(r['platform'])] = (byPlat[str(r['platform'])] ?? 0) + toD(r['gross']);
    }
    final plats = byPlat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxP = plats.isEmpty ? 1.0 : plats.first.value;

    final byMonth = <String, List<Rec>>{};
    for (final r in rows) {
      byMonth.putIfAbsent(str(r['month']), () => []).add(r);
    }
    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
      PillRow(options: Period.keys, value: _period, onChanged: (v) => setState(() => _period = v)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: const Color(0xFF0E7C55), borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${type == 'Affiliate' ? 'Affiliate' : 'Other income'} earned · $_period',
              style: const TextStyle(color: Color(0xFFBDF0D9), fontSize: 12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(money(gross), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _heroPart('TDS cut', money(tds))),
            Expanded(child: _heroPart('Paid to bank', money(paid))),
            Expanded(child: _heroPart('Pending', money(pend))),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      if (plats.isNotEmpty)
        Panel(
          title: 'By ${type == 'Affiliate' ? 'platform' : 'source'}',
          child: Column(
            children: plats
                .map((e) => BarLine(label: e.key, fraction: e.value / maxP, value: money(e.value), color: kMint))
                .toList(),
          ),
        ),
      if (months.isEmpty)
        Panel(
          child: Column(children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 40, color: kMuted),
            const SizedBox(height: 8),
            Text(
              type == 'Affiliate'
                  ? 'Log monthly affiliate earnings from Amazon, Flipkart, Wishlink, LehLah and more — with TDS they cut.'
                  : 'Log AdSense, platform bonuses, course sales and other income.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted),
            ),
          ]),
        ),
      for (final m in months) _monthCard(m, byMonth[m]!),
    ]);
  }

  Widget _heroPart(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(color: Color(0xFFBDF0D9), fontSize: 11)),
        FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800))),
      ]);

  Widget _monthCard(String month, List<Rec> rows) {
    final d = parseDate('$month-01');
    final total = rows.fold<double>(0, (a, r) => a + toD(r['gross']));
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(d == null ? month : '${_monthName(d.month)} ${d.year}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          Padding(padding: const EdgeInsets.only(right: 8), child: Text(money(total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 4),
        for (final r in rows)
          InkWell(
            onTap: () => incomeDialog(context, sourceType: str(r['source_type']), existing: r),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(children: [
                Expanded(child: Text(str(r['platform']), style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(money(toD(r['gross'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                SizedBox(
                  width: 64,
                  child: Text(toD(r['tds']) > 0 ? '−${money(toD(r['tds']))}' : '',
                      textAlign: TextAlign.right, style: const TextStyle(color: kMuted, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                _statusPill(str(r['status'])),
                const Icon(Icons.chevron_right, color: kMuted, size: 20),
              ]),
            ),
          ),
      ]),
    );
  }
}

Widget _statusPill(String s) {
  final (fg, bg) = switch (s) {
    'Paid' => (kMintDark, kMintTint),
    'Confirmed' => (kPrimaryDark, kPrimaryTint),
    _ => (kAmberDark, kAmberTint),
  };
  return Container(
    width: 78,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Text(s, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

String _monthName(int m) =>
    const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][m - 1];

/// Add / edit an affiliate or other-income entry.
Future<void> incomeDialog(BuildContext context, {required String sourceType, Rec? existing}) async {
  final isAff = sourceType == 'Affiliate';
  final options = isAff ? kAffiliatePlatforms : kOtherIncomeTypes;
  final now = DateTime.now();
  final monthCtl = TextEditingController(text: str(existing?['month']).isEmpty ? '${now.year}-${now.month.toString().padLeft(2, '0')}' : str(existing?['month']));
  String platform = str(existing?['platform']).isEmpty ? options.first : str(existing?['platform']);
  final custom = TextEditingController(text: options.contains(platform) ? '' : platform);
  if (!options.contains(platform)) platform = 'Other';
  final gross = numCtl(existing?['gross']);
  final tds = numCtl(existing?['tds']);
  final net = numCtl(existing?['net_paid']);
  final paidDate = ctl(existing?['paid_date']);
  final notes = ctl(existing?['notes']);
  String status = str(existing?['status']).isEmpty ? 'Pending' : str(existing?['status']);
  final form = GlobalKey<FormState>();

  final res = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Form(
              key: form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(existing == null ? (isAff ? 'Add affiliate earning' : 'Add other income') : 'Edit earning',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final o in options)
                    ChoiceChip(
                      label: Text(o, style: TextStyle(color: platform == o ? Colors.white : kInk, fontWeight: FontWeight.w600)),
                      selected: platform == o,
                      showCheckmark: false,
                      selectedColor: kMintDark,
                      onSelected: (_) => set(() => platform = o),
                    ),
                ]),
                if (platform == 'Other') ...[
                  const SizedBox(height: 10),
                  TextFormField(controller: custom, decoration: deco(isAff ? 'Platform name' : 'Income name')),
                ],
                const SizedBox(height: 12),
                _MonthField(controller: monthCtl),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: moneyField(gross, 'Earned (gross ₹)', req: true)),
                  const SizedBox(width: 8),
                  Expanded(child: moneyField(tds, 'TDS cut (₹)')),
                ]),
                const Text('Status', style: TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Segmented(options: kIncomeStatuses, value: status, onChanged: (v) => set(() => status = v)),
                if (status == 'Paid') ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: moneyField(net, 'Paid to bank (₹)')),
                    const SizedBox(width: 8),
                    Expanded(child: DateField(paidDate, 'Paid on')),
                  ]),
                ],
                const SizedBox(height: 4),
                textField(notes, 'Notes'),
                Row(children: [
                  if (existing != null)
                    TextButton(
                      onPressed: () => Navigator.pop(c, 'delete'),
                      child: const Text('Delete', style: TextStyle(color: kDanger)),
                    ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(140, 50), backgroundColor: kMintDark),
                    onPressed: () {
                      if (form.currentState!.validate()) Navigator.pop(c, 'save');
                    },
                    child: const Text('Save'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  if (res == 'delete' && existing != null) {
    if (!context.mounted) return;
    if (await confirm(context, 'Delete this entry?', '${str(existing['platform'])} · ${str(existing['month'])}')) {
      await Repo.delete('income', str(existing['id']));
    }
  } else if (res == 'save') {
    final g = toD(gross.text);
    final t = toD(tds.text);
    await Repo.save('income', {
      'id': existing?['id'],
      'source_type': sourceType,
      'platform': platform == 'Other' && custom.text.trim().isNotEmpty ? custom.text.trim() : platform,
      'month': monthCtl.text,
      'gross': g,
      'tds': t,
      'net_paid': status == 'Paid' ? (toD(net.text) > 0 ? toD(net.text) : g - t) : 0,
      'status': status,
      'paid_date': status == 'Paid' ? (nn(paidDate) ?? todayIso()) : null,
      'notes': nn(notes),
    });
  }
}

class _MonthField extends StatefulWidget {
  final TextEditingController controller;
  const _MonthField({required this.controller});
  @override
  State<_MonthField> createState() => _MonthFieldState();
}

class _MonthFieldState extends State<_MonthField> {
  @override
  Widget build(BuildContext context) {
    final d = parseDate('${widget.controller.text}-01') ?? DateTime.now();
    void shift(int n) {
      final x = DateTime(d.year, d.month + n, 1);
      setState(() => widget.controller.text = '${x.year}-${x.month.toString().padLeft(2, '0')}');
    }

    return InputDecorator(
      decoration: deco('Month'),
      child: Row(children: [
        IconButton(onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Previous month'),
        Expanded(
          child: Text('${_monthName(d.month)} ${d.year}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        IconButton(onPressed: () => shift(1), icon: const Icon(Icons.chevron_right), tooltip: 'Next month'),
      ]),
    );
  }
}
