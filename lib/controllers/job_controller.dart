import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../dao/company_dao.dart';
import '../dao/job_dao.dart';
import '../errors/api_exception.dart';
import '../middleware/auth_middleware.dart';
import '../middleware/error_middleware.dart';
import '../models/job.dart';
import '../utils/validators.dart';

class JobController {
  final JobDao jobs;
  final CompanyDao companies;

  JobController(this.jobs, this.companies);

  Router get router => Router()
    ..get('/api/jobs', _list)
    ..get('/api/jobs/<id|[0-9]+>', _detail)
    ..post('/api/jobs', guard(_create))
    ..get('/api/company/jobs', guard(_ownJobs));

  Map<String, dynamic> _publicJob(Job job) =>
      job.toPublicJson(companies.findById(job.companyId)!.name);

  Response _list(Request request) =>
      jsonResponse(jobs.all().map(_publicJob).toList());

  Response _detail(Request request, String id) {
    final parsed = int.tryParse(id);
    final job = parsed == null ? null : jobs.findById(parsed);
    if (job == null) throw const ApiException(404, 'Annuncio non trovato.');
    return jsonResponse(_publicJob(job));
  }

  Response _ownJobs(Request request) => jsonResponse(
    jobs.forCompany(currentCompany(request)!.id).map(_publicJob).toList(),
  );

  Future<Response> _create(Request request) async {
    final body = await readJsonObject(request);
    final title = validateJobTitle(body['title']);
    final description = validateJobDescription(body['description']);
    // Il proprietario viene sempre dalla sessione, mai dai dati inviati dal form.
    final job = await jobs.create(
      companyId: currentCompany(request)!.id,
      title: title,
      description: description,
    );
    return jsonResponse(_publicJob(job), status: 201);
  }
}
