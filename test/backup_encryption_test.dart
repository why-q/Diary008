import 'dart:convert';

import 'package:diary008/backup_encryption.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'encrypted backups preserve Unicode and exact password whitespace',
    () async {
      const text = '{"正文":"私人日记🔐"}';
      const password = ' 密码🔑 ';
      final encrypted = await encryptBackup(text, password);
      expect(encrypted, isNot(contains('私人日记')));
      expect(isEncryptedBackup(encrypted), isTrue);
      expect(isEncryptedBackup(text), isFalse);
      expect(await decryptBackup(encrypted, password), text);
      await expectLater(
        decryptBackup(encrypted, password.trim()),
        throwsFormatException,
      );
      final second = await encryptBackup(text, password);
      expect(second, isNot(encrypted));
    },
  );

  test(
    'rejects modified ciphertext, nonce, and unsupported parameters',
    () async {
      final encrypted = await encryptBackup('private notebook', 'password');
      final original = jsonDecode(encrypted) as Map<String, dynamic>;
      for (final field in ['ciphertext', 'nonce', 'salt', 'mac']) {
        final changed = Map<String, dynamic>.from(original);
        final bytes = base64Decode(changed[field] as String);
        bytes[0] ^= 1;
        changed[field] = base64Encode(bytes);
        await expectLater(
          decryptBackup(jsonEncode(changed), 'password'),
          throwsFormatException,
        );
      }
      for (final entry in {
        'version': 2,
        'iterations': 1,
        'cipher': 'none',
        'salt': 'bad',
      }.entries) {
        final changed = {...original, entry.key: entry.value};
        await expectLater(
          decryptBackup(jsonEncode(changed), 'password'),
          throwsFormatException,
        );
      }
      await expectLater(encryptBackup('private', ''), throwsFormatException);
    },
  );
}
