import 'dart:convert';
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

/// One product being added from the New collab screen.
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

class _Addon {
  bool on = false;
  final amount = TextEditingController();
  final detail = TextEditingController();
}

/// New / edit collab. The form adapts to the collab kind picked from the + sheet.
class CollabFormScreen extends StatefulWidget {
  final String? collabId;
  final String? brandId;
  final String kind;
  const CollabFormScreen({super.key, this.collabId, this.brandId, this.kind = kPaid});
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

  late String _kind = widget.kind;
  String? _brandId;
  String? _contactId;
  String? _source;
  String _feeMode = kFeeTop;
  String _stage = 'Confirmed';
  String _refundWhen = 'After posting';
  bool _extraProduct = false;
  String? _orderProof;
  final List<_ProductDraft> _products = [_ProductDraft()];
  final Map<String, int> _counts = {'Reel': 1, 'Story': 0, 'Post': 0, 'YouTube video': 0, 'UGC video': 0};
  final Map<String, _Addon> _addons = {for (final a in kAddons) a: _Addon()};

  final title = TextEditingController(),
      fee = TextEditingController(),
      total = TextEditingController(),
      refundAmt = TextEditingController(),
      barterFallback = TextEditingController(),
      payDue = TextEditingController(),
      advance = TextEditingController(),
      postBy = TextEditingController(),
      agency = TextEditingController(),
      agencyPct = TextEditingController(),
      promo = TextEditingController(),
      commissionPct = TextEditingController(),
      eventDate = TextEditingController(),
      venue = TextEditingController(),
      orderNo = TextEditingController(),
      orderDate = TextEditingController(),
      orderSite = TextEditingController(),
      pocName = TextEditingController(),
      pocRole = TextEditingController(),
      pocPhone = TextEditingController(),
      pocEmail = TextEditingController(),
      pocInsta = TextEditingController(),
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
    for (final c in recent) {
      final b = str(c['brand_id']);
      if (seen.add(b)) {
        final m = _brands.where((x) => x['id'] == b);
        if (m.isNotEmpty) _recentBrands.add(m.first);
      }
      if (_recentBrands.length >= 3) break;
    }
    _brandId = widget.brandId;
    if (_isNew) {
      _applyKindDefaults();
    } else {
      final r = await Repo.byId('collabs', widget.collabId!) ?? {};
      _row = r;
      _brandId = str(r['brand_id']);
      _contactId = r['contact_id'] as String?;
      _source = r['source'] as String?;
      _kind = kDealTypes.contains(str(r['deal_type'])) ? str(r['deal_type']) : kPaid;
      _stage = kAllStages.contains(str(r['stage'])) ? str(r['stage']) : 'Confirmed';
      _feeMode = str(r['fee_mode']).isEmpty ? (_kind == kOrder ? kFeeNone : kFeeTop) : str(r['fee_mode']);
      _refundWhen = str(r['refund_when']).isEmpty ? 'After posting' : str(r['refund_when']);
      _orderProof = str(r['order_proof']).isEmpty ? null : str(r['order_proof']);
      title.text = str(r['title']);
      fee.text = numCtl(r['agreed_amount']).text;
      refundAmt.text = numCtl(r['refund_amount']).text;
      if (_feeMode == kFeeIncl) total.text = numCtl(toD(r['agreed_amount']) + toD(r['refund_amount'])).text;
      barterFallback.text = numCtl(r['barter_value']).text;
      payDue.text = str(r['payment_due_date']);
      postBy.text = str(r['publish_date']);
      agency.text = str(r['agency_name']);
      agencyPct.text = numCtl(r['agency_pct']).text;
      promo.text = str(r['promo_code']);
      commissionPct.text = numCtl(r['commission_pct']).text;
      eventDate.text = str(r['event_date']);
      venue.text = str(r['venue']);
      orderNo.text = str(r['order_no']);
      orderDate.text = str(r['order_date']);
      orderSite.text = str(r['order_site']);
      campaign.text = str(r['campaign']);
      start.text = str(r['start_date']);
      end.text = str(r['end_date']);
      terms.text = str(r['payment_terms']);
      rights.text = str(r['usage_rights_until']);
      exclusivity.text = str(r['exclusivity_until']);
      renewal.text = str(r['renewal_date']);
      links.text = str(r['links']);
      notes.text = str(r['notes']);
      try {
        for (final a in (jsonDecode(str(r['addons'])) as List)) {
          final m = Map<String, dynamic>.from(a as Map);
          final ad = _addons[str(m['name'])];
          if (ad != null) {
            ad.on = true;
            ad.amount.text = numCtl(m['amount']).text;
            ad.detail.text = str(m['detail']);
          }
        }
      } catch (_) {}
      if (_contactId != null) _fillContact(_contactId!);
      _linkedProducts = await Repo.count('products', where: 'collab_id = ?', args: [widget.collabId]);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applyKindDefaults() {
    _feeMode = _kind == kOrder ? kFeeNone : kFeeTop;
    _counts.updateAll((k, v) => 0);
    if (_kind == kUgc) {
      _counts['UGC video'] = 1;
    } else if (_kind == kGifting) {
      _counts['Story'] = 1;
    } else if (_kind != kEvent) {
      _counts['Reel'] = 1;
    }
  }

  void _fillContact(String id) {
    final m = _contacts.where((c) => c['id'] == id).toList();
    if (m.isEmpty) return;
    final c = m.first;
    pocName.text = str(c['name']);
    pocRole.text = str(c['role']);
    pocPhone.text = str(c['phone']);
    pocEmail.text = str(c['email']);
    pocInsta.text = str(c['instagram']);
  }

  // ---------- derived ----------
  bool get _showProduct => kindHasProduct(_kind) || _extraProduct;
  bool get _isOrder => _kind == kOrder;
  bool get _showFee => kindHasFee(_kind) || (_isOrder && _feeMode != kFeeNone) || _kind == kCommission;

  double get _productTotal =>
      _isNew ? _products.fold<double>(0, (a, p) => a + p.total) : (_isOrder ? toD(refundAmt.text) : toD(barterFallback.text));

  double get _feeValue {
    if (_isOrder && _feeMode == kFeeIncl) return (toD(total.text) - _productTotal).clamp(0, double.infinity).toDouble();
    if (_isOrder && _feeMode == kFeeNone) return 0;
    return toD(fee.text);
  }

  double get _addonTotal => _addons.values.where((a) => a.on).fold(0.0, (s, a) => s + toD(a.amount.text));
  double get _grossFee => _feeValue + _addonTotal;
  double get _agencyCut => _grossFee * toD(agencyPct.text) / 100;
  double get _earn => _grossFee - _agencyCut + _productTotal;

  String get _brandName {
    for (final b in _brands) {
      if (b['id'] == _brandId) return str(b['name']);
    }
    return '';
  }

  // ---------- brand ----------
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
      setState(() => _brandId = picked);
    }
  }

  Future<void> _pickContact() async {
    final list = [..._contacts]..sort((a, b) {
        final ab = a['brand_id'] == _brandId ? 0 : 1;
        final bb = b['brand_id'] == _brandId ? 0 : 1;
        return ab != bb ? ab - bb : str(a['name']).compareTo(str(b['name']));
      });
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(c).size.height * 0.6,
          child: ListView(children: [
            ListTile(
              leading: const CircleAvatar(backgroundColor: kPrimaryTint, child: Icon(Icons.person_add_alt, color: kPrimary)),
              title: const Text('New contact', style: TextStyle(fontWeight: FontWeight.w700, color: kPrimary)),
              onTap: () => Navigator.pop(c, '__new__'),
            ),
            for (final ct in list)
              ListTile(
                leading: CircleAvatar(backgroundColor: kBg, child: Text(_initials(str(ct['name'])), style: const TextStyle(fontWeight: FontWeight.w800))),
                title: Text(str(ct['name'])),
                subtitle: Text([str(ct['role']), str(ct['company'])].where((x) => x.isNotEmpty).join(' · ')),
                onTap: () => Navigator.pop(c, str(ct['id'])),
              ),
          ]),
        ),
      ),
    );
    if (id == null) return;
    setState(() {
      if (id == '__new__') {
        _contactId = null;
        for (final c in [pocName, pocRole, pocPhone, pocEmail, pocInsta]) {
          c.clear();
        }
      } else {
        _contactId = id;
        _fillContact(id);
      }
    });
  }

  // ---------- products ----------
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
        if (_isOrder && orderSite.text.isEmpty) orderSite.text = r.siteName ?? Uri.parse(url).host.replaceFirst('www.', '');
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
      toast(context, 'Image limit is $_maxImages per product (change in Profile › Lock & limits)');
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

  Future<void> _pickProof() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (f == null) return;
    final n = await Media.importFile(f.path);
    setState(() => _orderProof = n);
  }

  // ---------- save ----------
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_brandId == null || _brandId!.isEmpty) {
      toast(context, 'Choose a brand');
      return;
    }
    final drafts = _products.where((p) => !p.isBlank).toList();
    if (_isNew && _showProduct && kindHasProduct(_kind)) {
      if (drafts.isEmpty) {
        toast(context, 'Add the product (paste a link or type its name)');
        return;
      }
      if (drafts.any((p) => p.name.text.trim().isEmpty)) {
        toast(context, 'Each product needs a name');
        return;
      }
    }
    if (_isOrder && _feeMode == kFeeIncl && toD(total.text) < _productTotal) {
      toast(context, 'Total must be at least the product cost (${money(_productTotal)})');
      return;
    }
    if (kindHasFee(_kind) && _feeValue <= 0 && _kind != kEvent) {
      toast(context, 'Enter the fee');
      return;
    }
    setState(() => _saving = true);
    try {
      final contactId = await _saveContact();
      final firstName = drafts.isNotEmpty ? drafts.first.name.text.trim() : '';
      final autoTitle = firstName.isNotEmpty ? firstName : '$_brandName ${_kind == kUgc ? 'UGC' : 'collab'}';
      final productTotal = _productTotal;
      final addons = _addons.entries
          .where((e) => e.value.on)
          .map((e) => {'name': e.key, 'amount': toD(e.value.amount.text), 'detail': e.value.detail.text.trim()})
          .toList();
      final row = <String, dynamic>{
        'id': widget.collabId,
        'brand_id': _brandId,
        'contact_id': contactId,
        'title': title.text.trim().isEmpty ? autoTitle : title.text.trim(),
        'deal_type': _kind,
        'fee_mode': _isOrder ? _feeMode : kFeeTop,
        'agreed_amount': _feeValue,
        'refund_amount': _isOrder ? productTotal : null,
        'barter_value': (!_isOrder && _showProduct) ? productTotal : 0,
        'addons': addons.isEmpty ? null : jsonEncode(addons),
        'stage': _stage,
        'source': _source,
        'agency_name': sourceHasAgency(_source) ? nn(agency) : null,
        'agency_pct': sourceHasAgency(_source) ? toD(agencyPct.text) : 0,
        'promo_code': _kind == kCommission ? nn(promo) : null,
        'commission_pct': _kind == kCommission ? toD(commissionPct.text) : null,
        'event_date': _kind == kEvent ? nn(eventDate) : null,
        'venue': _kind == kEvent ? nn(venue) : null,
        'order_no': _isOrder ? nn(orderNo) : null,
        'order_date': _isOrder ? nn(orderDate) : null,
        'order_site': _isOrder ? nn(orderSite) : null,
        'order_proof': _isOrder ? _orderProof : null,
        'refund_when': _isOrder ? _refundWhen : null,
        'campaign': nn(campaign),
        'start_date': nn(start),
        'end_date': nn(end),
        'publish_date': nn(postBy),
        'payment_due_date': nn(payDue),
        'payment_terms': nn(terms),
        'usage_rights_until': nn(rights),
        'exclusivity_until': nn(exclusivity),
        'renewal_date': nn(renewal),
        'links': nn(links),
        'notes': nn(notes),
      };
      if (!_isNew && _linkedProducts > 0 && !_isOrder) row.remove('barter_value');
      final id = await Repo.save('collabs', row);
      if (_isNew) {
        await Repo.log(id, 'Collab created: $_kind${_source == null ? '' : ' via $_source'}');
        if (_showProduct && drafts.isNotEmpty) await _saveProducts(id, drafts);
        await _saveDeliverables(id);
        final adv = toD(advance.text);
        if (adv > 0) {
          await Repo.save('payments', {
            'collab_id': id, 'amount': adv, 'tds': 0, 'received_date': todayIso(), 'kind': 'Advance', 'notes': 'Advance'
          });
          await Repo.log(id, 'Advance received: ${money(adv)}');
        }
        if (_isOrder && str(orderDate.text).isNotEmpty) await Repo.log(id, 'Product ordered: ${money(productTotal)}');
      } else if (str(_row['stage']) != _stage) {
        await Repo.log(id, 'Stage: ${stageLabel(str(_row['stage']))} → ${stageLabel(_stage)}');
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

  Future<String?> _saveContact() async {
    final name = pocName.text.trim();
    if (name.isEmpty) return _contactId;
    return Repo.save('contacts', {
      'id': _contactId,
      'brand_id': _brandId,
      'name': name,
      'role': nn(pocRole),
      'phone': nn(pocPhone),
      'email': nn(pocEmail),
      'instagram': nn(pocInsta)?.replaceFirst('@', ''),
      'company': sourceHasAgency(_source) && agency.text.trim().isNotEmpty ? agency.text.trim() : _brandName,
    });
  }

  Future<void> _saveProducts(String collabId, List<_ProductDraft> drafts) async {
    var failed = 0;
    for (final p in drafts) {
      final pid = await Repo.save('products', {
        'brand_id': _brandId,
        'collab_id': collabId,
        'name': p.name.text.trim().isEmpty ? 'Product' : p.name.text.trim(),
        'description': p.preview?.description,
        'category': p.preview?.category,
        'purchase_price': toD(p.value.text),
        'quantity': toI(p.qty.text) <= 0 ? 1 : toI(p.qty.text),
        'notes': _isOrder ? 'Bought by me · refund from brand' : null,
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
    }
    if (failed > 0 && mounted) toast(context, '$failed photo(s) could not be downloaded');
  }

  Future<void> _saveDeliverables(String collabId) async {
    for (final e in _counts.entries) {
      for (var i = 1; i <= e.value; i++) {
        final ugc = e.key == 'UGC video';
        await Repo.save('deliverables', {
          'collab_id': collabId,
          'type': e.key,
          'platform': ugc ? 'Brand (UGC)' : (e.key == 'YouTube video' ? 'YouTube' : 'Instagram'),
          'title': e.value > 1 ? '$i' : null,
          'due_date': nn(postBy),
          'status': 'Planned',
          'revision_count': 0,
        });
      }
    }
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text(_isNew ? 'New collab' : 'Edit collab', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ActionChip(
              avatar: Text(kKindIcon[_kind] ?? '', style: TextStyle(color: typeColor(_kind), fontWeight: FontWeight.w800)),
              label: Text(_kind, style: TextStyle(color: typeColor(_kind), fontWeight: FontWeight.w700)),
              backgroundColor: typeTint(_kind),
              onPressed: _changeKind,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _loading ? null : _footer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              onChanged: () => setState(() {}),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                _brandPanel(),
                _contactPanel(),
                if (_showProduct) (_isNew ? _productPanel() : _productEditPanel()),
                if (_isOrder) _orderPanel(),
                _feePanel(),
                if (_kind == kEvent) _eventPanel(),
                _summary(),
                if (_isNew) _postPanel(),
                _addonsPanel(),
                _stagePanel(),
                _moreDetails(),
              ]),
            ),
    );
  }

  Future<void> _changeKind() async {
    final k = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final k in kDealTypes)
            ListTile(
              leading: CircleAvatar(backgroundColor: typeTint(k), child: Text(kKindIcon[k]!, style: TextStyle(color: typeColor(k), fontWeight: FontWeight.w800))),
              title: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(kKindHint[k]!),
              trailing: k == _kind ? const Icon(Icons.check, color: kPrimary) : null,
              onTap: () => Navigator.pop(c, k),
            ),
        ]),
      ),
    );
    if (k == null || k == _kind) return;
    setState(() {
      _kind = k;
      if (_isNew) _applyKindDefaults();
      if (k == kOrder && _feeMode == kFeeTop && toD(fee.text) <= 0) _feeMode = kFeeNone;
    });
  }

  Widget _footer() => SafeArea(
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
                Text(_agencyCut > 0 ? 'You earn (after agency)' : 'You earn', style: const TextStyle(fontSize: 11, color: kMuted)),
                FittedBox(fit: BoxFit.scaleDown, child: Text(money(_earn), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
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
      );

  Widget _brandPanel() {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SmallLabel('Brand & where it came from'),
        const SizedBox(height: 10),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
              side: BorderSide(color: _brandId == null ? const Color(0xFFD7D4E3) : kPrimary, width: 1.5),
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
                  child: Text(_brandName.isEmpty ? 'Choose brand *' : _brandName,
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
                onPressed: () => setState(() => _brandId = str(b['id'])),
              )),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16, color: kPrimaryDark),
            label: const Text('New brand'),
            backgroundColor: kPrimaryTint,
            onPressed: () => _newBrand(),
          ),
        ]),
        const SizedBox(height: 14),
        const Text('Source', style: TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: kSources.map((s) {
            final on = _source == s;
            return ChoiceChip(
              label: Text(s, style: TextStyle(color: on ? Colors.white : kInk, fontWeight: FontWeight.w600)),
              selected: on,
              showCheckmark: false,
              selectedColor: kInk,
              onSelected: (_) => setState(() => _source = on ? null : s),
            );
          }).toList(),
        ),
        if (sourceHasAgency(_source)) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 3, child: TextFormField(controller: agency, decoration: deco('$_source name'))),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: agencyPct,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: deco('Their cut %'),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        TextFormField(controller: title, decoration: deco('Collab name (optional)', hint: 'Auto: product / brand name')),
      ]),
    );
  }

  Widget _contactPanel() {
    final hasPerson = pocName.text.trim().isNotEmpty;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: SmallLabel('Point of contact')),
          TextButton.icon(
              onPressed: _pickContact, icon: const Icon(Icons.contacts_outlined, size: 18), label: const Text('Pick saved')),
        ]),
        if (hasPerson)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              CircleAvatar(
                  backgroundColor: kPrimaryTint,
                  child: Text(_initials(pocName.text), style: const TextStyle(color: kPrimaryDark, fontWeight: FontWeight.w800))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  [pocName.text.trim(), pocRole.text.trim()].where((x) => x.isNotEmpty).join(' · '),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (_contactId != null) const Pill('Saved', kMintDark),
            ]),
          ),
        Row(children: [
          Expanded(child: TextFormField(controller: pocName, textCapitalization: TextCapitalization.words, decoration: deco('Name'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: pocRole, textCapitalization: TextCapitalization.words, decoration: deco('Role', hint: 'Brand manager'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: pocPhone, keyboardType: TextInputType.phone, decoration: deco('Phone / WhatsApp'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: pocInsta, decoration: deco('Instagram', hint: '@handle'))),
        ]),
        const SizedBox(height: 10),
        TextFormField(
          controller: pocEmail,
          keyboardType: TextInputType.emailAddress,
          decoration: deco('Email'),
          validator: (v) => (v ?? '').trim().isEmpty || isValidEmail(v!) ? null : 'Enter a valid email',
        ),
      ]),
    );
  }

  Widget _productPanel() {
    final c = _isOrder ? kAmberDark : kBarterDark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _isOrder ? const Color(0xFFF3C9A6) : const Color(0xFFF6C9D8), width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: SmallLabel(_isOrder ? 'Product you order' : 'Product', color: c)),
          if (!kindHasProduct(_kind))
            IconButton(onPressed: () => setState(() => _extraProduct = false), icon: const Icon(Icons.close), tooltip: 'Remove product'),
        ]),
        Text(_isOrder ? 'Price you pay is refunded by the brand.' : 'Product value counts as your earning.',
            style: const TextStyle(fontSize: 12, color: kMuted)),
        const SizedBox(height: 10),
        for (var i = 0; i < _products.length; i++) ...[
          if (i > 0) const Divider(height: 28),
          _productDraft(_products[i], i, c),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _products.add(_ProductDraft())),
            icon: Icon(Icons.add, color: c),
            label: Text('Add another product', style: TextStyle(color: c, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _productDraft(_ProductDraft p, int index, Color c) {
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
            style: FilledButton.styleFrom(backgroundColor: c, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
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
          decoration: BoxDecoration(color: kAmberTint, borderRadius: BorderRadius.circular(12)),
          child: Text('${p.error}\nAdd it manually below — the link is still saved.', style: const TextStyle(fontSize: 12, color: kAmberDark)),
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
                  decoration: BoxDecoration(border: Border.all(color: on ? c : kLine, width: on ? 3 : 1), borderRadius: BorderRadius.circular(12)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.network(u, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: kMuted)),
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
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(p.localPhotos[i]), width: 72, height: 72, fit: BoxFit.cover)),
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
            style: OutlinedButton.styleFrom(side: BorderSide(color: c), foregroundColor: c),
            onPressed: () => _addPhoto(p, ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Gallery'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: BorderSide(color: c), foregroundColor: c),
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
            decoration: deco(_isOrder ? 'Price you pay (₹)' : 'Product value (₹)', hint: 'MRP'),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 90, child: TextFormField(controller: p.qty, keyboardType: TextInputType.number, decoration: deco('Qty'))),
      ]),
    ]);
  }

  Widget _productEditPanel() {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SmallLabel(_isOrder ? 'Product you ordered' : 'Product', color: _isOrder ? kAmberDark : kBarterDark),
        const SizedBox(height: 10),
        if (_isOrder)
          moneyField(refundAmt, 'Product cost to be refunded (₹)')
        else if (_linkedProducts > 0)
          Text('$_linkedProducts product(s) linked — value comes from them. Add or edit products on the collab page.',
              style: const TextStyle(color: kMuted, fontSize: 13))
        else
          moneyField(barterFallback, 'Product value (₹)'),
      ]),
    );
  }

  Widget _orderPanel() {
    return Panel(
      color: kAmberTint,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SmallLabel('Your order', color: kAmberDark),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: orderSite, decoration: deco('Ordered on', hint: 'Amazon'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: orderNo, decoration: deco('Order #'))),
        ]),
        const SizedBox(height: 10),
        DateField(orderDate, 'Order date'),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: kAmberDark), foregroundColor: kAmberDark, backgroundColor: Colors.white),
              onPressed: _pickProof,
              icon: Icon(_orderProof == null ? Icons.receipt_long_outlined : Icons.check_circle, size: 18),
              label: Text(_orderProof == null ? 'Add order screenshot' : 'Screenshot added'),
            ),
          ),
          if (_orderProof != null)
            IconButton(onPressed: () => setState(() => _orderProof = null), icon: const Icon(Icons.close, color: kAmberDark), tooltip: 'Remove'),
        ]),
        const SizedBox(height: 10),
        Pick(
          label: 'Refund comes',
          value: _refundWhen,
          options: const ['After posting', 'After order proof', 'With the fee', 'Before posting'],
          onChanged: (v) => setState(() => _refundWhen = v ?? _refundWhen),
        ),
      ]),
    );
  }

  Widget _feePanel() {
    final showFeeChoice = _isOrder;
    if (!_showFee && !showFeeChoice && !(_kind == kBarter || _kind == kGifting)) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD6CEF7), width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SmallLabel(_kind == kCommission ? 'Commission' : 'Cash fee', color: kPrimaryDark),
        const SizedBox(height: 10),
        if (showFeeChoice) ...[
          Segmented(
            options: const [kFeeNone, kFeeTop, kFeeIncl],
            labels: const {kFeeNone: 'No fee', kFeeTop: 'Fee on top', kFeeIncl: 'Total incl. product'},
            value: _feeMode,
            onChanged: (v) => setState(() => _feeMode = v),
          ),
          const SizedBox(height: 12),
        ],
        if (_kind == kBarter || _kind == kGifting) ...[
          const Text('No cash fee for barter. Getting paid too? Switch type to Paid + Barter.', style: TextStyle(color: kMuted, fontSize: 13)),
        ] else if (_kind == kCommission) ...[
          Row(children: [
            Expanded(child: TextFormField(controller: promo, decoration: deco('Promo code / link'))),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                  controller: commissionPct, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco('Commission %')),
            ),
          ]),
          const SizedBox(height: 10),
          TextFormField(
              controller: fee, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: deco('Fixed fee too? (₹, optional)')),
          const SizedBox(height: 6),
          const Text('Log monthly commission payouts as payments on the collab.', style: TextStyle(fontSize: 12, color: kMuted)),
        ] else if (_isOrder && _feeMode == kFeeNone) ...[
          const Text('Only the product cost is refunded.', style: TextStyle(color: kMuted, fontSize: 13)),
        ] else if (_isOrder && _feeMode == kFeeIncl) ...[
          TextFormField(
            controller: total,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            decoration: deco('Brand pays in total (₹)'),
          ),
          const SizedBox(height: 6),
          Text('= product ${money(_productTotal)} + your fee ${money(_feeValue)}', style: const TextStyle(fontSize: 12, color: kMuted)),
        ] else ...[
          TextFormField(
            controller: fee,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            decoration: deco(_kind == kEvent ? 'Appearance fee (₹)' : 'Fee (₹)'),
          ),
        ],
        if (_showFee || _isOrder) ...[
          const SizedBox(height: 12),
          DateField(payDue, _isOrder ? 'Payment / refund due' : 'Payment due'),
          if (_isNew && _showFee) moneyField(advance, 'Advance already received (₹)'),
        ],
        if (!kindHasProduct(_kind) && !_extraProduct && _isNew)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _extraProduct = true),
              icon: const Icon(Icons.add, color: kBarterDark),
              label: const Text('Brand also sends a product', style: TextStyle(color: kBarterDark, fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
    );
  }

  Widget _eventPanel() => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SmallLabel('Event'),
          const SizedBox(height: 10),
          DateField(eventDate, 'Event date'),
          textField(venue, 'Venue / city'),
        ]),
      );

  Widget _summary() {
    final rows = <(String, String, Color, bool)>[];
    if (_isOrder && _productTotal > 0) rows.add(('You pay for product (refund due)', '− ${money(_productTotal)}', const Color(0xFFFFC9A3), false));
    if (_grossFee > 0) rows.add(('Fee${_addonTotal > 0 ? ' + add-ons' : ''}', money(_grossFee), const Color(0xFFC9BFFF), false));
    if (_agencyCut > 0) rows.add(('${agency.text.trim().isEmpty ? 'Agency' : agency.text.trim()} cut ${toD(agencyPct.text).toStringAsFixed(0)}%', '− ${money(_agencyCut)}', const Color(0xFFFFC9A3), false));
    if (_showProduct && _productTotal > 0) rows.add((_isOrder ? 'Product you keep' : 'Product value', money(_productTotal), const Color(0xFFFF9EC0), false));
    final cash = (_isOrder ? _productTotal : 0) + _grossFee - _agencyCut;
    if (cash > 0) rows.add(('Brand pays you in cash', money(cash), Colors.white, true));
    rows.add(('Your earning', money(_earn), const Color(0xFF9CF2C6), true));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('DEAL SUMMARY', style: TextStyle(color: Color(0xFFC9C5DC), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        const SizedBox(height: 8),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(r.$1, style: TextStyle(color: r.$3, fontSize: 13, fontWeight: r.$4 ? FontWeight.w800 : FontWeight.w500))),
              Text(r.$2, style: TextStyle(color: r.$3, fontSize: 13, fontWeight: r.$4 ? FontWeight.w800 : FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }

  Widget _postPanel() {
    final keys = _kind == kUgc
        ? ['UGC video', 'Reel', 'Story', 'Post', 'YouTube video']
        : ['Reel', 'Story', 'Post', 'YouTube video', 'UGC video'];
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SmallLabel(_kind == kUgc ? 'What you’ll deliver' : 'What you’ll post'),
        const SizedBox(height: 6),
        for (final k in keys)
          SizedBox(
            height: 50,
            child: Row(children: [
              Expanded(child: Text(k == 'Story' ? 'Stories' : (k.endsWith('video') ? '${k}s' : '${k}s'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              IconButton.outlined(
                onPressed: _counts[k]! > 0 ? () => setState(() => _counts[k] = _counts[k]! - 1) : null,
                icon: const Icon(Icons.remove, size: 18),
              ),
              SizedBox(width: 30, child: Text('${_counts[k]}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              IconButton.filledTonal(onPressed: () => setState(() => _counts[k] = _counts[k]! + 1), icon: const Icon(Icons.add, size: 18)),
            ]),
          ),
        const SizedBox(height: 8),
        DateField(postBy, _kind == kUgc ? 'Deliver by' : 'Post by'),
      ]),
    );
  }

  Widget _addonsPanel() {
    if (_kind == kBarter || _kind == kGifting) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: _addons.values.any((a) => a.on) || _kind == kUgc,
        title: const Text('Add-ons (rights, ads, raw files)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(_addonTotal > 0 ? '+ ${money(_addonTotal)}' : 'Priced separately · optional', style: const TextStyle(fontSize: 12, color: kMuted)),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final e in _addons.entries) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: e.value.on,
              title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
              onChanged: (v) => setState(() => e.value.on = v ?? false),
            ),
            if (e.value.on)
              Padding(
                padding: const EdgeInsets.only(left: 44, bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: TextFormField(
                        controller: e.value.amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: deco('₹', hint: '0')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: TextFormField(controller: e.value.detail, decoration: deco('Details', hint: '30 days, organic'))),
                ]),
              ),
          ],
        ],
      ),
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
          children: [...kStages, if (!_isNew) kCancelled].map((s) {
            final on = _stage == s;
            return ChoiceChip(
              label: Text(stageLabel(s), style: TextStyle(color: on ? Colors.white : kInk, fontWeight: FontWeight.w600)),
              selected: on,
              showCheckmark: false,
              selectedColor: s == kCancelled ? kDanger : kInk,
              onSelected: (_) => setState(() => _stage = s),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text(kStageHint[_stage] ?? '', style: const TextStyle(fontSize: 12, color: kMuted)),
      ]),
    );
  }

  Widget _moreDetails() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: const Text('More details (optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: const Text('Campaign, dates, rights, notes', style: TextStyle(fontSize: 12, color: kMuted)),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          textField(campaign, 'Campaign'),
          DateField(start, 'Campaign start'),
          DateField(end, 'Campaign end'),
          if (!_isNew) DateField(postBy, _kind == kUgc ? 'Deliver by' : 'Post by'),
          textField(terms, 'Payment terms', hint: 'e.g. 50% advance, rest 30 days after posting'),
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

String _initials(String n) {
  final parts = n.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).toList();
  return parts.isEmpty ? '?' : parts.map((w) => w[0].toUpperCase()).join();
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
