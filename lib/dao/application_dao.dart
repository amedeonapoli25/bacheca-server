import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../errors/api_exception.dart';
import '../models/job_application.dart';
import '../services/cv_storage.dart';
import 'json_store.dart';

class ApplicationDao {
  final JsonCollection _collection;
  final CvStorage _storage;

  ApplicationDao(this._collection, this._storage);

  Future<void> load() => _collection.load();

  JobApplication? findById(int id) {
    for (final item in _collection.all()) {
      if (item['id'] == id) return JobApplication.fromJson(item);
    }
    return null;
  }

  List<JobApplication> forJob(int jobId) {
    final applications = _collection
        .all()
        .where((item) => item['jobId'] == jobId)
        .map(JobApplication.fromJson)
        .toList();
    applications.sort((a, b) => b.id.compareTo(a.id));
    return applications;
  }

  Future<Uint8List> readCv(JobApplication application) async {
    final bytes = await _storage.read(application.cvFileName);
    if (bytes.length != application.cvSize) {
      throw const ApiException(
        409,
        'Il curriculum salvato risulta incompleto.',
      );
    }
    return bytes;
  }

  Future<JobApplication> create({
    required int jobId,
    required String firstName,
    required String lastName,
    required String email,
    required String submissionId,
    required String cvOriginalName,
    required List<int> cvBytes,
  }) async {
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              jobId,
              firstName,
              lastName,
              email,
              cvOriginalName,
              sha256.convert(cvBytes).toString(),
            ]),
          ),
        )
        .toString();
    String? savedFile;
    try {
      return await _collection.update((items) async {
        for (final item in items) {
          if (item['submissionId'] == submissionId) {
            final previous = JobApplication.fromJson(item);
            if (previous.fingerprint != fingerprint) {
              throw const ApiException(
                409,
                'Identificativo d’invio già usato con dati diversi.',
              );
            }
            return previous;
          }
        }
        final lastId = items.fold<int>(
          0,
          (last, item) => (item['id'] as int) > last ? item['id'] as int : last,
        );
        savedFile = await _storage.save(cvBytes);
        final application = JobApplication(
          id: lastId + 1,
          jobId: jobId,
          firstName: firstName,
          lastName: lastName,
          email: email,
          cvFileName: savedFile!,
          cvOriginalName: cvOriginalName,
          cvSize: cvBytes.length,
          submissionId: submissionId,
          fingerprint: fingerprint,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );
        items.add(application.toJson());
        return application;
      });
    } catch (_) {
      // Se il JSON non viene salvato, il PDF appena scritto non deve restare orfano.
      if (savedFile != null) await _storage.delete(savedFile!);
      rethrow;
    }
  }
}
