import 'package:flutter/material.dart';

import '../core/constants.dart';
import 'collab_form.dart';
import 'income_screen.dart';
import 'widgets.dart';

/// The + sheet: pick what you're adding. Big, obvious tiles.
Future<void> showAddSheet(BuildContext context, {String? brandId}) async {
  final pick = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (c) => const _AddSheet(),
  );
  if (pick == null || !context.mounted) return;
  if (pick == 'Affiliate' || pick == 'Other') {
    await incomeDialog(context, sourceType: pick);
  } else {
    await push(context, CollabFormScreen(kind: pick, brandId: brandId));
  }
}

class _AddSheet extends StatelessWidget {
  const _AddSheet();

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('What are you adding?', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            const Text('BRAND COLLAB', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [for (final k in kDealTypes) _tile(context, k, kKindIcon[k]!, k, kKindHint[k]!, typeColor(k), typeTint(k))],
            ),
            const SizedBox(height: 16),
            const Text('OTHER INCOME', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _row(context, 'Affiliate', 'A', 'Affiliate payout', 'Amazon, Wishlink…', kMintDark, kMintTint)),
              const SizedBox(width: 10),
              Expanded(child: _row(context, 'Other', '+', 'Other income', 'AdSense, bonus…', kAmberDark, kAmberTint)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, String value, String icon, String label, String hint, Color c, Color tint) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(side: const BorderSide(color: kLine, width: 1.5), borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pop(context, value),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
              child: Text(icon, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            const Spacer(),
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kInk)),
            Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kMuted)),
          ]),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String value, String icon, String label, String hint, Color c, Color tint) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(side: const BorderSide(color: kLine, width: 1.5), borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(context, value),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
              child: Text(icon, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kInk)),
                Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kMuted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
