import '../models/job.dart';
import 'json_store.dart';

class JobDao {
  final JsonCollection _collection;

  JobDao(this._collection);

  Future<void> load() => _collection.load();

  List<Job> all() {
    final jobs = _collection.all().map(Job.fromJson).toList();
    jobs.sort((a, b) => b.id.compareTo(a.id));
    return jobs;
  }

  List<Job> forCompany(int companyId) =>
      all().where((job) => job.companyId == companyId).toList();

  Job? findById(int id) {
    for (final item in _collection.all()) {
      if (item['id'] == id) return Job.fromJson(item);
    }
    return null;
  }

  Future<Job> create({
    required int companyId,
    required String title,
    required String description,
  }) => _collection.update((items) {
    final lastId = items.fold<int>(0, (last, item) {
      final id = item['id'] as int;
      return id > last ? id : last;
    });
    final job = Job(
      id: lastId + 1,
      companyId: companyId,
      title: title,
      description: description,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    items.add(job.toJson());
    return job;
  });
}
