import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';
import '../core/format.dart';
import '../core/link_preview.dart';
import '../core/media.dart';
import '../core/repo.dart';
import 'widgets.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> with AutoReload {
  List<Rec>? _rows;
  Map<String, String> _brands = {};
  Map<String, String> _linkText = {};
  Map<String, String> _firstImage = {};
  String _q = '';
  String? _category;

  @override
  Future<void> reload() async {
    final rows = await Repo.all('products', orderBy: 'name COLLATE NOCASE');
    final brands = await Repo.all('brands');
    final links = await Repo.all('product_links');
    final imgs = await Repo.all('product_images', orderBy: 'sort');
    final lt = <String, String>{};
    for (final l in links) {
      final k = str(l['product_id']);
      lt[k] = '${lt[k] ?? ''} ${str(l['url'])} ${str(l['title'])}';
    }
    final fi = <String, String>{};
    for (final i in imgs) {
      fi.putIfAbsent(str(i['product_id']), () => str(i['file_name']));
    }
    if (mounted) {
      setState(() {
        _rows = rows;
        _brands = {for (final b in brands) str(b['id']): str(b['name'])};
        _linkText = lt;
        _firstImage = fi;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows ?? [];
    final cats = rows.map((p) => str(p['category'])).where((c) => c.isNotEmpty).toSet().toList()..sort();
    final q = _q.toLowerCase();
    final list = rows.where((p) {
      if (_category != null && p['category'] != _category) return false;
      if (q.isEmpty) return true;
      return [p['name'], p['description'], p['category'], p['notes'], _brands[str(p['brand_id'])], _linkText[str(p['id'])]]
          .map(str)
          .join(' ')
          .toLowerCase()
          .contains(q);
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => push(context, const ProductFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Product'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: deco('Search name, brand, link…').copyWith(prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        if (cats.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(label: const Text('All'), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
              ),
              ...cats.map((c) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(label: Text(c), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
                  )),
            ]),
          ),
        Expanded(
          child: _rows == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const EmptyState(icon: Icons.inventory_2_outlined, text: 'No products.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final p = list[i];
                        final img = _firstImage[str(p['id'])];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: SizedBox(width: 48, height: 48, child: img == null ? const Icon(Icons.image_outlined) : MediaImage(img, radius: 8)),
                            title: Text(str(p['name'])),
                            subtitle: Text([_brands[str(p['brand_id'])] ?? '', str(p['category'])].where((x) => x.isNotEmpty).join(' · ')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => push(context, ProductDetailScreen(productId: str(p['id']))),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

/// Shows a stored image, with a clear placeholder when the file is missing.
class MediaImage extends StatelessWidget {
  final String fileName;
  final double radius;
  final BoxFit fit;
  const MediaImage(this.fileName, {super.key, this.radius = 10, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: Media.file(fileName),
      builder: (_, snap) {
        final f = snap.data;
        if (f == null) return const SizedBox.shrink();
        if (!f.existsSync()) {
          return Container(
            decoration: BoxDecoration(color: const Color(0xFFEEF0F3), borderRadius: BorderRadius.circular(radius)),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(4),
            child: const Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.broken_image_outlined, color: kMuted),
              Text('Image missing', style: TextStyle(fontSize: 10, color: kMuted), textAlign: TextAlign.center),
            ]),
          );
        }
        return ClipRRect(borderRadius: BorderRadius.circular(radius), child: Image.file(f, fit: fit));
      },
    );
  }
}

class ProductFormScreen extends StatefulWidget {
  final String? productId;
  final String? brandId;
  final String? collabId;
  const ProductFormScreen({super.key, this.productId, this.brandId, this.collabId});
  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  List<Rec> _brands = [];
  List<Rec> _collabs = [];
  String? _brandId;
  String? _collabId;
  final name = TextEditingController(),
      description = TextEditingController(),
      category = TextEditingController(),
      price = TextEditingController(),
      qty = TextEditingController(text: '1'),
      notes = TextEditingController(),
      fetchUrl = TextEditingController();
  LinkPreview? _preview;
  final Set<String> _pickedImages = {};
  bool _fetching = false;
  bool _saving = false;
  String? _newBrandName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _fetch() async {
    final url = fetchUrl.text.trim();
    if (!isValidUrl(url)) {
      toast(context, 'Paste a full product link starting with https://');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _fetching = true);
    try {
      final p = await LinkPreview.fetch(url);
      if (!mounted) return;
      final maxImages = await Repo.settingInt('max_images', 5);
      setState(() {
        _preview = p;
        _pickedImages
          ..clear()
          ..addAll(p.images.take(maxImages.clamp(1, 3).toInt()));
        if (p.title != null) name.text = p.title!;
        if (p.description != null && description.text.trim().isEmpty) description.text = p.description!;
        if (p.category != null && category.text.trim().isEmpty) category.text = p.category!;
        if (p.price != null && price.text.trim().isEmpty) {
          price.text = p.price! % 1 == 0 ? p.price!.toInt().toString() : p.price!.toStringAsFixed(2);
        }
        _newBrandName = null;
        final b = (p.brand ?? '').trim();
        if (b.isNotEmpty && _brandId == null) {
          final match = _brands.where((x) => str(x['name']).toLowerCase() == b.toLowerCase()).toList();
          if (match.isNotEmpty) {
            _brandId = str(match.first['id']);
          } else {
            _newBrandName = b;
          }
        }
      });
      toast(context, 'Details filled from ${p.siteName ?? Uri.parse(url).host}. Review before saving.');
    } catch (e) {
      if (mounted) toast(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _attachFetched(String productId) async {
    final p = _preview;
    final url = fetchUrl.text.trim();
    if (p == null && !isValidUrl(url)) return;
    final maxImages = await Repo.settingInt('max_images', 5);
    final maxLinks = await Repo.settingInt('max_links', 5);
    var imgCount = await Repo.count('product_images', where: 'product_id = ?', args: [productId]);
    var failed = 0;
    for (final u in (p?.images ?? <String>[]).where(_pickedImages.contains)) {
      if (imgCount >= maxImages) break;
      final file = await LinkPreview.downloadImage(u);
      if (file == null) {
        failed++;
        continue;
      }
      await Repo.save('product_images', {'product_id': productId, 'file_name': file, 'sort': imgCount++});
    }
    if (isValidUrl(url)) {
      final exists = await Repo.count('product_links', where: 'product_id = ? AND url = ?', args: [productId, url]);
      final links = await Repo.count('product_links', where: 'product_id = ?', args: [productId]);
      if (exists == 0 && links < maxLinks) {
        await Repo.save('product_links', {
          'product_id': productId,
          'url': url,
          'title': p?.siteName ?? Uri.parse(url).host.replaceFirst('www.', ''),
          'link_type': 'Shopping',
          'sort': links,
        });
      }
    }
    if (failed > 0 && mounted) toast(context, '$failed image(s) could not be downloaded');
  }

  Future<void> _load() async {
    _brands = await Repo.all('brands', orderBy: 'name COLLATE NOCASE');
    _collabs = await Repo.all('collabs', orderBy: 'updated_at DESC');
    _brandId = widget.brandId;
    _collabId = widget.collabId;
    if (widget.productId != null) {
      final p = await Repo.byId('products', widget.productId!) ?? {};
      name.text = str(p['name']);
      description.text = str(p['description']);
      category.text = str(p['category']);
      price.text = numCtl(p['purchase_price']).text;
      qty.text = str(p['quantity']);
      notes.text = str(p['notes']);
      _brandId = p['brand_id'] as String?;
      _collabId = p['collab_id'] as String?;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_saving) return;
    setState(() => _saving = true);
    final isNew = widget.productId == null;
    if (_brandId == null && _newBrandName != null) {
      _brandId = await Repo.save('brands', {'name': _newBrandName});
    }
    final id = await Repo.save('products', {
      'id': widget.productId,
      'brand_id': _brandId,
      'collab_id': _collabId,
      'name': name.text.trim(),
      'description': nn(description),
      'category': nn(category),
      'purchase_price': toD(price.text),
      'quantity': qty.text.trim().isEmpty ? 1 : toI(qty.text),
      'notes': nn(notes),
    });
    await _attachFetched(id);
    if (!mounted) return;
    setState(() => _saving = false);
    final nav = Navigator.of(context);
    nav.pop(id);
    if (isNew) nav.push(MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final collabsForBrand = _collabs.where((c) => _brandId == null || c['brand_id'] == _brandId).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.productId == null ? 'New product' : 'Edit product'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _fetchCard(),
                textField(name, 'Product name', req: true),
                if (_newBrandName != null && _brandId == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InputChip(
                      avatar: const Icon(Icons.add_business_outlined, size: 18),
                      label: Text('New brand "$_newBrandName" will be created'),
                      onDeleted: () => setState(() => _newBrandName = null),
                    ),
                  ),
                Pick(
                  label: 'Brand',
                  value: _brandId,
                  allowEmpty: true,
                  options: _brands.map((b) => str(b['id'])).toList(),
                  labels: {for (final b in _brands) str(b['id']): str(b['name'])},
                  onChanged: (v) => setState(() {
                    _brandId = v;
                    _collabId = null;
                  }),
                ),
                Pick(
                  label: 'Linked collab',
                  value: _collabId,
                  allowEmpty: true,
                  options: collabsForBrand.map((c) => str(c['id'])).toList(),
                  labels: {for (final c in collabsForBrand) str(c['id']): str(c['title'])},
                  onChanged: (v) => setState(() => _collabId = v),
                ),
                textField(category, 'Category', hint: 'Skincare, tech, apparel…'),
                textField(description, 'Description', maxLines: 3, keyboard: TextInputType.multiline),
                moneyField(price, 'Purchase price (₹)'),
                intField(qty, 'Quantity'),
                textField(notes, 'Notes', maxLines: 3, keyboard: TextInputType.multiline),
              ]),
            ),
    );
  }

  Widget _fetchCard() {
    final p = _preview;
    return SectionCard(
      title: 'Auto-fill from product link',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: fetchUrl,
              keyboardType: TextInputType.url,
              decoration: deco('Paste Amazon, Flipkart, Nykaa, brand site… link'),
              onSubmitted: (_) => _fetch(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _fetching ? null : _fetch,
              child: _fetching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Fetch'),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
            p == null
                ? 'Needs internet just for this step. Fills name, description, brand, price and images; the link is saved to the product.'
                : 'Tap images to choose which to save (${_pickedImages.length} selected).',
            style: const TextStyle(fontSize: 12, color: kMuted)),
        if (p != null && p.images.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: p.images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final u = p.images[i];
                final on = _pickedImages.contains(u);
                return InkWell(
                  onTap: () => setState(() => on ? _pickedImages.remove(u) : _pickedImages.add(u)),
                  child: Stack(children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        border: Border.all(color: on ? kPrimary : const Color(0xFFE3E5EA), width: on ? 3 : 1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          u,
                          fit: BoxFit.cover,
                          headers: const {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36'},
                          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: kMuted)),
                        ),
                      ),
                    ),
                    if (on)
                      const Positioned(
                        right: 4,
                        top: 4,
                        child: CircleAvatar(radius: 10, backgroundColor: kPrimary, child: Icon(Icons.check, size: 14, color: Colors.white)),
                      ),
                  ]),
                );
              },
            ),
          ),
        ],
      ]),
    );
  }
}

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> with AutoReload {
  Rec? _p;
  String _brand = '';
  String _collab = '';
  List<Rec> _images = [];
  List<Rec> _links = [];
  int _maxImages = 5;
  int _maxLinks = 5;
  bool _gone = false;
  bool _busy = false;

  @override
  Future<void> reload() async {
    final p = await Repo.byId('products', widget.productId);
    if (p == null) {
      if (mounted) setState(() => _gone = true);
      return;
    }
    final b = str(p['brand_id']).isEmpty ? null : await Repo.byId('brands', str(p['brand_id']));
    final c = str(p['collab_id']).isEmpty ? null : await Repo.byId('collabs', str(p['collab_id']));
    final imgs = await Repo.all('product_images', where: 'product_id = ?', args: [widget.productId], orderBy: 'sort, created_at');
    final links = await Repo.all('product_links', where: 'product_id = ?', args: [widget.productId], orderBy: 'sort, created_at');
    final mi = await Repo.settingInt('max_images', 5);
    final ml = await Repo.settingInt('max_links', 5);
    if (!mounted) return;
    setState(() {
      _p = p;
      _brand = str(b?['name']);
      _collab = str(c?['title']);
      _images = imgs;
      _links = links;
      _maxImages = mi;
      _maxLinks = ml;
    });
  }

  Future<void> _addImages(ImageSource source) async {
    final room = _maxImages - _images.length;
    if (room <= 0) {
      toast(context, 'Image limit reached ($_maxImages). Increase it in Settings.');
      return;
    }
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      List<XFile> files;
      if (source == ImageSource.camera) {
        final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2000);
        files = f == null ? [] : [f];
      } else {
        files = await picker.pickMultiImage(imageQuality: 85, maxWidth: 2000);
      }
      if (files.isEmpty) return;
      var skipped = 0;
      if (files.length > room) {
        skipped = files.length - room;
        files = files.take(room).toList();
      }
      var sort = _images.length;
      for (final f in files) {
        final name = await Media.importFile(f.path);
        await Repo.save('product_images', {'product_id': widget.productId, 'file_name': name, 'sort': sort++});
      }
      if (skipped > 0 && mounted) toast(context, '$skipped image(s) skipped: limit is $_maxImages per product.');
    } catch (e) {
      if (mounted) toast(context, 'Could not add image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _imageActions(Rec img) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.fullscreen), title: const Text('View'), onTap: () => Navigator.pop(c, 'view')),
          ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('Replace'), onTap: () => Navigator.pop(c, 'replace')),
          ListTile(
              leading: const Icon(Icons.delete_outline, color: kDanger),
              title: const Text('Remove', style: TextStyle(color: kDanger)),
              onTap: () => Navigator.pop(c, 'remove')),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    final name = str(img['file_name']);
    if (action == 'view') {
      push(context, _ImageViewer(fileName: name));
    } else if (action == 'remove') {
      if (!await confirm(context, 'Remove image?', 'The image file will be deleted from this phone.')) return;
      await Repo.delete('product_images', str(img['id']));
      await Media.remove(name);
    } else if (action == 'replace') {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
      if (f == null) return;
      final newName = await Media.importFile(f.path);
      await Repo.save('product_images', {'id': img['id'], 'file_name': newName});
      await Media.remove(name);
    }
  }

  Future<void> _linkDialog({Rec? existing}) async {
    if (existing == null && _links.length >= _maxLinks) {
      toast(context, 'Link limit reached ($_maxLinks). Increase it in Settings.');
      return;
    }
    final form = GlobalKey<FormState>();
    final url = ctl(existing?['url']);
    final title = ctl(existing?['title']);
    String? type = existing?['link_type'] as String?;
    final res = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(existing == null ? 'Add link' : 'Edit link'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                urlField(url, 'URL', req: true),
                textField(title, 'Display title (optional)'),
                Pick(label: 'Link type', value: type, options: kLinkTypes, allowEmpty: true, onChanged: (v) => set(() => type = v)),
              ]),
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(onPressed: () => Navigator.pop(d, 'delete'), child: const Text('Delete', style: TextStyle(color: kDanger))),
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  if (form.currentState!.validate()) Navigator.pop(d, 'save');
                },
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (res == 'delete' && existing != null) {
      if (!mounted) return;
      if (await confirm(context, 'Delete link?', url.text)) await Repo.delete('product_links', str(existing['id']));
    } else if (res == 'save') {
      await Repo.save('product_links', {
        'id': existing?['id'],
        'product_id': widget.productId,
        'url': url.text.trim(),
        'title': nn(title),
        'link_type': type,
        if (existing == null) 'sort': _links.length,
      });
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete product?', 'Its ${_images.length} images and ${_links.length} links will be deleted too.')) return;
    final names = _images.map((i) => str(i['file_name'])).toList();
    await Repo.delete('products', widget.productId);
    for (final n in names) {
      await Media.remove(n);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.delete_outline, text: 'Product deleted.'));
    final p = _p;
    if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final imgFull = _images.length >= _maxImages;
    final linkFull = _links.length >= _maxLinks;
    return Scaffold(
      appBar: AppBar(title: Text(str(p['name'])), actions: [
        IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => push(context, ProductFormScreen(productId: widget.productId))),
        IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        SectionCard(
          title: 'Images',
          trailing: Text('${_images.length} / $_maxImages', style: TextStyle(color: imgFull ? kDanger : kMuted, fontSize: 12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                ..._images.map((img) => InkWell(
                      onTap: () => _imageActions(img),
                      child: MediaImage(str(img['file_name'])),
                    )),
              ],
            ),
            if (_images.length > _maxImages)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('You have more images than the current limit ($_maxImages). Existing images are kept; remove some to add new ones.',
                    style: const TextStyle(color: kWarn, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: imgFull || _busy ? null : () => _addImages(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: imgFull || _busy ? null : () => _addImages(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
            ]),
            if (imgFull)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Image limit reached. Change it in Settings › Limits.', style: TextStyle(color: kMuted, fontSize: 12)),
              ),
          ]),
        ),
        SectionCard(
          title: 'Links',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${_links.length} / $_maxLinks', style: TextStyle(color: linkFull ? kDanger : kMuted, fontSize: 12)),
            TextButton(onPressed: linkFull ? null : () => _linkDialog(), child: const Text('+ Add')),
          ]),
          child: Column(children: [
            if (_links.isEmpty) const Text('No links yet.', style: TextStyle(color: kMuted)),
            ..._links.map((l) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: Text(str(l['title']).isEmpty ? str(l['url']) : str(l['title']), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${str(l['link_type']).isEmpty ? '' : '${str(l['link_type'])} · '}${str(l['url'])}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => openUrl(context, str(l['url'])),
                  trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _linkDialog(existing: l)),
                )),
            if (_links.length > _maxLinks)
              Text('More links than the current limit ($_maxLinks). Existing links are kept.',
                  style: const TextStyle(color: kWarn, fontSize: 12)),
          ]),
        ),
        SectionCard(
          title: 'Details',
          child: Column(children: [
            KV('Brand', _brand),
            KV('Linked collab', _collab),
            KV('Category', str(p['category'])),
            KV('Purchase price', toD(p['purchase_price']) > 0 ? money(toD(p['purchase_price'])) : ''),
            KV('Quantity', str(p['quantity'])),
            KV('Description', str(p['description'])),
            KV('Notes', str(p['notes'])),
          ]),
        ),
      ]),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final String fileName;
  const _ImageViewer({required this.fileName});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(child: InteractiveViewer(child: MediaImage(fileName, radius: 0, fit: BoxFit.contain))),
    );
  }
}
