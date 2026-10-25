import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'security.dart';

/// SQLCipher-encrypted database. Schema is versioned; add migrations in [_upgrade].
class AppDb {
  AppDb._();

  static const int schemaVersion = 1;
  static Database? _db;

  /// Parent tables first: used for backup export / restore order.
  static const List<String> tables = [
    'settings',
    'brands',
    'contacts',
    'collabs',
    'deliverables',
    'metrics',
    'payments',
    'invoices',
    'expenses',
    'products',
    'product_images',
    'product_links',
    'activity',
  ];

  static Database get db {
    final d = _db;
    if (d == null) throw StateError('Database is locked');
    return d;
  }

  static bool get isOpen => _db != null;

  static String newId() => const Uuid().v4();

  static Future<String> path() async => p.join(await getDatabasesPath(), 'creator_crm.db');

  static Future<void> open(List<int> dbKey) async {
    await close();
    _db = await openDatabase(
      await path(),
      password: Crypto.hex(dbKey),
      version: schemaVersion,
      onConfigure: (d) async {
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (d, v) async {
        await _createV1(d);
      },
      onUpgrade: _upgrade,
    );
  }

  static Future<void> close() async {
    final d = _db;
    _db = null;
    await d?.close();
  }

  /// Removes the database file (used only at first-run setup when no vault exists,
  /// i.e. an orphaned file that can never be decrypted again).
  static Future<void> destroy() async {
    await close();
    await deleteDatabase(await path());
  }

  static Future<void> _upgrade(Database d, int from, int to) async {
    // Future: if (from < 2) { await d.execute('ALTER TABLE ...'); }
  }

  static Future<void> _createV1(Database d) async {
    const ts = 'created_at TEXT NOT NULL, updated_at TEXT NOT NULL';
    final stmts = <String>[
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
      'CREATE TABLE brands (id TEXT PRIMARY KEY, name TEXT NOT NULL, email TEXT, phone TEXT, website TEXT, '
          'gstin TEXT, address TEXT, notes TEXT, $ts)',
      'CREATE TABLE contacts (id TEXT PRIMARY KEY, brand_id TEXT REFERENCES brands(id) ON DELETE SET NULL, '
          'name TEXT NOT NULL, email TEXT, phone TEXT, role TEXT, notes TEXT, $ts)',
      'CREATE TABLE collabs (id TEXT PRIMARY KEY, brand_id TEXT NOT NULL REFERENCES brands(id) ON DELETE RESTRICT, '
          'contact_id TEXT REFERENCES contacts(id) ON DELETE SET NULL, title TEXT NOT NULL, campaign TEXT, '
          'deal_type TEXT NOT NULL DEFAULT \'Paid\', agreed_amount REAL NOT NULL DEFAULT 0, barter_value REAL NOT NULL DEFAULT 0, '
          'stage TEXT NOT NULL DEFAULT \'Inquiry\', source TEXT, start_date TEXT, end_date TEXT, publish_date TEXT, '
          'payment_due_date TEXT, payment_terms TEXT, usage_rights_until TEXT, exclusivity_until TEXT, renewal_date TEXT, '
          'next_action TEXT, next_action_date TEXT, links TEXT, notes TEXT, cancel_reason TEXT, cancelled_from TEXT, '
          'rating INTEGER, $ts)',
      'CREATE TABLE deliverables (id TEXT PRIMARY KEY, collab_id TEXT NOT NULL REFERENCES collabs(id) ON DELETE CASCADE, '
          'type TEXT NOT NULL, platform TEXT, title TEXT, due_date TEXT, live_date TEXT, status TEXT NOT NULL DEFAULT \'Planned\', '
          'draft_link TEXT, live_link TEXT, revision_count INTEGER NOT NULL DEFAULT 0, checklist TEXT, feedback TEXT, notes TEXT, $ts)',
      'CREATE TABLE metrics (id TEXT PRIMARY KEY, deliverable_id TEXT NOT NULL REFERENCES deliverables(id) ON DELETE CASCADE, '
          'label TEXT NOT NULL, captured_at TEXT NOT NULL, views INTEGER DEFAULT 0, reach INTEGER DEFAULT 0, likes INTEGER DEFAULT 0, '
          'comments INTEGER DEFAULT 0, shares INTEGER DEFAULT 0, saves INTEGER DEFAULT 0, $ts)',
      'CREATE TABLE payments (id TEXT PRIMARY KEY, collab_id TEXT NOT NULL REFERENCES collabs(id) ON DELETE CASCADE, '
          'amount REAL NOT NULL, tds REAL NOT NULL DEFAULT 0, received_date TEXT NOT NULL, method TEXT, reference TEXT, notes TEXT, $ts)',
      'CREATE TABLE invoices (id TEXT PRIMARY KEY, collab_id TEXT NOT NULL REFERENCES collabs(id) ON DELETE CASCADE, '
          'number TEXT NOT NULL, invoice_date TEXT NOT NULL, due_date TEXT, items TEXT NOT NULL, subtotal REAL NOT NULL, '
          'gst_rate REAL NOT NULL DEFAULT 0, gst_amount REAL NOT NULL DEFAULT 0, total REAL NOT NULL, status TEXT NOT NULL DEFAULT \'Draft\', '
          'notes TEXT, $ts)',
      'CREATE TABLE expenses (id TEXT PRIMARY KEY, collab_id TEXT NOT NULL REFERENCES collabs(id) ON DELETE CASCADE, '
          'category TEXT NOT NULL, amount REAL NOT NULL, date TEXT, notes TEXT, $ts)',
      'CREATE TABLE products (id TEXT PRIMARY KEY, brand_id TEXT REFERENCES brands(id) ON DELETE SET NULL, '
          'collab_id TEXT REFERENCES collabs(id) ON DELETE SET NULL, name TEXT NOT NULL, description TEXT, category TEXT, '
          'purchase_price REAL DEFAULT 0, quantity INTEGER DEFAULT 1, notes TEXT, $ts)',
      'CREATE TABLE product_images (id TEXT PRIMARY KEY, product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE, '
          'file_name TEXT NOT NULL, sort INTEGER NOT NULL DEFAULT 0, $ts)',
      'CREATE TABLE product_links (id TEXT PRIMARY KEY, product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE, '
          'url TEXT NOT NULL, title TEXT, link_type TEXT, sort INTEGER NOT NULL DEFAULT 0, $ts)',
      'CREATE TABLE activity (id TEXT PRIMARY KEY, collab_id TEXT REFERENCES collabs(id) ON DELETE CASCADE, '
          'message TEXT NOT NULL, $ts)',
      'CREATE INDEX idx_contacts_brand ON contacts(brand_id)',
      'CREATE INDEX idx_collabs_brand ON collabs(brand_id)',
      'CREATE INDEX idx_collabs_stage ON collabs(stage)',
      'CREATE INDEX idx_deliv_collab ON deliverables(collab_id)',
      'CREATE INDEX idx_metrics_deliv ON metrics(deliverable_id)',
      'CREATE INDEX idx_pay_collab ON payments(collab_id)',
      'CREATE INDEX idx_inv_collab ON invoices(collab_id)',
      'CREATE INDEX idx_exp_collab ON expenses(collab_id)',
      'CREATE INDEX idx_prod_brand ON products(brand_id)',
      'CREATE INDEX idx_img_prod ON product_images(product_id)',
      'CREATE INDEX idx_link_prod ON product_links(product_id)',
      'CREATE INDEX idx_act_collab ON activity(collab_id)',
    ];
    final batch = d.batch();
    for (final s in stmts) {
      batch.execute(s);
    }
    final defaults = <String, String>{
      'max_images': '5',
      'max_links': '5',
      'auto_lock_minutes': '5',
      'invoice_prefix': 'INV',
      'invoice_seq': '0',
      'gst_rate': '18',
    };
    defaults.forEach((k, v) => batch.insert('settings', {'key': k, 'value': v}));
    await batch.commit(noResult: true);
  }
}
