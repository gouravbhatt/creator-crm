import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'db.dart';
import 'format.dart';

typedef Rec = Map<String, dynamic>;

/// Thin data-access layer over the encrypted database.
/// Every write bumps [changes] so open screens reload.
class Repo {
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static Database get _db => AppDb.db;

  static void notify() => changes.value++;

  static Future<List<Rec>> all(String table, {String? where, List<Object?>? args, String? orderBy}) async {
    final r = await _db.query(table, where: where, whereArgs: args, orderBy: orderBy);
    return r.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<Rec?> byId(String table, String id) async {
    final r = await _db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : Map<String, dynamic>.from(r.first);
  }

  static Future<int> count(String table, {String? where, List<Object?>? args}) async {
    final r = await _db.rawQuery(
        'SELECT COUNT(*) AS n FROM $table${where == null ? '' : ' WHERE $where'}', args);
    return toI(r.first['n']);
  }

  /// Insert when row has no id, otherwise update. Returns the id.
  static Future<String> save(String table, Rec row, {DatabaseExecutor? tx}) async {
    final ex = tx ?? _db;
    final now = DateTime.now().toIso8601String();
    final m = Map<String, dynamic>.from(row);
    final id = str(m['id']);
    if (id.isEmpty) {
      m['id'] = AppDb.newId();
      m['created_at'] = now;
      m['updated_at'] = now;
      await ex.insert(table, m);
    } else {
      m['updated_at'] = now;
      m.remove('created_at');
      await ex.update(table, m, where: 'id = ?', whereArgs: [id]);
    }
    if (tx == null) notify();
    return m['id'] as String;
  }

  static Future<void> delete(String table, String id) async {
    await _db.delete(table, where: 'id = ?', whereArgs: [id]);
    notify();
  }

  static Future<T> transaction<T>(Future<T> Function(Transaction tx) action) async {
    final r = await _db.transaction(action);
    notify();
    return r;
  }

  // ---------- settings ----------
  static Future<String> setting(String key, [String fallback = '']) async {
    final r = await _db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (r.isEmpty) return fallback;
    return str(r.first['value']).isEmpty ? fallback : str(r.first['value']);
  }

  static Future<int> settingInt(String key, int fallback) async => toI(await setting(key, '$fallback'));

  static Future<void> setSetting(String key, String value) async {
    await _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    notify();
  }

  static Future<Map<String, String>> settings() async {
    final r = await _db.query('settings');
    return {for (final e in r) str(e['key']): str(e['value'])};
  }

  // ---------- activity ----------
  static Future<void> log(String? collabId, String message, {DatabaseExecutor? tx}) async {
    final now = DateTime.now().toIso8601String();
    await (tx ?? _db).insert('activity', {
      'id': AppDb.newId(),
      'collab_id': collabId,
      'message': message,
      'created_at': now,
      'updated_at': now,
    });
  }

  // ---------- invoices ----------
  static Future<String> nextInvoiceNumber() async {
    final prefix = await setting('invoice_prefix', 'INV');
    final seq = await settingInt('invoice_seq', 0) + 1;
    final fy = fyLabel(fyStart(DateTime.now()));
    return '$prefix/$fy/${seq.toString().padLeft(3, '0')}';
  }

  static Future<void> consumeInvoiceNumber() async {
    final seq = await settingInt('invoice_seq', 0) + 1;
    await setSetting('invoice_seq', '$seq');
  }
}
