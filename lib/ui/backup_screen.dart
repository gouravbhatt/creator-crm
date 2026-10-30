import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/backup.dart';
import '../core/constants.dart';
import '../core/csv_export.dart';
import '../core/format.dart';
import '../core/repo.dart';
import '../core/security.dart';
import 'widgets.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String _status = '';
  String _lastBackup = '';
  final Set<String> _csv = {...CsvExport.sets};

  @override
  void initState() {
    super.initState();
    Repo.setting('last_backup_at').then((v) {
      if (mounted) setState(() => _lastBackup = v);
    });
  }

  Future<String?> _askPassword({required bool create}) async {
    final a = TextEditingController(), b = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(create ? 'Backup password' : 'Enter backup password'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (create)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('This password encrypts the file. You need it to restore on any phone. It can be your login password.',
                    style: TextStyle(fontSize: 13, color: kMuted)),
              ),
            TextFormField(
              controller: a,
              obscureText: true,
              autofocus: true,
              decoration: deco('Password'),
              validator: (v) => create ? (v == null || v.length < 8 ? 'At least 8 characters' : null) : null,
            ),
            if (create) ...[
              const Gap(),
              TextFormField(
                controller: b,
                obscureText: true,
                decoration: deco('Confirm password'),
                validator: (v) => v != a.text ? 'Does not match' : null,
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(d, true);
              },
              child: const Text('Continue')),
        ],
      ),
    );
    return ok == true ? a.text : null;
  }

  Future<void> _export() async {
    final pw = await _askPassword(create: true);
    if (pw == null) return;
    setState(() {
      _busy = true;
      _status = 'Encrypting backup…';
    });
    try {
      final bytes = await Backup.build(pw);
      final name = 'collabook_${todayIso()}.ccrm';
      final tmp = File(p.join((await getTemporaryDirectory()).path, name));
      await tmp.writeAsBytes(bytes, flush: true);
      await Repo.setSetting('last_backup_at', DateTime.now().toIso8601String());
      if (!mounted) return;
      setState(() {
        _status = 'Backup ready (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB).';
        _lastBackup = DateTime.now().toIso8601String();
      });
      final where = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Save to phone storage'),
                subtitle: const Text('Pick a folder, e.g. Downloads'),
                onTap: () => Navigator.pop(c, 'save')),
            ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share / send'),
                subtitle: const Text('Drive, email, WhatsApp to self, USB…'),
                onTap: () => Navigator.pop(c, 'share')),
          ]),
        ),
      );
      if (where == 'save') {
        final path = await FilePicker.platform.saveFile(dialogTitle: 'Save backup', fileName: name, bytes: bytes);
        if (mounted) setState(() => _status = path == null ? 'Save cancelled. Backup not stored outside the app.' : 'Saved: $name');
      } else if (where == 'share') {
        await Share.shareXFiles([XFile(tmp.path, mimeType: 'application/octet-stream')], subject: name);
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final f = picked?.files.single;
    if (f == null) return;
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null) {
      setState(() => _status = 'Could not read the selected file.');
      return;
    }
    final pw = await _askPassword(create: false);
    if (pw == null) return;
    setState(() {
      _busy = true;
      _status = 'Decrypting and validating…';
    });
    RestorePlan plan;
    try {
      plan = await Backup.read(bytes, pw);
    } on AuthException catch (e) {
      setState(() {
        _busy = false;
        _status = e.message;
      });
      return;
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'This file could not be read as a backup: $e';
      });
      return;
    }
    setState(() {
      _busy = false;
      _status = 'Backup is valid.';
    });
    if (!mounted) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Restore backup?'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Created ${plan.createdAt}'),
            const SizedBox(height: 8),
            Text('${plan.count('brands')} brands · ${plan.count('contacts')} contacts · ${plan.count('collabs')} collabs · '
                '${plan.count('deliverables')} deliverables · ${plan.count('payments')} payments · ${plan.count('products')} products · '
                '${plan.count('product_images')} images · ${plan.count('product_links')} links'),
            if (toI(plan.manifest['missingMedia']) > 0)
              Text('\n${plan.manifest['missingMedia']} image(s) were already missing when this backup was made.',
                  style: const TextStyle(color: kWarn)),
            const SizedBox(height: 12),
            const Text('Merge: adds records from the backup, keeps everything already on this phone.\n'
                'Replace: deletes all current data on this phone, then restores the backup.',
                style: TextStyle(fontSize: 13, color: kMuted)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          OutlinedButton(onPressed: () => Navigator.pop(d, 'merge'), child: const Text('Merge')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kDanger),
            onPressed: () => Navigator.pop(d, 'replace'),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    if (mode == 'replace') {
      final sure = await confirm(context, 'Replace all data?',
          'Everything currently on this phone will be deleted and replaced by the backup. This cannot be undone.',
          ok: 'Replace');
      if (!sure) return;
    }
    setState(() {
      _busy = true;
      _status = 'Restoring…';
    });
    try {
      await Backup.apply(plan, replace: mode == 'replace');
      if (mounted) setState(() => _status = 'Restore complete (${mode == 'replace' ? 'replaced' : 'merged'}).');
    } catch (e) {
      if (mounted) setState(() => _status = 'Restore failed, no changes were committed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_csv.isEmpty) return;
    setState(() {
      _busy = true;
      _status = 'Creating CSV files…';
    });
    try {
      final files = await CsvExport.export(_csv);
      await Share.shareXFiles(files.map((f) => XFile(f.path, mimeType: 'text/csv')).toList(), subject: 'Collabook export');
      if (mounted) setState(() => _status = '${files.length} CSV file(s) exported.');
    } catch (e) {
      if (mounted) setState(() => _status = 'CSV export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & export')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          if (_busy) const LinearProgressIndicator(),
          if (_status.isNotEmpty)
            Card(
              color: const Color(0xFFE8ECFC),
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_status)),
            ),
          SectionCard(
            title: 'Encrypted backup',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                  'One .ccrm file with all brands, contacts, collabs, deliverables, payments, invoices, products, images, links and settings. '
                  'Encrypted with AES-256 using your backup password. Keep a copy off the phone before switching devices.',
                  style: TextStyle(fontSize: 13, color: kMuted)),
              const SizedBox(height: 8),
              Text('Last backup: ${_lastBackup.isEmpty ? 'never' : showDate(_lastBackup)}', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _export, icon: const Icon(Icons.backup_outlined), label: const Text('Create backup')),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _restore, icon: const Icon(Icons.settings_backup_restore), label: const Text('Restore from file')),
            ]),
          ),
          SectionCard(
            title: 'CSV export',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ...CsvExport.sets.map((s) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _csv.contains(s),
                    title: Text(s),
                    onChanged: (v) => setState(() => v == true ? _csv.add(s) : _csv.remove(s)),
                  )),
              const Text('Images are not included in CSV — use the encrypted backup for those.',
                  style: TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(onPressed: _exportCsv, icon: const Icon(Icons.table_view_outlined), label: const Text('Export CSV')),
            ]),
          ),
        ]),
      ),
    );
  }
}
