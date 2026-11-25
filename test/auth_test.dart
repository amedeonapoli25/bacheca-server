import 'dart:convert';
import 'dart:io';

import 'package:bacheca_server/app.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late http.Client client;
  late String baseUrl;
  const password = 'UnaPassword123!';

  Future<void> start() async {
    server = await io.serve(
      await createHandler(dataDir: directory.path, logging: false),
      InternetAddress.loopbackIPv4,
      0,
    );
    baseUrl = 'http://127.0.0.1:${server.port}';
  }

  Future<http.Response> post(String path, Object body, {String? token}) =>
      client.post(
        Uri.parse('$baseUrl$path'),
        headers: {
          'content-type': 'application/json',
          if (token != null) 'authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

  Future<http.Response> register({String email = 'azienda@example.test'}) =>
      post('/api/auth/register', {
        'name': 'Azienda Demo',
        'email': email,
        'password': password,
      });

  Future<http.Response> login({
    String email = 'azienda@example.test',
    String secret = password,
  }) => post('/api/auth/login', {'email': email, 'password': secret});

  Future<http.Response> me([String? token]) => client.get(
    Uri.parse('$baseUrl/api/auth/me'),
    headers: {if (token != null) 'authorization': 'Bearer $token'},
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bacheca-auth-test-');
    client = http.Client();
    await start();
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
    'registrazione separata, login, account protetto e revoca al logout',
    () async {
      final created = await register();
      expect(created.statusCode, 201);
      final company = jsonDecode(created.body) as Map;
      expect(company['name'], 'Azienda Demo');
      expect(company.keys, isNot(contains('token')));
      expect(company.keys, isNot(contains('passwordHash')));
      expect(company.keys, isNot(contains('salt')));
      expect((await me()).statusCode, 401);

      final signedIn = await login();
      expect(signedIn.statusCode, 200);
      final session = jsonDecode(signedIn.body) as Map;
      final token = session['token'] as String;
      expect(jsonDecode((await me(token)).body), company);

      expect(
        (await post('/api/auth/logout', {}, token: token)).statusCode,
        204,
      );
      expect((await me(token)).statusCode, 401);
      expect(
        (await post('/api/auth/logout', {}, token: token)).statusCode,
        401,
      );
      expect((await login()).statusCode, 200);
    },
  );

  test(
    'email univoca normalizzata anche con registrazioni contemporanee',
    () async {
      final responses = await Future.wait([
        register(email: ' AZIENDA@Example.Test '),
        register(),
      ]);
      expect(responses.map((r) => r.statusCode), unorderedEquals([201, 409]));
      final stored = jsonDecode(
        await File('${directory.path}/companies.json').readAsString(),
      ) as List;
      expect(stored, hasLength(1));
      expect(stored.single['email'], 'azienda@example.test');
      expect((await login(email: ' AZIENDA@EXAMPLE.TEST ')).statusCode, 200);
    },
  );

  test('credenziali errate e token inventato non danno accesso', () async {
    await register();
    for (final response in [
      await login(secret: 'sbagliata'),
      await login(email: 'assente@example.test'),
    ]) {
      expect(response.statusCode, 401);
      expect(
        jsonDecode(response.body)['error'],
        'Email o password non corrette.',
      );
    }
    expect((await me('token-inventato')).statusCode, 401);
  });

  test(
    'riavvio: account e password persistono, vecchio token non valido',
    () async {
      await register();
      final oldToken = jsonDecode((await login()).body)['token'] as String;
      final text = await File('${directory.path}/companies.json')
          .readAsString();
      expect(text, isNot(contains(password)));
      expect((jsonDecode(text) as List).single['passwordHash'], isNotEmpty);
      await server.close(force: true);
      await start();
      expect((await me(oldToken)).statusCode, 401);
      expect((await login()).statusCode, 200);
      expect((await register()).statusCode, 409);
    },
  );

  test('validazione sul server anche senza passare dai form Flutter', () async {
    for (final body in [
      {},
      {'name': 'A', 'email': 'azienda@example.test', 'password': password},
      {'name': 'Demo', 'email': 'non-email', 'password': password},
      {'name': 'Demo', 'email': 'azienda@example.test', 'password': 'corta'},
      {'name': 12, 'email': 'azienda@example.test', 'password': password},
    ]) {
      expect((await post('/api/auth/register', body)).statusCode, 422);
    }
    expect(await File('${directory.path}/companies.json').exists(), isFalse);
    expect((await post('/api/auth/register', [])).statusCode, 400);
    final invalidJson = await client.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'content-type': 'application/json'},
      body: '{',
    );
    expect(invalidJson.statusCode, 400);
    final wrongType = await client.post(
      Uri.parse('$baseUrl/api/auth/login'),
      body: 'testo',
    );
    expect(wrongType.statusCode, 415);
    expect(
      (await post('/api/auth/register', {'name': 'x' * 17000})).statusCode,
      413,
    );
  });

  test(
    'errore di scrittura: nessun account fantasma, poi salvataggio riuscito',
    () async {
      final obstacle = await Directory('${directory.path}/companies.json.tmp')
          .create();
      expect((await register()).statusCode, 500);
      expect((await login()).statusCode, 401);
      expect(await File('${directory.path}/companies.json').exists(), isFalse);
      await obstacle.delete();
      expect((await register()).statusCode, 201);
      expect((await login()).statusCode, 200);
    },
  );

  test('health e risorse inesistenti hanno risposte JSON', () async {
    final health = await client.get(Uri.parse('$baseUrl/api/health'));
    expect(health.statusCode, 200);
    expect(jsonDecode(health.body), {'status': 'ok'});
    final unknown = await client.get(Uri.parse('$baseUrl/api/inesistente'));
    expect(unknown.statusCode, 404);
    expect(jsonDecode(unknown.body)['error'], isA<String>());
  });
}
