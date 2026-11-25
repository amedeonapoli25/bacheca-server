import 'dart:convert';
import 'dart:io';

import 'package:bacheca_server/app.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

import 'fixtures/cv_fixture.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late http.Client client;
  late String baseUrl;
  late String ownerToken;
  late int jobId;
  late int applicationId;
  final pdf = demoCvBytes();

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

  Future<String> account(String email, String name) async {
    expect(
      (await post('/api/auth/register', {
        'name': name,
        'email': email,
        'password': 'Password123!',
      })).statusCode,
      201,
    );
    final login = await post('/api/auth/login', {
      'email': email,
      'password': 'Password123!',
    });
    expect(login.statusCode, 200);
    return jsonDecode(login.body)['token'] as String;
  }

  Future<int> job(String token, String title) async {
    final response = await post('/api/jobs', {
      'title': title,
      'description': 'Offerta di prova.',
    }, token: token);
    expect(response.statusCode, 201);
    return jsonDecode(response.body)['id'] as int;
  }

  Future<int> apply(
    int id,
    String submissionId, {
    String firstName = 'Mario',
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$baseUrl/api/jobs/$id/applications'),
          )
          ..fields.addAll({
            'firstName': firstName,
            'lastName': 'Rossi',
            'email': 'mario.rossi@example.test',
            'submissionId': submissionId,
          })
          ..files.add(
            http.MultipartFile.fromBytes('cv', pdf, filename: 'currículum.pdf'),
          );
    final response = await http.Response.fromStream(await client.send(request));
    expect(response.statusCode, 201);
    return jsonDecode(response.body)['id'] as int;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'bacheca-company-review-',
    );
    client = http.Client();
    await start();
    ownerToken = await account('owner@example.test', 'Azienda Proprietaria');
    jobId = await job(ownerToken, 'Sviluppatore Flutter');
    applicationId = await apply(jobId, 'review_submission_000001');
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  List<String> privatePaths() => [
    '/api/company/jobs/$jobId/applications',
    '/api/company/applications/$applicationId',
    '/api/company/applications/$applicationId/cv',
  ];

  test('proprietario: elenco, dettaglio e PDF con dati riservati e intestazioni corrette', () async {
    final list = await get(privatePaths().first, token: ownerToken);
    expect(list.statusCode, 200);
    final applications = jsonDecode(list.body) as List;
    expect(applications, hasLength(1));
    final application = applications.single as Map;
    expect(application['firstName'], 'Mario');
    expect(application['lastName'], 'Rossi');
    expect(application['email'], 'mario.rossi@example.test');
    expect(application['jobTitle'], 'Sviluppatore Flutter');
    expect(application['cvOriginalName'], 'currículum.pdf');
    for (final hidden in ['cvFileName', 'submissionId', 'fingerprint']) {
      expect(application.containsKey(hidden), isFalse);
    }
    final detail = await get(privatePaths()[1], token: ownerToken);
    expect(jsonDecode(detail.body), application);
    final cv = await get(privatePaths()[2], token: ownerToken);
    expect(cv.statusCode, 200);
    expect(cv.bodyBytes, orderedEquals(pdf));
    expect(cv.headers['content-type'], 'application/pdf');
    expect(cv.headers['content-length'], pdf.length.toString());
    expect(cv.headers['cache-control'], 'no-store');
    expect(cv.headers['content-disposition'], contains('curr%C3%ADculum.pdf'));
    final emptyJob = await job(ownerToken, 'Annuncio senza candidature');
    expect(
      jsonDecode(
        (await get(
          '/api/company/jobs/$emptyJob/applications',
          token: ownerToken,
        )).body,
      ),
      isEmpty,
    );
    expect(
      (await get(
        '/api/company/jobs/999999/applications',
        token: ownerToken,
      )).statusCode,
      404,
    );
    expect(
      (await get(
        '/api/company/applications/999999',
        token: ownerToken,
      )).statusCode,
      404,
    );
    expect(
      (await get(
        '/api/company/applications/999999/cv',
        token: ownerToken,
      )).statusCode,
      404,
    );
  });

  test(
    'ospite, token falso e altra azienda non accedono ai dati o al curriculum',
    () async {
      final otherToken = await account('other@example.test', 'Altra Azienda');
      for (final path in privatePaths()) {
        expect((await get(path)).statusCode, 401);
        expect((await get(path, token: 'token-inventato')).statusCode, 401);
        expect((await get('$path?token=$ownerToken')).statusCode, 401);
        final denied = await get(path, token: otherToken);
        expect(denied.statusCode, 404);
        expect(denied.body, isNot(contains('Mario')));
        expect(denied.body, isNot(contains('mario.rossi@example.test')));
        expect(denied.body, isNot(contains('%PDF-')));
      }
      final otherJob = await job(otherToken, 'Offerta altra azienda');
      final otherApplication = await apply(
        otherJob,
        'review_submission_000002',
        firstName: 'Luigi',
      );
      final otherList = jsonDecode(
        (await get(
          '/api/company/jobs/$otherJob/applications',
          token: otherToken,
        )).body,
      ) as List;
      expect(otherList.single['firstName'], 'Luigi');
      expect(
        (await get(
          '/api/company/applications/$otherApplication/cv',
          token: ownerToken,
        )).statusCode,
        404,
      );
      expect(
        (await get(
          '/api/company/jobs/$otherJob/applications',
          token: ownerToken,
        )).statusCode,
        404,
      );
    },
  );

  test('logout revoca tutti gli endpoint della sessione e i dati persistono dopo il riavvio', () async {
    final before = (await get(privatePaths()[1], token: ownerToken)).body;
    expect(
      (await post('/api/auth/logout', {}, token: ownerToken)).statusCode,
      204,
    );
    for (final path in privatePaths()) {
      expect((await get(path, token: ownerToken)).statusCode, 401);
    }
    await server.close(force: true);
    await start();
    expect((await get(privatePaths()[2], token: ownerToken)).statusCode, 401);
    final login = await post('/api/auth/login', {
      'email': 'owner@example.test',
      'password': 'Password123!',
    });
    ownerToken = jsonDecode(login.body)['token'] as String;
    expect((await get(privatePaths()[1], token: ownerToken)).body, before);
    expect(
      (await get(privatePaths()[2], token: ownerToken)).bodyBytes,
      orderedEquals(pdf),
    );
  });

  test('file mancante o alterato produce un errore, mantenendo consultabile la candidatura', () async {
    final records = jsonDecode(
      await File('${directory.path}/applications.json').readAsString(),
    ) as List;
    final file = File(
      '${directory.path}/curricula/${records.single['cvFileName']}',
    );
    await file.delete();
    expect((await get(privatePaths()[2], token: ownerToken)).statusCode, 404);
    expect((await get(privatePaths()[1], token: ownerToken)).statusCode, 200);
    await file.writeAsString('file non PDF');
    expect((await get(privatePaths()[2], token: ownerToken)).statusCode, 409);
    await file.writeAsBytes([...pdf, 32]);
    expect((await get(privatePaths()[2], token: ownerToken)).statusCode, 409);
    await file.writeAsBytes(pdf);
    expect(
      (await get(privatePaths()[2], token: ownerToken)).bodyBytes,
      orderedEquals(pdf),
    );
  });
}
