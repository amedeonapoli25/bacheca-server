import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'controllers/auth_controller.dart';
import 'controllers/application_controller.dart';
import 'dao/application_dao.dart';
import 'controllers/job_controller.dart';
import 'dao/company_dao.dart';
import 'dao/job_dao.dart';
import 'dao/json_store.dart';
import 'middleware/auth_middleware.dart';
import 'middleware/error_middleware.dart';
import 'services/token_service.dart';
import 'services/cv_storage.dart';

Future<Handler> createHandler({
  required String dataDir,
  bool logging = true,
}) async {
  await Directory(dataDir).create(recursive: true);
  final companies = CompanyDao(JsonCollection('$dataDir/companies.json'));
  await companies.load();
  final jobs = JobDao(JsonCollection('$dataDir/jobs.json'));
  await jobs.load();
  final applications = ApplicationDao(
    JsonCollection('$dataDir/applications.json'),
    CvStorage('$dataDir/curricula'),
  );
  await applications.load();
  final tokens = TokenService();
  final health = Router()
    ..get('/api/health', (Request request) => jsonResponse({'status': 'ok'}));
  final api = Cascade()
      .add(health.call)
      .add(AuthController(companies, tokens).router.call)
      .add(JobController(jobs, companies).router.call)
      .add(ApplicationController(applications, jobs).router.call)
      .add((Request request) => jsonError(404, 'Risorsa non trovata.'))
      .handler;

  var pipeline = const Pipeline();
  if (logging) pipeline = pipeline.addMiddleware(logRequests());
  return pipeline
      .addMiddleware(errorMiddleware())
      .addMiddleware(authMiddleware(tokens, companies))
      .addHandler(api);
}
