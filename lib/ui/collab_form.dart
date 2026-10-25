import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/link_preview.dart';
import '../core/media.dart';
import '../core/repo.dart';
import 'collab_detail.dart';
import 'v2_widgets.dart';
import 'widgets.dart';

/// One barter product being added from the New collab screen.
class _ProductDraft {
  final link = TextEditingController();
  final name = TextEditingController();
  final value = TextEditingController();
  final qty = TextEditingController(text: '1');
  LinkPreview? preview;
  final Set<String> pickedUrls = {};
  final List<String> localPhotos = [];
  bool fetching = false;
  String? error;

  bool get isBlank => link.text.trim().isEmpty && name.text.trim().isEmpty && value.text.trim().isEmpty;
  double get total => toD(value.text) * (toI(qty.text) <= 0 ? 1 : toI(qty.text));
}

class CollabFormScreen extends StatefulWidget {
  final String? collabId;
  final String? brandId;
  const CollabFormScreen({super.key, this.collabId, this.brandId});
  @override
  State<CollabFormScreen> createState() => _CollabFormScreenState();
}

class _CollabFormScreenState extends State<CollabFormScreen> {
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  bool get _isNew => widget.collabId == null;
  Rec _row = {};
  List<Rec> _brands = [];
  List<Rec> _recentBrands = [];
  List<Rec> _contacts = [];
  int _linkedProducts = 0;
  int _maxImages = 5;

  String? _brandId;
  String? _contactId;
  String? _source;
  String _type = kBarter;
  String _stage = 'Confirmed';
  final List<_ProductDraft> _products = [_ProductDraft()];
  final Map<String, int> _counts = {'Reel': 1, 'Story': 0, 'Post': 0, 'YouTube video': 0};

  final title = TextEditingController(),
      amount = TextEditingController(),
      barterFallback = TextEditingController(),
      payDue = TextEditingController(),
      advance = TextEditingController(),
      postBy = TextEditingController(),
      campaign = TextEditingController(),
      start = TextEditingController(),
      end = TextEditingController(),
      terms = TextEditingController(),
      rights = TextEditingController(),
      exclusivity = TextEditingController(),
      renewal = TextEditingController(),
      links = TextEditingController(),
      notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _brands = await Repo.all('brands', orderBy: 'name COLLATE NOCASE');
    _contacts = await Repo.all('contacts', orderBy: 'name COLLATE NOCASE');
    _maxImages = await Repo.settingInt('max_images', 5);
    final recent = await Repo.all('collabs', orderBy: 'updated_at DESC');
    final seen = <String>{};
    _recentBrands = [];
    for (final c in recent) {
      final b = str(c['brand_id']);
      if (seen.add(b)) {
        final match = _brands.where((x) => x['id'] == b);
        if (match.isNotEmpty) _recentBrands.add(match.first);
      }
      if (_recentBrands.length >= 3) break;
    }
    _brandId = widget.brandId;
    if (!_isNew) {
      _row = await Repo.byId('collabs', widget.collabId!) ?? {};
      _brandId = str(_row['brand_id']);
      _contactId = _row['contact_id'] as String?;
      _source = _row['source'] as String?;
      _type = kDealTypes.contains(str(_row['deal_type'])) ? str(_row['deal_type']) : kPaid;
      _stage = kAllStages.contains(str(_row['stage'])) ? str(_row['stage']) : 'Confirmed';
      title.text = str(_row['title']);
      amount.text = numCtl(_row['agreed_amount']).text;
      barterFallback.text = numCtl(_row['barter_value']).text;
      payDue.text = str(_row['payment_due_date']);
      campaign.text = str(_row['campaign']);
      start.text = str(_row['start_date']);
      end.text = str(_row['end_date']);
      postBy.text = str(_row['publish_date']);
      terms.text = str(_row['payment_terms']);
      rights.text = str(_row['usage_rights_until']);
      exclusivity.text = str(_row['exclusivity_until']);
      renewal.text = str(_row['renewal_date']);
      links.text = str(_row['links']);
      notes.text = str(_row['notes']);
      _linkedProducts = await Repo.count('products', where: 'collab_id = ?', args: [widget.collabId]);
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _showProduct => _type != kPaid;
  bool get _showPaid => _type != kBarter;

  String get _brandName {
    for (final b in _brands) {
      if (b['id'] == _brandId) return str(b['name']);
    }
    return '';
  }

  Future<void> _newBrand([String prefill = '']) async {
    final ctrl = TextEditingController(text: prefill);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('New brand'),
        content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.words, decoration: deco('Brand name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, ctrl.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final existing = _brands.where((b) => str(b['name']).toLowerCase() == name.toLowerCase()).toList();
    final id = existing.isNotEmpty ? str(existing.first['id']) : await Repo.save('brands', {'name': name});
    _brands = await Repo.all('brands', orderBy: 'name COLLATE NOCASE');
    setState(() => _brandId = id);
  }

  Future<void> _pickBrand() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _BrandPicker(brands: _brands),
    );
    if (picked != null && picked.startsWith('__new__:')) {
      await _newBrand(picked.substring(8));
    } else if (picked != null) {
      setState(() {
        _brandId = picked;
        _contactId = null;
      });
    }
  }

  Future<void> _fetch(_ProductDraft p) async {
    final url = p.link.text.trim();
    if (!isValidUrl(url)) {
      setState(() => p.error = 'Paste a full link starting with https://');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      p.fetching = true;
      p.error = null;
    });
    try {
      final r = await LinkPreview.fetch(url);
      setState(() {
        p.preview = r;
        if (r.title != null) p.name.text = r.title!;
        if (r.price != null && p.value.text.trim().isEmpty) {
          p.value.text = r.price! % 1 == 0 ? r.price!.toInt().toString() : r.price!.toStringAsFixed(2);
        }
        p.pickedUrls
          ..clear()
          ..addAll(r.images.take(_maxImages < 3 ? _maxImages : 3));
        final b = (r.brand ?? '').trim().toLowerCase();
        if (_brandId == null && b.isNotEmpty) {
          final m = _brands.where((x) => str(x['name']).toLowerCase() == b).toList();
          if (m.isNotEmpty) _brandId = str(m.first['id']);
        }
      });
    } catch (e) {
      setState(() => p.error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => p.fetching = false);
    }
  }

  Future<void> _addPhoto(_ProductDraft p, ImageSource src) async {
    final room = _maxImages - p.pickedUrls.length - p.localPhotos.length;
    if (room <= 0) {
      toast(context, 'Image limit is $_maxImages per product (change in Profile › Limits)');
      return;
    }
    final picker = ImagePicker();
    if (src == ImageSource.camera) {
      final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2000);
      if (f != null) setState(() => p.localPhotos.add(f.path));
    } else {
      final fs = await picker.pickMultiImage(imageQuality: 85, maxWidth: 2000);
      setState(() => p.localPhotos.addAll(fs.take(room).map((e) => e.path)));
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_brandId == null || _brandId!.isEmpty) {
      toast(context, 'Choose a brand');
      return;
    }
    final drafts = _products.where((p) => !p.isBlank).toList();
    if (_isNew && _showProduct) {
      if (drafts.isEmpty) {
        toast(context, 'Add the barter product (paste a link or type its name)');
        return;
      }
      if (drafts.any((p) => p.name.text.trim().isEmpty)) {
        toast(context, 'Each product needs a name');
        return;
      }
    }
    if (_showPaid && toD(amount.text) <= 0) {
      toast(context, 'Enter the agreed amount');
      return;
    }
    setState(() => _saving = true);
    try {
      final firstName = drafts.isNotEmpty ? drafts.first.name.text.trim() : '';
      final autoTitle = firstName.isNotEmpty ? firstName : '$_brandName collab';
      final barterValue = _isNew ? drafts.fold<double>(0, (a, p) => a + p.total) : toD(barterFallback.text);
      final row = <String, dynamic>{
        'id': widget.collabId,
        'brand_id': _brandId,
        'contact_id': _contactId,
        'title': title.text.trim().isEmpty ? autoTitle : title.text.trim(),
        'campaign': nn(campaign),
        'deal_type': _type,
        'agreed_amount': _showPaid ? toD(amount.text) : 0,
        'barter_value': _showProduct ? barterValue : 0,
        'stage': _stage,
        'source': _source,
        'start_date': nn(start),
        'end_date': nn(end),
        'publish_date': nn(postBy),
        'payment_due_date': _showPaid ? nn(payDue) : null,
        'payment_terms': nn(terms),
        'usage_rights_until': nn(rights),
        'exclusivity_until': nn(exclusivity),
        'renewal_date': nn(renewal),
        'links': nn(links),
        'notes': nn(notes),
      };
      final id = await Repo.save('collabs', row);
      if (_isNew) {
        await Repo.log(id, 'Collab created ($_type) at stage $_stage');
        if (_showProduct) await _saveProducts(id, drafts);
        await _saveDeliverables(id);
        final adv = toD(advance.text);
        if (_showPaid && adv > 0) {
          await Repo.save('payments', {'collab_id': id, 'amount': adv, 'tds': 0, 'received_date': todayIso(), 'notes': 'Advance'});
          await Repo.log(id, 'Advance received: ${money(adv)}');
        }
      } else if (str(_row['stage']) != _stage) {
        await Repo.log(id, 'Stage: ${str(_row['stage'])} → $_stage');
      }
      Repo.notify();
      if (!mounted) return;
      final nav = Navigator.of(context);
      nav.pop(id);
      if (_isNew) nav.push(MaterialPageRoute(builder: (_) => CollabDetailScreen(collabId: id)));
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveProducts(String collabId, List<_ProductDraft> drafts) async {
    var failed = 0;
    for (final p in drafts) {
      final pid = await Repo.save('products', {
        'brand_id': _brandId,
        'collab_id': collabId,
        'name': p.name.text.trim(),
        'description': p.preview?.description,
        'category': p.preview?.category,
        'purchase_price': toD(p.value.text),
        'quantity': toI(p.qty.text) <= 0 ? 1 : toI(p.qty.text),
      });
      var sort = 0;
      for (final u in p.preview?.images.where(p.pickedUrls.contains) ?? const Iterable<String>.empty()) {
        if (sort >= _maxImages) break;
        final f = await LinkPreview.downloadImage(u);
        if (f == null) {
          failed++;
          continue;
        }
        await Repo.save('product_images', {'product_id': pid, 'file_name': f, 'sort': sort++});
      }
      for (final path in p.localPhotos) {
        if (sort >= _maxImages) break;
        final f = await Media.importFile(path);
        await Repo.save('product_images', {'product_id': pid, 'file_name': f, 'sort': sort++});
      }
      final url = p.link.text.trim();
      if (isValidUrl(url)) {
        await Repo.save('product_links', {
          'product_id': pid,
          'url': url,
          'title': p.preview?.siteName ?? Uri.parse(url).host.replaceFirst('www.', ''),
          'link_type': 'Shopping',
          'sort': 0,
        });
      }
      await Repo.log(collabId, 'Product added: ${p.name.text.trim()} (${money(p.total)})');
    }
    if (failed > 0 && mounted) toast(context, '$failed photo(s) could not be downloaded');
  }

  Future<void> _saveDeliverables(String collabId) async {
    for (final e in _counts.entries) {
      for (var i = 1; i <= e.value; i++) {
        await Repo.save('deliverables', {
          'collab_id': collabId,
          'type': e.key == 'YouTube video' ? 'YouTube video' : e.key,
          'platform': e.key == 'YouTube video' ? 'YouTube' : 'Instagram',
          'title': e.value > 1 ? '$i' : null,
          'due_date': nn(postBy),
          'status': 'Planned',
          'revision_count': 0,
        });
      }
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final total = (_showPaid ? toD(amount.text) : 0) +
        (_showProduct ? (_isNew ? _products.fold<double>(0, (a, p) => a + p.total) : toD(barterFallback.text)) : 0);
    var n = 2;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text(_isNew ? 'New collab' : 'Edit collab', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  boxShadow: [BoxShadow(color: Color(0x0F17142B), blurRadius: 20, offset: Offset(0, -4))],
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Total value', style: TextStyle(fontSize: 11, color: kMuted)),
                      Text(money(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(minimumSize: const Size(150, 52)),
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_isNew ? 'Save collab' : 'Save'),
                  ),
                ]),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              onChanged: () => setState(() {}),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                _brandPanel(),
                _typePanel(),
                if (_showProduct) _isNew ? _productPanel(++n) : _barterEditPanel(++n),
                if (_showPaid) _paidPanel(++n),
                if (_isNew) _postPanel(++n),
                _stagePanel(),
                _moreDetails(),
              ]),
            ),
    );
  }

  Widget _brandPanel() {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SmallLabel('1 · Brand'),
        const SizedBox(height: 10),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
              side: BorderSide(color: _brandId == null ? const Color(0xFFE2E0EC) : kPrimary, width: 1.5),
              borderRadius: BorderRadius.circular(14)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _pickBrand,
            child: SizedBox(
              height: 54,
              child: Row(children: [
                const SizedBox(width: 12),
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: kPrimaryTint, borderRadius: BorderRadius.circular(9)),
                  child: Text(_brandName.isEmpty ? '?' : _brandName[0].toUpperCase(),
                      style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_brandName.isEmpty ? 'Choose brand' : _brandName,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _brandName.isEmpty ? kMuted : kInk)),
                ),
                Text(_brandId == null ? 'Select' : 'Change', style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(width: 12),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ..._recentBrands.where((b) => b['id'] != _brandId).map((b) => ActionChip(
                label: Text(str(b['name'])),
                backgroundColor: kBg,
                onPressed: () => setState(() {
                  _brandId = str(b['id']);
                  _contactId = null;
                }),
              )),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16, color: kPrimary),
            label: const Text('New brand', style: TextStyle(color: kPrimary)),
            backgroundColor: kPrimaryTint,
            onPressed: () => _newBrand(),
          ),
        ]),
        const SizedBox(height: 12),
        TextFormField(controller: title, decoration: deco('Collab name (optional)', hint: 'Auto: product name')),
      ]),
    );
  }

  Widget _typePanel() {
    Widget card(String t, IconData icon) {
      final on = _type == t;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _type = t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 86,
            decoration: BoxDecoration(
              color: on ? typeTint(t) : Colors.white,
              border: Border.all(color: on ? typeColor(t) : const Color(0xFFE2E0EC), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: on ? typeColor(t) : kMuted),
              const SizedBox(height: 6),
              Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? typeColor(t) : const Color(0xFF3B3753))),
            ]),
          ),
        ),
      );
    }

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SmallLabel('2 · Type'),
        const SizedBox(height: 10),
        Row(children: [
          card(kBarter, Icons.card_giftcard_outlined),
          const SizedBox(width: 8),
          card(kPaid, Icons.currency_rupee),
          const SizedBox(width: 8),
          card(kBoth, Icons.auto_awesome_outlined),
        ]),
      ]),
    );
  }

  Widget _productPanel(int n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF6C9D8), width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SmallLabel('$n · Barter product', color: kBarterC),
          const Spacer(),
          const Text('counts as earnings', style: TextStyle(fontSize: 12, color: kMuted)),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < _products.length; i++) ...[
          if (i > 0) const Divider(height: 28),
          _productDraft(_products[i], i),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _products.add(_ProductDraft())),
            icon: const Icon(Icons.add, color: kBarterC),
            label: const Text('Add another product', style: TextStyle(color: kBarterC, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _productDraft(_ProductDraft p, int index) {
    final pv = p.preview;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: p.link,
            keyboardType: TextInputType.url,
            decoration: deco('Paste product link', hint: 'Amazon, Nykaa, brand site…'),
            onSubmitted: (_) => _fetch(p),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBarterC, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: p.fetching ? null : () => _fetch(p),
            child: p.fetching
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Fetch'),
          ),
        ),
        if (_products.length > 1)
          IconButton(onPressed: () => setState(() => _products.removeAt(index)), icon: const Icon(Icons.close), tooltip: 'Remove'),
      ]),
      if (p.error != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kWarnTint, borderRadius: BorderRadius.circular(12)),
          child: Text('${p.error}\nFill it in yourself below — the link is still saved.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A3306))),
        ),
      ],
      if (pv != null && pv.images.isNotEmpty) ...[
        const SizedBox(height: 10),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: pv.images.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final u = pv.images[i];
              final on = p.pickedUrls.contains(u);
              return GestureDetector(
                onTap: () => setState(() => on ? p.pickedUrls.remove(u) : p.pickedUrls.add(u)),
                child: Container(
                  width: 84,
                  decoration: BoxDecoration(
                    border: Border.all(color: on ? kBarterC : kLine, width: on ? 3 : 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.network(u, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: kMuted)),
                  ),
                ),
              );
            },
          ),
        ),
        Text('${p.pickedUrls.length} photo(s) selected · tap to choose', style: const TextStyle(fontSize: 11, color: kMuted)),
      ],
      if (p.localPhotos.isNotEmpty) ...[
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: p.localPhotos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(p.localPhotos[i]), width: 72, height: 72, fit: BoxFit.cover),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: () => setState(() => p.localPhotos.removeAt(i)),
                  child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: kBarterC), foregroundColor: kBarterC),
            onPressed: () => _addPhoto(p, ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Gallery'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: kBarterC), foregroundColor: kBarterC),
            onPressed: () => _addPhoto(p, ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('Camera'),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      TextFormField(controller: p.name, textCapitalization: TextCapitalization.sentences, decoration: deco('Product name *')),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: TextFormField(
            controller: p.value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: deco('Product value (₹)', hint: 'MRP'),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: TextFormField(controller: p.qty, keyboardType: TextInputType.number, decoration: deco('Qty')),
        ),
      ]),
    ]);
  }

  Widget _barterEditPanel(int n) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SmallLabel('$n · Barter', color: kBarterC),
        const SizedBox(height: 10),
        if (_linkedProducts > 0)
          Text('$_linkedProducts product(s) linked. Barter value is their total — add or edit products on the collab page.',
              style: const TextStyle(color: kMuted, fontSize: 13))
        else
          moneyField(barterFallback, 'Barter value (₹)'),
      ]),
    );
  }

  Widget _paidPanel(int n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD6CEF7), width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SmallLabel('$n · Payment', color: kPrimary),
        const SizedBox(height: 10),
        TextFormField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          decoration: deco('Agreed amount (₹) *'),
        ),
        const SizedBox(height: 12),
        DateField(payDue, 'Payment due'),
        if (_isNew) moneyField(advance, 'Advance already received (₹)'),
      ]),
    );
  }

  Widget _postPanel(int n) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SmallLabel('$n · What you’ll post'),
        const SizedBox(height: 6),
        for (final k in _counts.keys)
          SizedBox(
            height: 48,
            child: Row(children: [
              Expanded(child: Text(k == 'YouTube video' ? 'YouTube video' : '${k}s', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              IconButton.outlined(
                onPressed: _counts[k]! > 0 ? () => setState(() => _counts[k] = _counts[k]! - 1) : null,
                icon: const Icon(Icons.remove, size: 18),
              ),
              SizedBox(width: 28, child: Text('${_counts[k]}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              IconButton.filledTonal(onPressed: () => setState(() => _counts[k] = _counts[k]! + 1), icon: const Icon(Icons.add, size: 18)),
            ]),
          ),
        const SizedBox(height: 8),
        DateField(postBy, 'Post by'),
      ]),
    );
  }

  Widget _stagePanel() {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SmallLabel('Stage'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...kStages,
            if (!_isNew) kCancelled,
          ]
              .map((s) => ChoiceChip(
                    label: Text(s),
                    selected: _stage == s,
                    showCheckmark: false,
                    selectedColor: s == kCancelled ? kDanger : kInk,
                    labelStyle: TextStyle(color: _stage == s ? Colors.white : const Color(0xFF3B3753), fontWeight: FontWeight.w600),
                    backgroundColor: kBg,
                    onSelected: (_) => setState(() => _stage = s),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        Text(kStageHint[_stage] ?? '', style: const TextStyle(fontSize: 12, color: kMuted)),
      ]),
    );
  }

  Widget _moreDetails() {
    final contacts = _contacts.where((c) => _brandId == null || c['brand_id'] == null || c['brand_id'] == _brandId).toList();
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: const Text('More details (optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: const Text('Contact, dates, rights, notes', style: TextStyle(fontSize: 12, color: kMuted)),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Pick(
            label: 'Contact',
            value: _contactId,
            allowEmpty: true,
            options: contacts.map((c) => str(c['id'])).toList(),
            labels: {for (final c in contacts) str(c['id']): str(c['name'])},
            onChanged: (v) => setState(() => _contactId = v),
          ),
          Pick(label: 'How it came', value: _source, options: kSources, allowEmpty: true, onChanged: (v) => setState(() => _source = v)),
          textField(campaign, 'Campaign'),
          DateField(start, 'Campaign start'),
          DateField(end, 'Campaign end'),
          if (!_isNew) DateField(postBy, 'Post by'),
          if (_showPaid) textField(terms, 'Payment terms', hint: 'e.g. 50% advance, rest 30 days after posting'),
          DateField(rights, 'Usage rights until'),
          DateField(exclusivity, 'Exclusivity until'),
          DateField(renewal, 'Follow up / renewal'),
          textField(links, 'Links (brief, drive…)', maxLines: 3, keyboard: TextInputType.multiline),
          textField(notes, 'Notes', maxLines: 4, keyboard: TextInputType.multiline),
        ],
      ),
    );
  }
}

class _BrandPicker extends StatefulWidget {
  final List<Rec> brands;
  const _BrandPicker({required this.brands});
  @override
  State<_BrandPicker> createState() => _BrandPickerState();
}

class _BrandPickerState extends State<_BrandPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final l = widget.brands.where((b) => str(b['name']).toLowerCase().contains(_q.toLowerCase())).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: deco('Search brands').copyWith(prefixIcon: const Icon(Icons.search)),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: kPrimaryTint, child: Icon(Icons.add, color: kPrimary)),
              title: Text(_q.isEmpty ? 'New brand' : 'New brand "$_q"', style: const TextStyle(fontWeight: FontWeight.w700, color: kPrimary)),
              onTap: () => Navigator.pop(context, '__new__:$_q'),
            ),
            Expanded(
              child: ListView(
                children: l
                    .map((b) => ListTile(
                          leading: CircleAvatar(
                              backgroundColor: kBg,
                              child: Text(str(b['name']).isEmpty ? '?' : str(b['name'])[0].toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.w800))),
                          title: Text(str(b['name'])),
                          onTap: () => Navigator.pop(context, str(b['id'])),
                        ))
                    .toList(),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
