import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../errors/api_exception.dart';

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String validatePersonName(Object? value, String label) {
  if (value is! String || value.trim().isEmpty || value.trim().length > 80) {
    throw ApiException(422, 'Inserisci un $label da 1 a 80 caratteri.');
  }
  return value.trim();
}

Future<Map<String, dynamic>> readJsonObject(Request request) async {
  final type = request.headers['content-type']?.split(';').first.trim();
  if (type != 'application/json') {
    throw const ApiException(415, 'Invia i dati in formato JSON.');
  }
  final bytes = <int>[];
  await for (final chunk in request.read()) {
    if (bytes.length + chunk.length > 16384) {
      throw const ApiException(413, 'Richiesta troppo grande.');
    }
    bytes.addAll(chunk);
  }
  final data = jsonDecode(utf8.decode(bytes));
  if (data is! Map<String, dynamic>) {
    throw const ApiException(400, 'Il corpo deve essere un oggetto JSON.');
  }
  return data;
}

String validateName(Object? value) {
  if (value is! String || value.trim().length < 2 || value.trim().length > 80) {
    throw const ApiException(
      422,
      'Il nome azienda deve avere da 2 a 80 caratteri.',
    );
  }
  return value.trim();
}

String validateEmail(Object? value) {
  if (value is! String ||
      value.trim().length > 254 ||
      !_emailPattern.hasMatch(value.trim())) {
    throw const ApiException(422, 'Inserisci un indirizzo email valido.');
  }
  return value.trim().toLowerCase();
}

String validatePassword(Object? value, {bool registration = false}) {
  if (value is! String || value.isEmpty || value.length > 128) {
    throw const ApiException(
      422,
      'Inserisci una password di massimo 128 caratteri.',
    );
  }
  if (registration && value.length < 8) {
    throw const ApiException(422, 'La password deve avere almeno 8 caratteri.');
  }
  return value;
}

String validateJobTitle(Object? value) {
  if (value is! String || value.trim().isEmpty || value.trim().length > 120) {
    throw const ApiException(422, 'Inserisci un titolo da 1 a 120 caratteri.');
  }
  return value.trim();
}

String validateJobDescription(Object? value) {
  if (value is! String || value.trim().isEmpty || value.trim().length > 5000) {
    throw const ApiException(
      422,
      'Inserisci una descrizione da 1 a 5000 caratteri.',
    );
  }
  return value.trim();
}
