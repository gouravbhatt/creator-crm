import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';

/// Images are copied into the app's private documents folder; the DB stores only the file name.
/// This avoids temporary picker paths and keeps files portable across backup/restore.
class Media {
  static Directory? _dir;

  static Future<Directory> dir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(docs.path, 'media'));
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  /// Copies a picked file into app storage and returns the stored file name.
  static Future<String> importFile(String sourcePath) async {
    final ext = p.extension(sourcePath).toLowerCase();
    final name = '${AppDb.newId()}${ext.isEmpty ? '.jpg' : ext}';
    final d = await dir();
    await File(sourcePath).copy(p.join(d.path, name));
    return name;
  }

  /// Saves downloaded image bytes into app storage and returns the stored file name.
  static Future<String> importBytes(List<int> bytes, String ext) async {
    final name = '${AppDb.newId()}$ext';
    final d = await dir();
    await File(p.join(d.path, name)).writeAsBytes(bytes, flush: true);
    return name;
  }

  static Future<File> file(String name) async => File(p.join((await dir()).path, p.basename(name)));

  static Future<bool> exists(String name) async => (await file(name)).exists();

  static Future<void> remove(String name) async {
    final f = await file(name);
    if (await f.exists()) await f.delete();
  }

  static Future<void> writeBytes(String name, List<int> bytes, {bool overwrite = true}) async {
    final f = await file(name);
    if (!overwrite && await f.exists()) return;
    await f.writeAsBytes(bytes, flush: true);
  }

  static Future<void> clearAll() async {
    final d = await dir();
    if (await d.exists()) {
      await for (final e in d.list()) {
        if (e is File) await e.delete();
      }
    }
  }
}
