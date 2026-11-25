import 'dart:io';

import 'package:bacheca_server/app.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080');
  if (port == null || port < 1 || port > 65535) {
    stderr.writeln('PORT deve essere un numero tra 1 e 65535.');
    exitCode = 1;
    return;
  }
  try {
    final handler = await createHandler(
      dataDir: Platform.environment['DATA_DIR'] ?? 'data',
    );
    final server = await io.serve(handler, InternetAddress.anyIPv4, port);
    stdout.writeln(
      'Bacheca lavoro: server in ascolto sulla porta ${server.port}',
    );
    stdout.writeln('Simulatore iOS: http://127.0.0.1:${server.port}');
    stdout.writeln('Emulatore Android: http://10.0.2.2:${server.port}');
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      for (final address in interface.addresses) {
        stdout.writeln('Rete locale: http://${address.address}:${server.port}');
      }
    }
  } catch (error) {
    stderr.writeln(
      'Avvio non riuscito (${error.runtimeType}). Controlla porta e cartella dati.',
    );
    exitCode = 1;
  }
}
