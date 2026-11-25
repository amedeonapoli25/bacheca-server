import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bacheca_server/app.dart';
import 'package:bacheca_server/services/cv_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

import 'fixtures/cv_fixture.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late http.Client client;
  late String baseUrl;
  late String companyToken;
  late int jobId;
  final pdf = demoCvBytes();
  const submissionId = 'test_submission_00000001';

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

  Future<http.Response> upload({
    Map<String, String> fields = const {},
    List<int>? bytes,
    String fileName = 'cv.pdf',
    bool attach = true,
    bool duplicateFile = false,
    int? targetJob,
    String? token,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$baseUrl/api/jobs/${targetJob ?? jobId}/applications'),
          )
          ..fields.addAll({
            'firstName': ' Luís ',
            'lastName': " D'Amico ",
            'email': ' CANDIDATO@EXAMPLE.TEST ',
            'submissionId': submissionId,
            ...fields,
          });
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (attach) {
      request.files.add(
        http.MultipartFile.fromBytes('cv', bytes ?? pdf, filename: fileName),
      );
    }
    if (duplicateFile) {
      request.files.add(
        http.MultipartFile.fromBytes('cv', pdf, filename: 'altro.pdf'),
      );
    }
    return http.Response.fromStream(await client.send(request));
  }

  Future<List<dynamic>> records() async {
    final file = File('${directory.path}/applications.json');
    return await file.exists()
        ? jsonDecode(await file.readAsString()) as List
        : [];
  }

  Future<List<FileSystemEntity>> files() async {
    final folder = Directory('${directory.path}/curricula');
    return await folder.exists() ? folder.list().toList() : [];
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'bacheca-applications-test-',
    );
    client = http.Client();
    await start();
    expect(
      (await post('/api/auth/register', {
        'name': 'Azienda Test',
        'email': 'azienda@example.test',
        'password': 'Password123!',
      })).statusCode,
      201,
    );
    final login = await post('/api/auth/login', {
      'email': 'azienda@example.test',
      'password': 'Password123!',
    });
    companyToken = jsonDecode(login.body)['token'] as String;
    final job = await post('/api/jobs', {
      'title': 'Sviluppatore Flutter',
      'description': 'Offerta di prova.',
    }, token: companyToken);
    jobId = jsonDecode(job.body)['id'] as int;
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
    'candidatura senza login: dati e PDF privato persistono dopo il riavvio',
    () async {
      final response = await upload(fileName: '../../currículum.pdf');
      expect(response.statusCode, 201);
      final receipt = jsonDecode(response.body) as Map;
      expect(receipt['jobId'], jobId);
      expect(receipt.keys.toSet(), {'id', 'jobId', 'createdAt'});
      final saved = (await records()).single as Map;
      expect(saved['firstName'], 'Luís');
      expect(saved['lastName'], "D'Amico");
      expect(saved['email'], 'candidato@example.test');
      expect(saved['cvOriginalName'], 'currículum.pdf');
      expect(saved['cvFileName'], matches(r'^[a-f0-9]{32}\.pdf$'));
      final storedFile = File(
        '${directory.path}/curricula/${saved['cvFileName']}',
      );
      expect(await storedFile.readAsBytes(), orderedEquals(pdf));
      expect(
        (await client.get(
          Uri.parse('$baseUrl/curricula/${saved['cvFileName']}'),
        )).statusCode,
        404,
      );
      expect(
        (await client.get(Uri.parse('$baseUrl/api/jobs/$jobId/applications')))
            .statusCode,
        404,
      );
      await server.close(force: true);
      await start();
      expect((await records()).single, saved);
      expect(await storedFile.readAsBytes(), orderedEquals(pdf));
      final retry = await upload(fileName: '../../currículum.pdf');
      expect(jsonDecode(retry.body), receipt);
      expect(await records(), hasLength(1));
      expect(await files(), hasLength(1));
    },
  );

  test('campi, allegato mancante e contenuto non PDF sono rifiutati senza scrivere dati', () async {
    for (final fields in [
      {'firstName': ''},
      {'lastName': ' '},
      {'email': 'non-email'},
      {'lastName': 'X' * 81},
      {'submissionId': 'non valido'},
    ]) {
      expect((await upload(fields: fields)).statusCode, 422);
    }
    expect((await upload(attach: false)).statusCode, 422);
    expect((await upload(bytes: [])).statusCode, 422);
    expect((await upload(bytes: utf8.encode('Non è un PDF.'))).statusCode, 422);
    expect(
      (await upload(bytes: utf8.encode('%PDF-1.7\nfile interrotto')))
          .statusCode,
      422,
    );
    expect((await upload(fileName: 'cv.docx')).statusCode, 422);
    expect((await upload(duplicateFile: true)).statusCode, 422);
    expect(await records(), isEmpty);
    expect(await files(), isEmpty);
  });

  test('limite file: 5 MiB accettati, un byte oltre rifiutato', () async {
    final exact = Uint8List(CvStorage.maxBytes)..setRange(0, pdf.length, pdf);
    exact.setRange(exact.length - 6, exact.length, ascii.encode('%%EOF\n'));
    expect((await upload(bytes: exact)).statusCode, 201);
    expect((await records()).single['cvSize'], CvStorage.maxBytes);
    final over = Uint8List(CvStorage.maxBytes + 1)
      ..setRange(0, pdf.length, pdf);
    expect(
      (await upload(
        bytes: over,
        fields: {'submissionId': 'test_submission_00000002'},
      )).statusCode,
      413,
    );
    expect(await records(), hasLength(1));
    expect(await files(), hasLength(1));
  });

  test(
    'azienda autenticata e annuncio inesistente non possono ricevere un invio',
    () async {
      expect((await upload(token: companyToken)).statusCode, 403);
      expect((await upload(targetJob: 999999)).statusCode, 404);
      expect(await records(), isEmpty);
      expect(await files(), isEmpty);
    },
  );

  test(
    'errori di scrittura di PDF e JSON non lasciano candidature o file orfani',
    () async {
      final obstacle = await File('${directory.path}/curricula')
          .writeAsString('ostacolo di prova');
      expect((await upload()).statusCode, 500);
      expect(await records(), isEmpty);
      await obstacle.delete();
      final jsonObstacle = await Directory(
        '${directory.path}/applications.json.tmp',
      ).create();
      expect((await upload()).statusCode, 500);
      expect(await records(), isEmpty);
      expect(await files(), isEmpty);
      await jsonObstacle.delete();
      expect((await upload()).statusCode, 201);
      expect(await records(), hasLength(1));
      expect(await files(), hasLength(1));
    },
  );

  test('ritentativi contemporanei non duplicano; dati diversi con la stessa chiave sono rifiutati', () async {
    final responses = await Future.wait(List.generate(3, (_) => upload()));
    expect(responses.map((r) => r.statusCode), everyElement(201));
    expect(responses.map((r) => jsonDecode(r.body)['id']).toSet(), {1});
    expect(await records(), hasLength(1));
    expect(await files(), hasLength(1));
    expect(
      (await upload(fields: {'firstName': 'Un altro nome'})).statusCode,
      409,
    );
    expect(
      (await upload(fields: {'submissionId': 'test_submission_00000002'}))
          .statusCode,
      201,
    );
    expect(await records(), hasLength(2));
    expect(await files(), hasLength(2));
  });

  test(
    'multipart malformato o incompleto restituisce un errore senza salvare',
    () async {
      final uri = Uri.parse('$baseUrl/api/jobs/$jobId/applications');
      expect(
        (await client.post(
          uri,
          headers: {'content-type': 'application/json'},
          body: '{}',
        )).statusCode,
        415,
      );
      for (final body in [
        '',
        '--prova\r\nContent-Disposition: form-data; name="cv"; filename="cv.pdf"\r\n\r\n%PDF-1.7',
      ]) {
        final response = await client.post(
          uri,
          headers: {'content-type': 'multipart/form-data; boundary=prova'},
          body: body,
        );
        expect(response.statusCode, 400);
      }
      expect(await records(), isEmpty);
      expect(await files(), isEmpty);
    },
  );
}
