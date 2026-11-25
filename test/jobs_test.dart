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

  Future<void> start() async {
    server = await io.serve(
      await createHandler(dataDir: directory.path, logging: false),
      InternetAddress.loopbackIPv4,
      0,
    );
    baseUrl = 'http://127.0.0.1:${server.port}';
  }

  Future<http.Response> get(String path, {String? token}) => client.get(
    Uri.parse('$baseUrl$path'),
    headers: {if (token != null) 'authorization': 'Bearer $token'},
  );

  Future<http.Response> post(String path, Object body, {String? token}) =>
      client.post(
        Uri.parse('$baseUrl$path'),
        headers: {
          'content-type': 'application/json',
          if (token != null) 'authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

  Future<Map<String, dynamic>> account(String email, String name) async {
    final created = await post('/api/auth/register', {
      'name': name,
      'email': email,
      'password': 'Password123!',
    });
    expect(created.statusCode, 201);
    final response = await post('/api/auth/login', {
      'email': email,
      'password': 'Password123!',
    });
    expect(response.statusCode, 200);
    return (jsonDecode(response.body) as Map).cast<String, dynamic>();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bacheca-jobs-test-');
    client = http.Client();
    await start();
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
    'pubblicazione, bacheca pubblica, proprietà, dettaglio e persistenza',
    () async {
      expect(jsonDecode((await get('/api/jobs')).body), isEmpty);
      final body = {
        'title': 'Sviluppatore Flutter',
        'description': 'Sviluppo di applicazioni mobili.',
      };
      expect((await post('/api/jobs', body)).statusCode, 401);
      expect((await get('/api/company/jobs')).statusCode, 401);

      final first = await account('prima@example.test', 'Prima Azienda');
      final second = await account('seconda@example.test', 'Seconda Azienda');
      final firstToken = first['token'] as String;
      final secondToken = second['token'] as String;
      final firstId = (first['company'] as Map)['id'];
      final response = await post('/api/jobs', {
        ...body,
        'companyId': (second['company'] as Map)['id'],
        'companyName': 'Nome contraffatto',
      }, token: firstToken);
      expect(response.statusCode, 201);
      final job = jsonDecode(response.body) as Map;
      expect(job['companyId'], firstId);
      expect(job['companyName'], 'Prima Azienda');
      expect(job.keys, isNot(contains('email')));
      expect(job.keys, isNot(contains('passwordHash')));
      expect(DateTime.tryParse(job['createdAt'] as String), isNotNull);
      final jobId = job['id'];
      expect(jsonDecode((await get('/api/jobs/$jobId')).body), job);
      expect(
        jsonDecode((await get('/api/company/jobs', token: firstToken)).body),
        [job],
      );
      expect(
        jsonDecode((await get('/api/company/jobs', token: secondToken)).body),
        isEmpty,
      );

      final other = await post('/api/jobs', {
        'title': 'Analista',
        'description': 'Seconda offerta.',
      }, token: secondToken);
      expect(other.statusCode, 201);
      final board = jsonDecode((await get('/api/jobs')).body) as List;
      expect(board, hasLength(2));
      expect(board.first['title'], 'Analista');
      expect((await get('/api/jobs/999999')).statusCode, 404);
      expect((await get('/api/jobs/non-numerico')).statusCode, 404);

      await server.close(force: true);
      await start();
      expect(jsonDecode((await get('/api/jobs')).body), board);
      expect(jsonDecode((await get('/api/jobs/$jobId')).body), job);
      expect(
        (await post('/api/jobs', body, token: firstToken)).statusCode,
        401,
      );
      final newLogin = await post('/api/auth/login', {
        'email': 'prima@example.test',
        'password': 'Password123!',
      });
      final newToken = jsonDecode(newLogin.body)['token'] as String;
      expect(
        jsonDecode((await get('/api/company/jobs', token: newToken)).body),
        [job],
      );
      expect(
        (await post('/api/auth/logout', {}, token: newToken)).statusCode,
        204,
      );
      expect((await post('/api/jobs', body, token: newToken)).statusCode, 401);
    },
  );

  test(
    'validazione e scrittura fallita non pubblicano annunci incompleti',
    () async {
      final session = await account('demo@example.test', 'Azienda Demo');
      final token = session['token'] as String;
      for (final body in [
        {},
        {'title': '   ', 'description': 'Descrizione'},
        {'title': 'Titolo', 'description': '\n  '},
        {'title': 42, 'description': 'Descrizione'},
        {'title': 'T' * 121, 'description': 'Descrizione'},
        {'title': 'Titolo', 'description': 'D' * 5001},
      ]) {
        expect((await post('/api/jobs', body, token: token)).statusCode, 422);
      }
      expect(jsonDecode((await get('/api/jobs')).body), isEmpty);
      expect(await File('${directory.path}/jobs.json').exists(), isFalse);
      final obstacle = await Directory('${directory.path}/jobs.json.tmp')
          .create();
      final body = {
        'title': '  Tecnico Flutter  ',
        'description': 'Prima riga.\nSeconda riga: attività.',
      };
      expect((await post('/api/jobs', body, token: token)).statusCode, 500);
      expect(jsonDecode((await get('/api/jobs')).body), isEmpty);
      await obstacle.delete();
      final success = await post('/api/jobs', body, token: token);
      expect(success.statusCode, 201);
      final job = jsonDecode(success.body) as Map;
      expect(job['title'], 'Tecnico Flutter');
      expect(job['description'], body['description']);
      expect(job['id'], 1);
    },
  );

  test(
    'pubblicazioni contemporanee mantengono ID univoci e proprietari corretti',
    () async {
      final session = await account('demo@example.test', 'Azienda Demo');
      final token = session['token'] as String;
      final responses = await Future.wait(
        List.generate(
          6,
          (index) => post('/api/jobs', {
            'title': 'Annuncio $index',
            'description': 'Descrizione $index',
          }, token: token),
        ),
      );
      expect(responses.map((r) => r.statusCode), everyElement(201));
      final board = jsonDecode((await get('/api/jobs')).body) as List;
      expect(board.map((job) => job['id']).toSet(), hasLength(6));
      expect(board.map((job) => job['id']), [6, 5, 4, 3, 2, 1]);
      expect(
        board.map((job) => job['companyId']),
        everyElement(session['company']['id']),
      );
      final stored = jsonDecode(
        await File('${directory.path}/jobs.json').readAsString(),
      ) as List;
      expect(stored, hasLength(6));
    },
  );
}
