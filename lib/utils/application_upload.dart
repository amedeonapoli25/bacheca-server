import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';

import '../errors/api_exception.dart';
import '../services/cv_storage.dart';

class ApplicationUpload {
  final Map<String, String> fields;
  final String fileName;
  final Uint8List bytes;

  const ApplicationUpload(this.fields, this.fileName, this.bytes);
}

/// Multipart contiene i campi testuali e un solo allegato chiamato "cv".
Future<ApplicationUpload> readApplicationUpload(Request request) async {
  try {
    return await _parseApplicationUpload(request);
  } on HttpException {
    throw const ApiException(400, 'Richiesta multipart non valida.');
  } on MimeMultipartException {
    throw const ApiException(
      400,
      'Richiesta multipart incompleta o non valida.',
    );
  } on FormatException {
    throw const ApiException(400, 'Richiesta multipart non valida.');
  }
}

Future<ApplicationUpload> _parseApplicationUpload(Request request) async {
  final contentType = ContentType.parse(
    request.headers['content-type'] ?? 'application/octet-stream',
  );
  final boundary = contentType.parameters['boundary'];
  if (contentType.mimeType != 'multipart/form-data' ||
      boundary == null ||
      boundary.isEmpty ||
      boundary.length > 200) {
    throw const ApiException(
      415,
      'Invia i dati e il curriculum come multipart/form-data.',
    );
  }
  final body = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    if (body.length + chunk.length > CvStorage.maxBytes + 16384) {
      throw const ApiException(413, 'Il curriculum supera il limite di 5 MiB.');
    }
    body.add(chunk);
  }
  final bytes = body.takeBytes();
  final tailStart = bytes.length > boundary.length + 12
      ? bytes.length - boundary.length - 12
      : 0;
  final tail = latin1.decode(bytes.sublist(tailStart)).trimRight();
  // Prima del parser verifichiamo che il caricamento sia arrivato fino alla fine.
  if (!tail.endsWith('\r\n--$boundary--')) {
    throw const ApiException(400, 'Caricamento incompleto. Riprova l’invio.');
  }

  final fields = <String, String>{};
  String? fileName;
  Uint8List? fileBytes;
  await for (final part in Stream<List<int>>.value(
    bytes,
  ).transform(MimeMultipartTransformer(boundary))) {
    final disposition = HeaderValue.parse(
      part.headers['content-disposition'] ?? '',
    );
    final name = disposition.parameters['name'];
    if (disposition.value != 'form-data' || name == null) {
      throw const ApiException(400, 'Parte del form non valida.');
    }
    final originalName = disposition.parameters['filename'];
    if (originalName != null) {
      if (name != 'cv' || fileName != null) {
        throw const ApiException(422, 'Allega un solo curriculum PDF.');
      }
      fileName = originalName.replaceAll('\\', '/').split('/').last;
      if (fileName.isEmpty ||
          fileName.length > 200 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(fileName)) {
        throw const ApiException(422, 'Il nome del curriculum non è valido.');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in part) {
        if (builder.length + chunk.length > CvStorage.maxBytes) {
          throw const ApiException(
            413,
            'Il curriculum supera il limite di 5 MiB.',
          );
        }
        builder.add(chunk);
      }
      fileBytes = builder.takeBytes();
    } else {
      if (!{'firstName', 'lastName', 'email', 'submissionId'}.contains(name) ||
          fields.containsKey(name)) {
        throw const ApiException(422, 'Campi della candidatura non validi.');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in part) {
        if (builder.length + chunk.length > 2048) {
          throw const ApiException(422, 'Campo del form troppo lungo.');
        }
        builder.add(chunk);
      }
      fields[name] = utf8.decode(builder.takeBytes());
    }
  }
  if (fileName == null || fileBytes == null) {
    throw const ApiException(422, 'Allega il curriculum PDF.');
  }
  CvStorage.validate(fileName, fileBytes);
  return ApplicationUpload(fields, fileName, fileBytes);
}
