import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

const _format = 'Diary008-encrypted-backup';
const _iterations = 600000;
const _header = <String, Object>{
  'format': _format,
  'version': 1,
  'cipher': 'AES-256-GCM',
  'kdf': 'PBKDF2-HMAC-SHA256',
  'iterations': _iterations,
};
final _aad = utf8.encode(jsonEncode(_header));

bool isEncryptedBackup(String text) {
  try {
    final value = jsonDecode(text);
    return value is Map && value.containsKey('format');
  } on FormatException {
    return false;
  }
}

Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2.hmacSha256(
  iterations: _iterations,
  bits: 256,
).deriveKeyFromPassword(password: password, nonce: salt);

/// Passwords are used verbatim: whitespace and Unicode are significant.
Future<String> encryptBackup(String text, String password) =>
    Isolate.run(() async {
      if (password.isEmpty) throw const FormatException('密码不能为空。');
      final random = Random.secure();
      final salt = List<int>.generate(16, (_) => random.nextInt(256));
      final cipher = AesGcm.with256bits();
      final key = await _key(password, salt);
      try {
        final box = await cipher.encrypt(
          utf8.encode(text),
          secretKey: key,
          aad: _aad,
        );
        return jsonEncode({
          ..._header,
          'salt': base64Encode(salt),
          'nonce': base64Encode(box.nonce),
          'ciphertext': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        });
      } finally {
        key.destroy();
      }
    });

Future<String> decryptBackup(String text, String password) =>
    Isolate.run(() async {
      try {
        final value = jsonDecode(text) as Map<String, dynamic>;
        if (_header.entries.any((entry) => value[entry.key] != entry.value)) {
          throw const FormatException('不支持的加密备份格式或参数，现有记录未改变。');
        }
        final salt = base64Decode(value['salt'] as String);
        final nonce = base64Decode(value['nonce'] as String);
        final mac = base64Decode(value['mac'] as String);
        final ciphertext = base64Decode(value['ciphertext'] as String);
        if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
          throw const FormatException('加密备份文件无效或不完整，现有记录未改变。');
        }
        final key = await _key(password, salt);
        try {
          final bytes = await AesGcm.with256bits().decrypt(
            SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
            secretKey: key,
            aad: _aad,
          );
          return utf8.decode(bytes);
        } finally {
          key.destroy();
        }
      } on SecretBoxAuthenticationError {
        throw const FormatException('密码错误或备份文件已损坏，现有记录未改变。');
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException('加密备份文件无效或不完整，现有记录未改变。');
      }
    });
