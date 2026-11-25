import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../dao/company_dao.dart';
import '../errors/api_exception.dart';
import '../middleware/auth_middleware.dart';
import '../middleware/error_middleware.dart';
import '../services/password_service.dart';
import '../services/token_service.dart';
import '../utils/validators.dart';

class AuthController {
  final CompanyDao companies;
  final TokenService tokens;

  AuthController(this.companies, this.tokens);

  Router get router => Router()
    ..post('/api/auth/register', _register)
    ..post('/api/auth/login', _login)
    ..post('/api/auth/logout', guard(_logout))
    ..get('/api/auth/me', guard(_me));

  Future<Response> _register(Request request) async {
    final body = await readJsonObject(request);
    final name = validateName(body['name']);
    final email = validateEmail(body['email']);
    final password = validatePassword(body['password'], registration: true);
    final salt = PasswordService.generateSalt();
    final company = await companies.create(
      name: name,
      email: email,
      passwordHash: await PasswordService.hash(password, salt),
      salt: salt,
    );
    // S1 richiede di eseguire il login dopo la creazione dell'account.
    return jsonResponse(company.toPublicJson(), status: 201);
  }

  Future<Response> _login(Request request) async {
    final body = await readJsonObject(request);
    final email = validateEmail(body['email']);
    final password = validatePassword(body['password']);
    final company = companies.findByEmail(email);
    if (company == null ||
        !await PasswordService.verify(
          password,
          company.salt,
          company.passwordHash,
        )) {
      throw const ApiException(401, 'Email o password non corrette.');
    }
    return jsonResponse({
      'token': tokens.issue(company.id),
      'company': company.toPublicJson(),
    });
  }

  Response _me(Request request) =>
      jsonResponse(currentCompany(request)!.toPublicJson());

  Response _logout(Request request) {
    tokens.revoke(currentToken(request)!);
    return Response(204, headers: {'cache-control': 'no-store'});
  }
}
