import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import '../errors/api_exception.dart';

Response jsonResponse(Object? body, {int status = 200}) => Response(
  status,
  body: body == null ? null : jsonEncode(body),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

Response jsonError(int status, String message) =>
    jsonResponse({'error': message}, status: status);

Middleware errorMiddleware() =>
    (Handler inner) => (Request request) async {
      try {
        return await inner(request);
      } on ApiException catch (error) {
        return jsonError(error.status, error.message);
      } on FormatException {
        return jsonError(400, 'JSON non valido.');
      } catch (error, stack) {
        // Non si registrano password, token o contenuti delle richieste.
        stderr.writeln('Errore interno (${error.runtimeType}): $stack');
        return jsonError(500, 'Impossibile completare l’operazione. Riprova.');
      }
    };
