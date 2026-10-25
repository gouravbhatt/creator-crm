import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// Crypto primitives. Key derivation = Argon2id, encryption = AES-256-GCM.
class Crypto {
  static final Random _rnd = Random.secure();

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rnd.nextInt(256)));

  /// Argon2id(secret, salt) -> 32-byte key. Runs off the UI thread.
  static Future<List<int>> deriveKey(String secret, List<int> salt) {
    final s = secret;
    final sl = List<int>.from(salt);
    return Isolate.run(() async {
      final algo = Argon2id(parallelism: 1, memory: 19456, iterations: 2, hashLength: 32);
      final k = await algo.deriveKey(secretKey: SecretKey(utf8.encode(s)), nonce: sl);
      return await k.extractBytes();
    });
  }

  /// Output layout: nonce(12) | ciphertext | mac(16)
  static Future<Uint8List> seal(List<int> key, List<int> clear) async {
    final aes = AesGcm.with256bits();
    final nonce = randomBytes(12);
    final box = await aes.encrypt(clear, secretKey: SecretKey(key), nonce: nonce);
    final b = BytesBuilder(copy: false)
      ..add(nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return b.toBytes();
  }

  static Future<Uint8List> open(List<int> key, List<int> sealed) async {
    if (sealed.length < 28) throw AuthException('Data is too short or corrupted');
    final aes = AesGcm.with256bits();
    final nonce = sealed.sublist(0, 12);
    final mac = sealed.sublist(sealed.length - 16);
    final ct = sealed.sublist(12, sealed.length - 16);
    try {
      final clear = await aes.decrypt(SecretBox(ct, nonce: nonce, mac: Mac(mac)), secretKey: SecretKey(key));
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw AuthException('Wrong password or corrupted data');
    }
  }

  /// Seal/open large payloads (backups) in a background isolate.
  static Future<Uint8List> sealInBackground(List<int> key, List<int> clear) {
    final k = List<int>.from(key);
    return Isolate.run(() => Crypto.seal(k, clear));
  }

  static Future<Uint8List> openInBackground(List<int> key, List<int> sealed) {
    final k = List<int>.from(key);
    return Isolate.run(() => Crypto.open(k, sealed));
  }

  static Future<String> sha256Hex(List<int> data) async {
    final h = await Sha256().hash(data);
    return hex(h.bytes);
  }

  static String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

/// Stores the database key wrapped twice: once by the password, once by the recovery key.
/// The database key itself is never stored in clear text.
class Vault {
  static const FlutterSecureStorage _storage =
      FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const String _key = 'ccrm_vault_v1';
  static const String _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // no 0/O/1/I/L

  static Future<Map<String, dynamic>?> _load() async {
    final v = await _storage.read(key: _key);
    if (v == null) return null;
    return jsonDecode(v) as Map<String, dynamic>;
  }

  static Future<void> _save(Map<String, dynamic> m) => _storage.write(key: _key, value: jsonEncode(m));

  static Future<bool> exists() async => (await _load()) != null;

  static Future<String> username() async => (await _load())?['user']?.toString() ?? '';

  static String generateRecoveryKey() {
    final b = StringBuffer();
    for (var i = 0; i < 32; i++) {
      if (i > 0 && i % 4 == 0) b.write('-');
      b.write(_alphabet[Crypto._rnd.nextInt(_alphabet.length)]);
    }
    return b.toString();
  }

  static String normalizeRecovery(String rk) => rk.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static Future<Map<String, String>> _wrap(String secret, List<int> dbKey) async {
    final salt = Crypto.randomBytes(16);
    final kek = await Crypto.deriveKey(secret, salt);
    final sealed = await Crypto.seal(kek, dbKey);
    return {'salt': base64Encode(salt), 'box': base64Encode(sealed)};
  }

  static Future<Uint8List> _unwrap(Map<String, dynamic> w, String secret) async {
    final salt = base64Decode(w['salt'] as String);
    final box = base64Decode(w['box'] as String);
    final kek = await Crypto.deriveKey(secret, salt);
    return Crypto.open(kek, box);
  }

  /// First-run setup. Returns (recoveryKey, dbKey).
  static Future<(String, Uint8List)> create(String user, String password) async {
    final dbKey = Crypto.randomBytes(32);
    final rk = generateRecoveryKey();
    await _save({
      'v': 1,
      'user': user.trim(),
      'pw': await _wrap(password, dbKey),
      'rk': await _wrap(normalizeRecovery(rk), dbKey),
      'created': DateTime.now().toIso8601String(),
    });
    return (rk, dbKey);
  }

  static Future<Uint8List> unlockWithPassword(String user, String password) async {
    final v = await _load();
    if (v == null) throw AuthException('No account on this device');
    if (v['user'].toString().toLowerCase() != user.trim().toLowerCase()) {
      throw AuthException('Wrong username or password');
    }
    try {
      return await _unwrap(v['pw'] as Map<String, dynamic>, password);
    } on AuthException {
      throw AuthException('Wrong username or password');
    }
  }

  static Future<Uint8List> unlockWithRecovery(String recoveryKey) async {
    final v = await _load();
    if (v == null) throw AuthException('No account on this device');
    try {
      return await _unwrap(v['rk'] as Map<String, dynamic>, normalizeRecovery(recoveryKey));
    } on AuthException {
      throw AuthException('Recovery key is not correct');
    }
  }

  static Future<void> setPassword(List<int> dbKey, String newPassword) async {
    final v = await _load();
    if (v == null) throw AuthException('No account on this device');
    v['pw'] = await _wrap(newPassword, dbKey);
    await _save(v);
  }

  static Future<String> regenerateRecovery(List<int> dbKey) async {
    final v = await _load();
    if (v == null) throw AuthException('No account on this device');
    final rk = generateRecoveryKey();
    v['rk'] = await _wrap(normalizeRecovery(rk), dbKey);
    await _save(v);
    return rk;
  }

  static Future<void> wipe() => _storage.delete(key: _key);
}

/// Holds the unlocked database key for the session only.
class Session {
  static Uint8List? dbKey;
  static String user = '';
  static bool get unlocked => dbKey != null;
  static void clear() {
    dbKey = null;
  }
}
