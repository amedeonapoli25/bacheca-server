import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Come nell'esempio del corso, conserva una collezione in un file JSON.
class JsonCollection {
  final String path;
  List<Map<String, dynamic>> _items = [];
  Future<void> _queue = Future<void>.value();

  JsonCollection(this.path);

  Future<void> load() async {
    final file = File(path);
    if (!await file.exists()) return;
    final data = jsonDecode(await file.readAsString()) as List;
    _items = data
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  List<Map<String, dynamic>> all() =>
      _items.map((item) => Map<String, dynamic>.from(item)).toList();

  /// Mette in coda controllo, modifica e salvataggio, evitando scritture sovrapposte.
  /// La copia diventa visibile solo dopo un salvataggio riuscito.
  Future<T> update<T>(FutureOr<T> Function(List<Map<String, dynamic>>) change) {
    final operation = _queue.then((_) async {
      final copy = all();
      final result = await change(copy);
      final content = const JsonEncoder.withIndent('  ').convert(copy);
      final temporary = File('$path.tmp');
      await temporary.parent.create(recursive: true);
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(path);
      _items = copy;
      return result;
    });
    // Un errore viene restituito al chiamante, ma non blocca le operazioni future.
    _queue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace st) {},
    );
    return operation;
  }
}
