import 'package:creator_crm/core/csv_export.dart';
import 'package:creator_crm/core/format.dart';
import 'package:creator_crm/core/invoice_pdf.dart';
import 'package:creator_crm/core/security.dart';
import 'package:creator_crm/core/snapshot.dart';
import 'package:creator_crm/core/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CSV escaping', () {
    test('plain values stay unquoted', () => expect(csvCell('Nykaa'), 'Nykaa'));
    test('comma is quoted', () => expect(csvCell('a,b'), '"a,b"'));
    test('quotes are doubled', () => expect(csvCell('say "hi"'), '"say ""hi"""'));
    test('newlines are quoted', () => expect(csvCell('l1\nl2'), '"l1\nl2"'));
    test('null is empty', () => expect(csvCell(null), ''));
  });

  group('format helpers', () {
    test('financial year label', () => expect(fyLabel(DateTime(2026, 4, 1)), '2026-27'));
    test('fy start before April', () => expect(fyStart(DateTime(2027, 2, 10)), DateTime(2026, 4, 1)));
    test('url validation', () {
      expect(isValidUrl('https://www.instagram.com/reel/abc/'), isTrue);
      expect(isValidUrl('instagram.com/reel'), isFalse);
      expect(isValidUrl('ftp://x.com'), isFalse);
    });
    test('toD parses commas', () => expect(toD('1,25,000'), 125000));
  });

  group('crypto', () {
    test('seal/open round trip', () async {
      final key = Crypto.randomBytes(32);
      final sealed = await Crypto.seal(key, [1, 2, 3, 4]);
      expect(await Crypto.open(key, sealed), [1, 2, 3, 4]);
    });
    test('wrong key fails', () async {
      final sealed = await Crypto.seal(Crypto.randomBytes(32), [9, 9]);
      expect(() => Crypto.open(Crypto.randomBytes(32), sealed), throwsA(isA<AuthException>()));
    });
    test('recovery key normalises', () {
      final rk = Vault.generateRecoveryKey();
      expect(rk.split('-').length, 8);
      expect(Vault.normalizeRecovery(rk.toLowerCase()), rk.replaceAll('-', ''));
    });
  });

  group('money model', () {
    test('order & refund with total including product', () {
      final c = _cv({'deal_type': kOrder, 'fee_mode': kFeeIncl, 'agreed_amount': 1500, 'refund_amount': 800, 'order_no': 'X'});
      expect(c.pendingFee, 1500);
      expect(c.pendingRefund, 800);
      expect(c.pending, 2300);
      expect(c.moneyOut, 800);
      expect(c.totalValue, 2300);
      expect(c.barterEarned, 0); // product counts only once refunded
    });
    test('refund received is not income, fee is', () {
      final c = _cv({'deal_type': kOrder, 'fee_mode': kFeeTop, 'agreed_amount': 1500, 'refund_amount': 800, 'order_no': 'X'}, receipts: [
        {'kind': 'Refund', 'amount': 800, 'tds': 0, 'received_date': '2026-10-01'},
        {'kind': 'Fee', 'amount': 1350, 'tds': 150, 'received_date': '2026-10-05'},
      ]);
      expect(c.received, 1500);
      expect(c.refundReceived, 800);
      expect(c.pending, 0);
      expect(c.barterEarned, 800);
      expect(c.earned, 2300);
      expect(c.paymentStatus, 'Paid');
    });
    test('agency cut reduces what brand owes', () {
      final c = _cv({'deal_type': kPaid, 'agreed_amount': 10000, 'agency_pct': 15});
      expect(c.agencyCut, 1500);
      expect(c.pendingFee, 8500);
    });
    test('barter value from products', () {
      final c = _cv({'deal_type': kBarter, 'agreed_amount': 0}, products: [
        {'purchase_price': 1200, 'quantity': 2},
      ]);
      expect(c.hasCash, false);
      expect(c.barterValue, 2400);
      expect(c.barterEarned, 2400);
      expect(c.paymentStatus, 'Barter');
    });
    test('add-ons add to fee', () {
      final c = _cv({'deal_type': kUgc, 'agreed_amount': 3000, 'addons': '[{"name":"Ad rights","amount":1000}]'});
      expect(c.agreed, 4000);
      expect(c.pendingFee, 4000);
    });
  });

  test('UPI uri encodes values', () {
    final u = upiUri(upiId: 'me@okicici', name: 'A B', amount: 1500, note: 'INV/2026-27/001');
    expect(u, startsWith('upi://pay?pa=me%40okicici&pn=A%20B&am=1500.00'));
  });
}

// ---------------- v3 money model ----------------
// ignore_for_file: prefer_const_constructors
CollabView _cv(Map<String, dynamic> row, {List<Map<String, dynamic>> receipts = const [], List<Map<String, dynamic>> products = const []}) =>
    CollabView({'id': 'c1', 'title': 't', 'stage': 'Posted', ...row}, 'Brand', const [], receipts, const [], const [], const {}, products, null, null);


