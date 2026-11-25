import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class PasswordService {
  static final _random = Random.secure();
  // La libreria esegue una funzione specifica per le password, con sale casuale.
  static final _algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  );

  static String generateSalt() =>
      base64UrlEncode(List<int>.generate(16, (_) => _random.nextInt(256)));

  static Future<String> hash(String password, String salt) async {
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: base64Url.decode(salt),
    );
    return base64UrlEncode(await key.extractBytes());
  }

  static Future<bool> verify(
    String password,
    String salt,
    String expected,
  ) async {
    final actual = await hash(password, salt);
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }
}
