import '../errors/api_exception.dart';
import '../models/company.dart';
import 'json_store.dart';

class CompanyDao {
  final JsonCollection _collection;

  CompanyDao(this._collection);

  Future<void> load() => _collection.load();

  Company? findById(int id) {
    for (final item in _collection.all()) {
      if (item['id'] == id) return Company.fromJson(item);
    }
    return null;
  }

  Company? findByEmail(String email) {
    final normalized = email.trim().toLowerCase();
    for (final item in _collection.all()) {
      if (item['email'] == normalized) return Company.fromJson(item);
    }
    return null;
  }

  Future<Company> create({
    required String name,
    required String email,
    required String passwordHash,
    required String salt,
  }) => _collection.update((items) {
    final normalized = email.trim().toLowerCase();
    if (items.any((item) => item['email'] == normalized)) {
      throw const ApiException(409, 'Email già registrata.');
    }
    final lastId = items.fold<int>(0, (last, item) {
      final id = item['id'] as int;
      return id > last ? id : last;
    });
    final company = Company(
      id: lastId + 1,
      name: name.trim(),
      email: normalized,
      passwordHash: passwordHash,
      salt: salt,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    items.add(company.toJson());
    return company;
  });
}
