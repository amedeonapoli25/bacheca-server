import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../errors/api_exception.dart';

class CvStorage {
  static const maxBytes = 5 * 1024 * 1024;
  final String directory;
  final _random = Random.secure();

  CvStorage(this.directory);

  Future<Uint8List> read(String name) async {
    // Il nome è interno al server: non può indicare un percorso arbitrario.
    if (!RegExp(r'^[a-f0-9]{32}\.pdf$').hasMatch(name)) {
      throw const ApiException(404, 'Curriculum non disponibile.');
    }
    final file = File('$directory/$name');
    if (!await file.exists()) {
      throw const ApiException(404, 'Curriculum non disponibile.');
    }
    if (await file.length() > maxBytes) {
      throw const ApiException(409, 'Il curriculum salvato non è leggibile.');
    }
    final bytes = await file.readAsBytes();
    try {
      validate(name, bytes);
    } on ApiException {
      throw const ApiException(409, 'Il curriculum salvato non è leggibile.');
    }
    return bytes;
  }

  static void validate(String name, List<int> bytes) {
    if (bytes.isEmpty) throw const ApiException(422, 'Il curriculum è vuoto.');
    if (bytes.length > maxBytes) {
      throw const ApiException(413, 'Il curriculum supera il limite di 5 MiB.');
    }
    final header = latin1.decode(bytes.take(5).toList());
    final start = bytes.length > 2048 ? bytes.length - 2048 : 0;
    final tail = latin1.decode(bytes.sublist(start)).trimRight();
    if (!name.toLowerCase().endsWith('.pdf') ||
        header != '%PDF-' ||
        !tail.endsWith('%%EOF')) {
      throw const ApiException(422, 'Allega un curriculum in formato PDF.');
    }
  }

  Future<String> save(List<int> bytes) async {
    await Directory(directory).create(recursive: true);
    final name =
        '${List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}.pdf';
    final temporary = File('$directory/$name.part');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename('$directory/$name');
      return name;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> delete(String name) async {
    final file = File('$directory/$name');
    if (await file.exists()) await file.delete();
  }
}
