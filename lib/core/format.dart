import 'package:intl/intl.dart';

final NumberFormat _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final NumberFormat _plain = NumberFormat.decimalPattern('en_IN');
final DateFormat _iso = DateFormat('yyyy-MM-dd');
final DateFormat _show = DateFormat('d MMM yyyy');
final DateFormat _month = DateFormat('MMM');

String money(num? v) => _money.format(v ?? 0);
String plainNum(num? v) => _plain.format(v ?? 0);
String isoDate(DateTime d) => _iso.format(d);
String todayIso() => isoDate(DateTime.now());
String monthLabel(DateTime d) => _month.format(d);

DateTime? parseDate(Object? s) {
  if (s == null) return null;
  final t = s.toString();
  if (t.isEmpty) return null;
  return DateTime.tryParse(t);
}

String showDate(Object? s) {
  final d = parseDate(s);
  return d == null ? '—' : _show.format(d);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysFromToday(Object? s) {
  final d = parseDate(s);
  if (d == null) return 1 << 30;
  return dateOnly(d).difference(dateOnly(DateTime.now())).inDays;
}

double toD(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
}

int toI(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? 0;
}

String str(Object? v) => v?.toString() ?? '';

bool isValidUrl(String s) {
  final u = Uri.tryParse(s.trim());
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.contains('.');
}

bool isValidEmail(String s) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

/// Indian financial year (Apr–Mar) containing [d]: returns start date.
DateTime fyStart(DateTime d) => d.month >= 4 ? DateTime(d.year, 4, 1) : DateTime(d.year - 1, 4, 1);

String fyLabel(DateTime start) => '${start.year}-${((start.year + 1) % 100).toString().padLeft(2, '0')}';
