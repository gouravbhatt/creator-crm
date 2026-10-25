import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'db.dart';
import 'format.dart';
import 'media.dart';
import 'repo.dart';
import 'security.dart';

/// Encrypted, versioned backup file (.ccrm).
///
/// File layout:  "CCRM" | formatVersion(1 byte) | salt(16) | nonce(12) | AES-256-GCM(zip) | mac(16)
/// Zip contents: manifest.json, data.json (all tables as rows), media/<image files>
class Backup {
  static const List<int> _magic = [0x43, 0x43, 0x52, 0x4D]; // CCRM
  static const int formatVersion = 1;

  static Future<Uint8List> build(String password) async {
    final db = AppDb.db;
    final data = <String, List<Map<String, Object?>>>{};
    for (final t in AppDb.tables) {
      data[t] = await db.query(t);
    }
    final archive = Archive();
    final hashes = <String, String>{};

    Future<void> add(String name, List<int> bytes) async {
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      hashes[name] = await Crypto.sha256Hex(bytes);
    }

    await add('data.json', utf8.encode(jsonEncode(data)));

    final mediaNames = <String>{
      for (final r in data['product_images']!) str(r['file_name']),
    };
    for (final s in data['settings']!) {
      if (s['key'] == 'signature_file' && str(s['value']).isNotEmpty) mediaNames.add(str(s['value']));
    }
    var missing = 0;
    for (final n in mediaNames) {
      final f = await Media.file(n);
      if (await f.exists()) {
        await add('media/$n', await f.readAsBytes());
      } else {
        missing++;
      }
    }

    final manifest = {
      'format': 'ccrm',
      'formatVersion': formatVersion,
      'schemaVersion': AppDb.schemaVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'counts': {for (final e in data.entries) e.key: e.value.length},
      'missingMedia': missing,
      'files': hashes,
    };
    final mBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(ArchiveFile('manifest.json', mBytes.length, mBytes));

    final zip = ZipEncoder().encode(archive);
    if (zip == null) throw StateError('Could not create archive');

    final salt = Crypto.randomBytes(16);
    final key = await Crypto.deriveKey(password, salt);
    final sealed = await Crypto.sealInBackground(key, zip);
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(formatVersion)
      ..add(salt)
      ..add(sealed);
    return out.toBytes();
  }

  /// Decrypts and validates a backup without touching the database.
  static Future<RestorePlan> read(Uint8List bytes, String password) async {
    if (bytes.length < 4 + 1 + 16 + 28) throw AuthException('Not a Creator CRM backup file');
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _magic[i]) throw AuthException('Not a Creator CRM backup file');
    }
    final ver = bytes[4];
    if (ver > formatVersion) throw AuthException('Backup was made by a newer app version. Update the app first.');
    final salt = bytes.sublist(5, 21);
    final key = await Crypto.deriveKey(password, salt);
    final zip = await Crypto.openInBackground(key, bytes.sublist(21));

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zip, verify: true);
    } catch (_) {
      throw AuthException('Backup archive is corrupted');
    }
    final files = <String, List<int>>{};
    for (final f in archive.files) {
      if (f.isFile) files[f.name] = f.content as List<int>;
    }
    final mRaw = files['manifest.json'];
    final dRaw = files['data.json'];
    if (mRaw == null || dRaw == null) throw AuthException('Backup is missing required files');
    final manifest = jsonDecode(utf8.decode(mRaw)) as Map<String, dynamic>;
    if (manifest['format'] != 'ccrm') throw AuthException('Unknown backup format');
    if (toI(manifest['schemaVersion']) > AppDb.schemaVersion) {
      throw AuthException('Backup uses a newer database version. Update the app first.');
    }
    final hashes = (manifest['files'] as Map).cast<String, dynamic>();
    for (final e in hashes.entries) {
      final b = files[e.key];
      if (b == null) throw AuthException('Backup is incomplete: ${e.key} missing');
      if (await Crypto.sha256Hex(b) != e.value) throw AuthException('Backup integrity check failed: ${e.key}');
    }
    final decoded = jsonDecode(utf8.decode(dRaw)) as Map<String, dynamic>;
    final data = <String, List<Map<String, dynamic>>>{};
    for (final t in AppDb.tables) {
      final l = decoded[t];
      data[t] = l is List ? l.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
    }
    final media = <String, List<int>>{
      for (final e in files.entries)
        if (e.key.startsWith('media/')) e.key.substring(6): e.value,
    };
    return RestorePlan(manifest, data, media);
  }

  /// Applies a validated plan in one transaction. [replace]=true wipes current data first;
  /// otherwise records are merged and existing records with the same id are kept.
  static Future<void> apply(RestorePlan plan, {required bool replace}) async {
    final db = AppDb.db;
    final columns = <String, Set<String>>{};
    for (final t in AppDb.tables) {
      final info = await db.rawQuery('PRAGMA table_info($t)');
      columns[t] = info.map((e) => str(e['name'])).toSet();
    }
    await db.transaction((tx) async {
      if (replace) {
        for (final t in AppDb.tables.reversed) {
          await tx.delete(t);
        }
      }
      for (final t in AppDb.tables) {
        final cols = columns[t]!;
        final batch = tx.batch();
        for (final r in plan.data[t]!) {
          final row = {
            for (final e in r.entries)
              if (cols.contains(e.key)) e.key: e.value,
          };
          if (t == 'settings' && !replace) {
            batch.insert(t, row, conflictAlgorithm: ConflictAlgorithm.ignore);
          } else {
            batch.insert(t, row, conflictAlgorithm: replace ? ConflictAlgorithm.replace : ConflictAlgorithm.ignore);
          }
        }
        await batch.commit(noResult: true);
      }
    });
    if (replace) await Media.clearAll();
    for (final e in plan.media.entries) {
      await Media.writeBytes(e.key, e.value, overwrite: replace);
    }
    Repo.notify();
  }
}

class RestorePlan {
  final Map<String, dynamic> manifest;
  final Map<String, List<Map<String, dynamic>>> data;
  final Map<String, List<int>> media;
  RestorePlan(this.manifest, this.data, this.media);

  int count(String t) => data[t]?.length ?? 0;
  String get createdAt => showDate(manifest['createdAt']);
}
