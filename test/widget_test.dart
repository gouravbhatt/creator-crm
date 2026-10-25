import 'package:creator_crm/core/csv_export.dart';
import 'package:creator_crm/core/format.dart';
import 'package:creator_crm/core/invoice_pdf.dart';
import 'package:creator_crm/core/security.dart';
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

  test('UPI uri encodes values', () {
    final u = upiUri(upiId: 'me@okicici', name: 'A B', amount: 1500, note: 'INV/2026-27/001');
    expect(u, startsWith('upi://pay?pa=me%40okicici&pn=A%20B&am=1500.00'));
  });
}
