import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../dao/application_dao.dart';
import '../dao/job_dao.dart';
import '../errors/api_exception.dart';
import '../middleware/auth_middleware.dart';
import '../middleware/error_middleware.dart';
import '../models/job.dart';
import '../models/job_application.dart';
import '../utils/application_upload.dart';
import '../utils/validators.dart';

class ApplicationController {
  final ApplicationDao applications;
  final JobDao jobs;

  ApplicationController(this.applications, this.jobs);

  Router get router => Router()
    ..post('/api/jobs/<id|[0-9]+>/applications', _apply)
    ..get(
      '/api/company/jobs/<id|[0-9]+>/applications',
      (Request request, String id) =>
          guard((inner) => _list(inner, id))(request),
    )
    ..get(
      '/api/company/applications/<id|[0-9]+>',
      (Request request, String id) =>
          guard((inner) => _detail(inner, id))(request),
    )
    ..get(
      '/api/company/applications/<id|[0-9]+>/cv',
      (Request request, String id) => guard((inner) => _cv(inner, id))(request),
    );

  Job _ownedJob(Request request, int? id) {
    final job = id == null ? null : jobs.findById(id);
    if (job == null || job.companyId != currentCompany(request)!.id) {
      throw const ApiException(404, 'Annuncio non trovato.');
    }
    return job;
  }

  JobApplication _ownedApplication(Request request, String id) {
    final parsed = int.tryParse(id);
    final application = parsed == null ? null : applications.findById(parsed);
    final job = application == null ? null : jobs.findById(application.jobId);
    if (application == null ||
        job == null ||
        job.companyId != currentCompany(request)!.id) {
      throw const ApiException(404, 'Candidatura non trovata.');
    }
    return application;
  }

  Response _list(Request request, String id) {
    final job = _ownedJob(request, int.tryParse(id));
    return jsonResponse(
      applications
          .forJob(job.id)
          .map((item) => item.toCompanyJson(job.title))
          .toList(),
    );
  }

  Response _detail(Request request, String id) {
    final application = _ownedApplication(request, id);
    return jsonResponse(
      application.toCompanyJson(jobs.findById(application.jobId)!.title),
    );
  }

  Future<Response> _cv(Request request, String id) async {
    final application = _ownedApplication(request, id);
    final bytes = await applications.readCv(application);
    return Response.ok(
      bytes,
      headers: {
        'content-type': 'application/pdf',
        'content-length': bytes.length.toString(),
        'content-disposition':
            "inline; filename=\"curriculum.pdf\"; filename*=UTF-8''${Uri.encodeComponent(application.cvOriginalName)}",
        'cache-control': 'no-store',
        'x-content-type-options': 'nosniff',
      },
    );
  }

  Future<Response> _apply(Request request, String id) async {
    if (currentCompany(request) != null) {
      throw const ApiException(
        403,
        'L’azienda autenticata non può inviare candidature.',
      );
    }
    final jobId = int.tryParse(id);
    if (jobId == null || jobs.findById(jobId) == null) {
      throw const ApiException(404, 'Annuncio non trovato.');
    }
    final upload = await readApplicationUpload(request);
    final firstName = validatePersonName(upload.fields['firstName'], 'nome');
    final lastName = validatePersonName(upload.fields['lastName'], 'cognome');
    final email = validateEmail(upload.fields['email']);
    final submissionId = upload.fields['submissionId'];
    if (submissionId == null ||
        !RegExp(r'^[a-zA-Z0-9_-]{16,64}$').hasMatch(submissionId)) {
      throw const ApiException(422, 'Identificativo d’invio non valido.');
    }
    final application = await applications.create(
      jobId: jobId,
      firstName: firstName,
      lastName: lastName,
      email: email,
      submissionId: submissionId,
      cvOriginalName: upload.fileName,
      cvBytes: upload.bytes,
    );
    return jsonResponse(application.toReceiptJson(), status: 201);
  }
}
