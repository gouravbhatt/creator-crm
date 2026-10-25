import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/repo.dart';
import 'widgets.dart';

/// Create / edit a deliverable (reel, story, post…) with its draft + live links,
/// compliance checklist and performance snapshots.
class DeliverableScreen extends StatefulWidget {
  final String collabId;
  final String? deliverableId;
  const DeliverableScreen({super.key, required this.collabId, this.deliverableId});
  @override
  State<DeliverableScreen> createState() => _DeliverableScreenState();
}

class _DeliverableScreenState extends State<DeliverableScreen> {
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  String? _id;
  Rec _row = {};
  String _type = 'Reel';
  String _platform = 'Instagram';
  String _status = 'Planned';
  int _revisions = 0;
  List<bool> _checks = List<bool>.filled(kChecklist.length, false);
  List<Rec> _metrics = [];
  final title = TextEditingController(),
      due = TextEditingController(),
      liveDate = TextEditingController(),
      draft = TextEditingController(),
      live = TextEditingController(),
      feedback = TextEditingController(),
      notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _id = widget.deliverableId;
    _load();
  }

  Future<void> _load() async {
    if (_id != null) {
      _row = await Repo.byId('deliverables', _id!) ?? {};
      _type = str(_row['type']).isEmpty ? 'Reel' : str(_row['type']);
      _platform = str(_row['platform']).isEmpty ? 'Instagram' : str(_row['platform']);
      _status = str(_row['status']).isEmpty ? 'Planned' : str(_row['status']);
      _revisions = toI(_row['revision_count']);
      title.text = str(_row['title']);
      due.text = str(_row['due_date']);
      liveDate.text = str(_row['live_date']);
      draft.text = str(_row['draft_link']);
      live.text = str(_row['live_link']);
      feedback.text = str(_row['feedback']);
      notes.text = str(_row['notes']);
      try {
        final l = jsonDecode(str(_row['checklist'])) as List;
        _checks = List<bool>.generate(kChecklist.length, (i) => i < l.length && l[i] == true);
      } catch (_) {}
      _metrics = await Repo.all('metrics', where: 'deliverable_id = ?', args: [_id], orderBy: 'captured_at');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<bool> _save({bool close = true}) async {
    if (!_form.currentState!.validate()) return false;
    final liveUrl = live.text.trim();
    if (liveUrl.isNotEmpty) {
      final dup = await Repo.all('deliverables', where: 'live_link = ? AND id != ?', args: [liveUrl, _id ?? '']);
      if (dup.isNotEmpty && mounted) {
        final go = await confirm(context, 'Duplicate link', 'This live link is already saved on another deliverable. Save anyway?',
            ok: 'Save anyway', danger: false);
        if (!go) return false;
      }
    }
    var status = _status;
    if (liveUrl.isNotEmpty && status != 'Live') {
      if (!mounted) return false;
      final mark = await confirm(context, 'Mark as Live?', 'A live link was added. Set status to Live?', ok: 'Mark Live', danger: false);
      if (mark) status = 'Live';
    }
    final isNew = _id == null;
    final oldStatus = str(_row['status']);
    final row = {
      'id': _id,
      'collab_id': widget.collabId,
      'type': _type,
      'platform': _platform,
      'title': nn(title),
      'due_date': nn(due),
      'live_date': (status == 'Live' && liveDate.text.isEmpty) ? todayIso() : nn(liveDate),
      'status': status,
      'draft_link': nn(draft),
      'live_link': liveUrl.isEmpty ? null : liveUrl,
      'revision_count': _revisions,
      'checklist': jsonEncode(_checks),
      'feedback': nn(feedback),
      'notes': nn(notes),
    };
    final id = await Repo.save('deliverables', row);
    final name = '$_type${title.text.trim().isEmpty ? '' : ' · ${title.text.trim()}'}';
    if (isNew) {
      await Repo.log(widget.collabId, 'Deliverable added: $name');
    } else if (oldStatus != status) {
      await Repo.log(widget.collabId, '$name: $oldStatus → $status${status == 'Revision' ? ' (rev $_revisions)' : ''}');
    }
    if (liveUrl.isNotEmpty && liveUrl != str(_row['live_link'])) {
      await Repo.log(widget.collabId, '$name live link added');
    }
    Repo.notify();
    _id = id;
    _row = row..['id'] = id;
    _status = status;
    if (close && mounted) Navigator.pop(context);
    if (!close && mounted) setState(() {});
    return true;
  }

  Future<void> _delete() async {
    if (_id == null) return;
    if (!await confirm(context, 'Delete deliverable?', 'Its links, checklist and metrics will be removed.')) return;
    await Repo.delete('deliverables', _id!);
    await Repo.log(widget.collabId, 'Deliverable deleted: $_type');
    Repo.notify();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _metricDialog({Rec? existing}) async {
    if (_id == null) {
      final ok = await _save(close: false);
      if (!ok) return;
    }
    String label = str(existing?['label']).isEmpty ? _suggestLabel() : str(existing?['label']);
    final date = ctl(existing?['captured_at'] ?? todayIso());
    final f = <String, TextEditingController>{
      for (final k in ['views', 'reach', 'likes', 'comments', 'shares', 'saves'])
        k: TextEditingController(text: existing == null ? '' : str(existing[k])),
    };
    if (!mounted) return;
    final res = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(existing == null ? 'Log performance' : 'Edit snapshot'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Pick(label: 'Snapshot', value: label, options: kSnapshotLabels, onChanged: (v) => set(() => label = v ?? label)),
              DateField(date, 'Captured on'),
              for (final e in f.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: e.value,
                    keyboardType: TextInputType.number,
                    decoration: deco(e.key[0].toUpperCase() + e.key.substring(1)),
                  ),
                ),
            ]),
          ),
          actions: [
            if (existing != null)
              TextButton(onPressed: () => Navigator.pop(d, 'delete'), child: const Text('Delete', style: TextStyle(color: kDanger))),
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, 'save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (res == 'delete' && existing != null) {
      await Repo.delete('metrics', str(existing['id']));
    } else if (res == 'save') {
      await Repo.save('metrics', {
        'id': existing?['id'],
        'deliverable_id': _id,
        'label': label,
        'captured_at': date.text.isEmpty ? todayIso() : date.text,
        for (final e in f.entries) e.key: toI(e.value.text),
      });
      if (existing == null) await Repo.log(widget.collabId, '$_type $label metrics logged: ${plainNum(toI(f['views']!.text))} views');
    }
    _metrics = await Repo.all('metrics', where: 'deliverable_id = ?', args: [_id], orderBy: 'captured_at');
    Repo.notify();
    if (mounted) setState(() {});
  }

  String _suggestLabel() {
    final have = _metrics.map((m) => str(m['label'])).toSet();
    for (final l in ['24h', '7d', '30d']) {
      if (!have.contains(l)) return l;
    }
    return 'Custom';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_id == null ? 'New deliverable' : 'Deliverable'),
        actions: [
          if (_id != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Delete'),
          TextButton(onPressed: _loading ? null : () => _save(), child: const Text('Save')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                SectionCard(
                  title: 'Basics',
                  child: Column(children: [
                    Pick(label: 'Type', value: _type, options: kDeliverableTypes, onChanged: (v) => setState(() => _type = v ?? _type)),
                    Pick(
                        label: 'Platform',
                        value: _platform,
                        options: kPlatforms,
                        onChanged: (v) => setState(() => _platform = v ?? _platform)),
                    textField(title, 'Title / label', hint: 'e.g. Launch reel 1'),
                    DateField(due, 'Draft due'),
                    DateField(liveDate, 'Go-live date'),
                  ]),
                ),
                SectionCard(
                  title: 'Status',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: kDeliverableStatuses
                          .map((st) => ChoiceChip(
                                label: Text(st),
                                selected: _status == st,
                                onSelected: (_) => setState(() {
                                  if (st == 'Revision' && _status != 'Revision') _revisions++;
                                  _status = st;
                                }),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('Revisions'),
                      const Spacer(),
                      IconButton(
                          onPressed: _revisions > 0 ? () => setState(() => _revisions--) : null,
                          icon: const Icon(Icons.remove_circle_outline)),
                      Text('$_revisions', style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(onPressed: () => setState(() => _revisions++), icon: const Icon(Icons.add_circle_outline)),
                    ]),
                    textField(feedback, 'Brand feedback', maxLines: 3, keyboard: TextInputType.multiline),
                  ]),
                ),
                SectionCard(
                  title: 'Links',
                  child: Column(children: [
                    _linkRow(draft, 'Draft link'),
                    _linkRow(live, 'Live link (reel / post URL)'),
                  ]),
                ),
                SectionCard(
                  title: 'Compliance checklist',
                  child: Column(
                    children: List.generate(
                      kChecklist.length,
                      (i) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        value: _checks[i],
                        title: Text(kChecklist[i]),
                        onChanged: (v) => setState(() => _checks[i] = v ?? false),
                      ),
                    ),
                  ),
                ),
                SectionCard(
                  title: 'Performance snapshots',
                  trailing: TextButton(onPressed: () => _metricDialog(), child: const Text('+ Log')),
                  child: _metricsTable(),
                ),
                SectionCard(child: textField(notes, 'Notes', maxLines: 4, keyboard: TextInputType.multiline)),
              ]),
            ),
    );
  }

  Widget _linkRow(TextEditingController c, String label) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: urlField(c, label)),
      IconButton(
        tooltip: 'Copy',
        icon: const Icon(Icons.copy, size: 20),
        onPressed: () => c.text.trim().isEmpty ? null : copyText(context, c.text.trim()),
      ),
      IconButton(
        tooltip: 'Open',
        icon: const Icon(Icons.open_in_new, size: 20),
        onPressed: () => isValidUrl(c.text) ? openUrl(context, c.text.trim()) : toast(context, 'Enter a valid link first'),
      ),
    ]);
  }

  Widget _metricsTable() {
    if (_metrics.isEmpty) {
      return const Text('Log views, likes and more at 24h, 7 days and 30 days after posting.', style: TextStyle(color: kMuted));
    }
    const cols = ['views', 'reach', 'likes', 'comments', 'shares', 'saves'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        headingRowHeight: 36,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columns: [
          const DataColumn(label: Text('When')),
          for (final c in cols) DataColumn(label: Text(c[0].toUpperCase() + c.substring(1)), numeric: true),
        ],
        rows: _metrics.map((m) {
          final views = toI(m['views']);
          final eng = toI(m['likes']) + toI(m['comments']) + toI(m['shares']) + toI(m['saves']);
          return DataRow(
            onSelectChanged: (_) => _metricDialog(existing: m),
            cells: [
              DataCell(Text('${str(m['label'])}\n${views > 0 ? '${(eng * 100 / views).toStringAsFixed(1)}% eng' : ''}',
                  style: const TextStyle(fontSize: 12))),
              for (final c in cols) DataCell(Text(plainNum(toI(m[c])))),
            ],
          );
        }).toList(),
      ),
    );
  }
}
