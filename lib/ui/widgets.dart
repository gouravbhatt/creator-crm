import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/repo.dart';

/// Reloads a screen whenever any data changes.
mixin AutoReload<T extends StatefulWidget> on State<T> {
  Future<void> reload();

  void _onChange() {
    if (mounted) reload();
  }

  @override
  void initState() {
    super.initState();
    Repo.changes.addListener(_onChange);
    reload();
  }

  @override
  void dispose() {
    Repo.changes.removeListener(_onChange);
    super.dispose();
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'Delete', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: kDanger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<void> openUrl(BuildContext context, String url) async {
  final u = Uri.tryParse(url.trim());
  if (u == null || !await launchUrl(u, mode: LaunchMode.externalApplication)) {
    if (context.mounted) toast(context, 'Could not open link');
  }
}

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, 'Copied');
}

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  const SectionCard({super.key, this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: Text(title ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                if (trailing != null) trailing!,
              ]),
            ),
          child,
        ]),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? color;
  const StatTile({super.key, required this.label, required this.value, this.sub, this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: kMuted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          ),
          if (sub != null) Text(sub!, style: const TextStyle(fontSize: 11, color: kMuted)),
        ]),
      ),
    );
  }
}

class StatGrid extends StatelessWidget {
  final List<Widget> children;
  const StatGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: children[i]),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
          ]),
        ),
      ));
    }
    return Column(children: rows);
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

Color paymentStatusColor(String s) {
  switch (s) {
    case 'Paid':
      return kOk;
    case 'Overdue':
      return kDanger;
    case 'Partial':
      return kWarn;
    default:
      return kMuted;
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: kMuted),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ]),
      ),
    );
  }
}

class KV extends StatelessWidget {
  final String k;
  final String v;
  final VoidCallback? onTap;
  const KV(this.k, this.v, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (v.isEmpty || v == '—') return const SizedBox.shrink();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: const TextStyle(color: kMuted, fontSize: 13))),
          Expanded(
            child: Text(v,
                style: TextStyle(fontSize: 13, color: onTap != null ? kPrimary : null, fontWeight: FontWeight.w500)),
          ),
        ]),
      ),
    );
  }
}

class BarLine extends StatelessWidget {
  final String label;
  final double fraction;
  final String value;
  final Color color;
  const BarLine({super.key, required this.label, required this.fraction, required this.value, this.color = kPrimary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 96, child: Text(label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.isNaN ? 0 : fraction.clamp(0.0, 1.0),
              minHeight: 12,
              backgroundColor: const Color(0xFFEEF0F3),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
            width: 72,
            child: Text(value,
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ---------------- form fields ----------------

InputDecoration deco(String label, {String? hint, Widget? suffix}) =>
    InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix);

class Gap extends StatelessWidget {
  const Gap({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(height: 12);
}

Widget textField(TextEditingController c, String label,
    {bool req = false,
    TextInputType? keyboard,
    int maxLines = 1,
    String? hint,
    String? Function(String)? validate}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      keyboardType: keyboard,
      maxLines: maxLines,
      minLines: 1,
      textCapitalization: keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
      decoration: deco(req ? '$label *' : label, hint: hint),
      validator: (v) {
        final t = (v ?? '').trim();
        if (req && t.isEmpty) return '$label is required';
        if (t.isNotEmpty && validate != null) return validate(t);
        return null;
      },
    ),
  );
}

Widget moneyField(TextEditingController c, String label, {bool req = false}) => textField(c, label,
    req: req,
    keyboard: const TextInputType.numberWithOptions(decimal: true),
    validate: (t) {
      final v = double.tryParse(t.replaceAll(',', ''));
      if (v == null) return 'Enter a number';
      if (v < 0) return 'Cannot be negative';
      return null;
    });

Widget intField(TextEditingController c, String label) => textField(c, label,
    keyboard: TextInputType.number, validate: (t) => int.tryParse(t) == null ? 'Enter a whole number' : null);

Widget urlField(TextEditingController c, String label, {bool req = false}) => textField(c, label,
    req: req,
    keyboard: TextInputType.url,
    hint: 'https://…',
    validate: (t) => isValidUrl(t) ? null : 'Enter a valid http(s) link');

Widget emailField(TextEditingController c) => textField(c, 'Email',
    keyboard: TextInputType.emailAddress, validate: (t) => isValidEmail(t) ? null : 'Enter a valid email');

class Pick extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final bool allowEmpty;
  final Map<String, String>? labels;
  const Pick(
      {super.key,
      required this.label,
      required this.value,
      required this.options,
      required this.onChanged,
      this.allowEmpty = false,
      this.labels});

  @override
  Widget build(BuildContext context) {
    final v = (value != null && options.contains(value)) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: v,
        isExpanded: true,
        decoration: deco(label),
        items: [
          if (allowEmpty) const DropdownMenuItem<String>(value: null, child: Text('— None —')),
          ...options.map((o) => DropdownMenuItem<String>(value: o, child: Text(labels?[o] ?? o, overflow: TextOverflow.ellipsis))),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Date stored as ISO yyyy-MM-dd text in [controller].
class DateField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  const DateField(this.controller, this.label, {super.key});

  @override
  State<DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<DateField> {
  @override
  Widget build(BuildContext context) {
    final has = widget.controller.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: context,
            initialDate: parseDate(widget.controller.text) ?? now,
            firstDate: DateTime(now.year - 10),
            lastDate: DateTime(now.year + 10),
          );
          if (d != null) setState(() => widget.controller.text = isoDate(d));
        },
        child: InputDecorator(
          decoration: deco(widget.label,
              suffix: has
                  ? IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => widget.controller.clear()))
                  : const Icon(Icons.calendar_today_outlined)),
          child: Text(has ? showDate(widget.controller.text) : 'Not set',
              style: TextStyle(color: has ? null : kMuted)),
        ),
      ),
    );
  }
}

String? nn(TextEditingController c) {
  final t = c.text.trim();
  return t.isEmpty ? null : t;
}

TextEditingController ctl(Object? v) => TextEditingController(text: v == null ? '' : v.toString());

TextEditingController numCtl(Object? v) {
  final d = toD(v);
  if (v == null || d == 0) return TextEditingController();
  return TextEditingController(text: d % 1 == 0 ? d.toInt().toString() : d.toString());
}
