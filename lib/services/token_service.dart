import 'dart:convert';
import 'dart:math';

/// Token opachi in memoria, come nell'esempio del corso.
/// Il riavvio del server richiede un nuovo login, senza cancellare gli account.
class TokenService {
  final Map<String, int> _tokens = {};
  final Random _random = Random.secure();

  String issue(int companyId) {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = base64UrlEncode(bytes).replaceAll('=', '');
    _tokens[token] = companyId;
    return token;
  }

  int? companyIdFor(String token) => _tokens[token];

  void revoke(String token) => _tokens.remove(token);
}
