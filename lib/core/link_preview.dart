import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'media.dart';

/// Product details read from a product page (Open Graph, Twitter cards, JSON-LD Product schema).
/// Needs internet only while fetching; results are saved locally.
class LinkPreview {
  final String url;
  String? title;
  String? description;
  String? brand;
  String? siteName;
  String? category;
  double? price;
  final List<String> images = [];

  LinkPreview(this.url);

  bool get isEmpty => (title ?? '').isEmpty && images.isEmpty;

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-IN,en;q=0.9',
  };

  static Future<LinkPreview> fetch(String url) async {
    final uri = Uri.parse(url.trim());
    final http.Response res;
    try {
      res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw Exception('The site took too long to respond');
    } catch (_) {
      throw Exception('No internet connection or the site could not be reached');
    }
    if (res.statusCode >= 400) throw Exception('The site refused the request (HTTP ${res.statusCode})');
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final doc = html.parse(body);
    final base = res.request?.url ?? uri;
    final p = LinkPreview(url.trim());

    String? meta(String key) {
      final e = doc.querySelector('meta[property="$key"]') ?? doc.querySelector('meta[name="$key"]');
      final v = e?.attributes['content']?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    void addImage(String? src) {
      if (src == null || src.trim().isEmpty || src.startsWith('data:')) return;
      final abs = base.resolve(src.trim()).toString();
      if (!abs.startsWith('http')) return;
      if (!p.images.contains(abs)) p.images.add(abs);
    }

    // 1) JSON-LD Product schema (most reliable on shops)
    for (final s in doc.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        _readJsonLd(jsonDecode(s.text), p, addImage);
      } catch (_) {}
    }

    // 2) Open Graph / Twitter / standard meta
    p.title ??= meta('og:title') ?? meta('twitter:title') ?? doc.querySelector('title')?.text.trim();
    p.description ??= meta('og:description') ?? meta('twitter:description') ?? meta('description');
    p.siteName ??= meta('og:site_name');
    p.brand ??= meta('product:brand') ?? meta('og:brand');
    p.price ??= _num(meta('product:price:amount') ?? meta('og:price:amount'));
    addImage(meta('og:image:secure_url') ?? meta('og:image'));
    addImage(meta('twitter:image') ?? meta('twitter:image:src'));

    // 3) Site-specific fallbacks (Amazon, common shop markup)
    _amazon(doc, p, addImage);
    if (p.images.isEmpty) addImage(doc.querySelector('link[rel="image_src"]')?.attributes['href']);

    p.title = _clean(p.title);
    p.description = _clean(p.description);
    if (p.images.length > 12) p.images.removeRange(12, p.images.length);
    if (p.isEmpty) throw Exception('No product details found on this page. The site may block apps or need a browser.');
    return p;
  }

  static void _readJsonLd(Object? node, LinkPreview p, void Function(String?) addImage) {
    if (node is List) {
      for (final n in node) {
        _readJsonLd(n, p, addImage);
      }
      return;
    }
    if (node is! Map) return;
    if (node['@graph'] is List) _readJsonLd(node['@graph'], p, addImage);
    final type = node['@type'];
    final isProduct = type == 'Product' || (type is List && type.contains('Product'));
    if (!isProduct) return;
    p.title ??= node['name']?.toString();
    p.description ??= node['description']?.toString();
    p.category ??= node['category']?.toString();
    final b = node['brand'];
    p.brand ??= b is Map ? b['name']?.toString() : b?.toString();
    final img = node['image'];
    if (img is String) addImage(img);
    if (img is List) {
      for (final i in img) {
        addImage(i is Map ? i['url']?.toString() : i?.toString());
      }
    }
    if (img is Map) addImage(img['url']?.toString());
    var offers = node['offers'];
    if (offers is List && offers.isNotEmpty) offers = offers.first;
    if (offers is Map) p.price ??= _num(offers['price'] ?? offers['lowPrice']);
  }

  static void _amazon(dom.Document doc, LinkPreview p, void Function(String?) addImage) {
    final t = doc.querySelector('#productTitle')?.text.trim();
    if (t != null && t.isNotEmpty) p.title = t;
    final img = doc.querySelector('#landingImage') ?? doc.querySelector('#imgBlkFront');
    addImage(img?.attributes['data-old-hires']);
    final dyn = img?.attributes['data-a-dynamic-image'];
    if (dyn != null) {
      try {
        (jsonDecode(dyn) as Map).keys.take(3).forEach((k) => addImage(k.toString()));
      } catch (_) {}
    }
    final byline = doc.querySelector('#bylineInfo')?.text.trim();
    if (byline != null && byline.isNotEmpty && p.brand == null) {
      p.brand = byline.replaceAll(RegExp(r'^(Visit the|Brand:)\s*', caseSensitive: false), '').replaceAll(RegExp(r'\s*Store$'), '');
    }
    final bullets = doc.querySelectorAll('#feature-bullets li span').map((e) => e.text.trim()).where((e) => e.isNotEmpty).take(5);
    if (bullets.isNotEmpty && (p.description ?? '').length < 40) p.description = bullets.join('\n');
    final priceText = doc.querySelector('.a-price .a-offscreen')?.text;
    p.price ??= _num(priceText);
  }

  static double? _num(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final m = RegExp(r'[\d,]+(\.\d+)?').firstMatch(v.toString());
    return m == null ? null : double.tryParse(m.group(0)!.replaceAll(',', ''));
  }

  static String? _clean(String? s) {
    if (s == null) return null;
    final t = html.parseFragment(s).text?.replaceAll(RegExp(r'[ \t]+'), ' ').trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// Downloads an image into app storage. Returns the stored file name, or null if it isn't an image.
  static Future<String?> downloadImage(String url) async {
    try {
      final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 25));
      if (res.statusCode >= 400 || res.bodyBytes.length < 500) return null;
      final type = (res.headers['content-type'] ?? '').toLowerCase();
      String ext;
      if (type.contains('png')) {
        ext = '.png';
      } else if (type.contains('webp')) {
        ext = '.webp';
      } else if (type.contains('gif')) {
        ext = '.gif';
      } else if (type.contains('jpeg') || type.contains('jpg') || type.isEmpty || type.contains('octet')) {
        ext = '.jpg';
      } else if (type.contains('image')) {
        ext = '.jpg';
      } else {
        return null;
      }
      return await Media.importBytes(res.bodyBytes, ext);
    } catch (_) {
      return null;
    }
  }
}
