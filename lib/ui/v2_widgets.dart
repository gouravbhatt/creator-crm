import 'dart:io';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/media.dart';
import '../core/snapshot.dart';

/// iOS-style segmented control (used for collab type filters).
class Segmented extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, String>? labels;
  const Segmented({super.key, required this.options, required this.value, required this.onChanged, this.labels});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFECEAF4), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: options.map((o) {
          final on = o == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(o),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: on ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))] : null,
                ),
                child: Text(labels?[o] ?? o,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? kInk : kMuted)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Horizontal row of pill chips; selected one is dark.
class PillRow extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final EdgeInsets padding;
  const PillRow({super.key, required this.options, required this.value, required this.onChanged, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final o = options[i];
          final on = o == value;
          return GestureDetector(
            onTap: () => onChanged(o),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? kInk : Colors.white, borderRadius: BorderRadius.circular(19)),
              child: Text(o, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : const Color(0xFF3B3753))),
            ),
          );
        },
      ),
    );
  }
}

class TypeBadge extends StatelessWidget {
  final String type;
  const TypeBadge(this.type, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: typeTint(type), borderRadius: BorderRadius.circular(8)),
        child: Text(type, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: typeColor(type))),
      );
}

/// Product photo for a collab, or a tinted placeholder in the collab type colour.
class ProductThumb extends StatelessWidget {
  final String? fileName;
  final String type;
  final double size;
  final double radius;
  const ProductThumb({super.key, this.fileName, required this.type, this.size = 64, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: typeTint(type), borderRadius: BorderRadius.circular(radius)),
      child: Icon(type == kPaid ? Icons.campaign_outlined : Icons.inventory_2_outlined, color: typeColor(type), size: size * 0.42),
    );
    final f = fileName;
    if (f == null || f.isEmpty) return placeholder;
    return FutureBuilder<File>(
      future: Media.file(f),
      builder: (_, snap) {
        final file = snap.data;
        if (file == null || !file.existsSync()) return placeholder;
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
        );
      },
    );
  }
}

/// White rounded section with optional title and trailing action.
class Panel extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  const Panel(
      {super.key, this.title, this.trailing, required this.child, this.color = Colors.white, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null || trailing != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(child: Text(title ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              if (trailing != null) trailing!,
            ]),
          ),
        child,
      ]),
    );
  }
}

class SmallLabel extends StatelessWidget {
  final String text;
  final Color color;
  const SmallLabel(this.text, {super.key, this.color = kMuted});
  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.4));
}

/// Collab row used on dashboard and collabs list.
class CollabRow extends StatelessWidget {
  final CollabView c;
  final VoidCallback onTap;
  final double thumb;
  const CollabRow({super.key, required this.c, required this.onTap, this.thumb = 72});

  String get amountText {
    if (c.dealType == kBoth) return '${money(c.agreed)} + ${money(c.barterValue)}';
    if (c.dealType == kBarter) return money(c.barterValue);
    return money(c.agreed);
  }

  (String, Color) get meta {
    if (c.stage == kCancelled) return ('Cancelled', kDanger);
    if (c.pending > 0 && c.paymentStatus == 'Overdue') return ('${money(c.pending)} overdue', kDanger);
    final posted = c.postedDate;
    if (posted != null && c.pending <= 0) return ('Posted ${showDate(posted)}', kBothC);
    if (c.pending > 0 && posted != null) return ('${money(c.pending)} due', kWarn);
    final n = c.nextAction;
    if (n != null && n.$2.isNotEmpty) return ('${n.$1} · ${showDate(n.$2)}', daysFromToday(n.$2) < 0 ? kDanger : kMuted);
    return ('', kMuted);
  }

  @override
  Widget build(BuildContext context) {
    final m = meta;
    final name = c.products.isNotEmpty ? str(c.products.first['name']) : c.title;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ProductThumb(fileName: c.coverImage, type: c.dealType, size: thumb),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(c.brandName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
                  ),
                  const SizedBox(width: 6),
                  Text(amountText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 2),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Row(children: [
                  TypeBadge(c.dealType),
                  const SizedBox(width: 8),
                  CircleAvatar(radius: 4, backgroundColor: stageColor(c.stage)),
                  const SizedBox(width: 4),
                  Text(c.stage, style: const TextStyle(fontSize: 11, color: Color(0xFF3B3753))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(m.$1,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: m.$2, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
