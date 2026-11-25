import 'package:shelf/shelf.dart';

import '../dao/company_dao.dart';
import '../models/company.dart';
import '../services/token_service.dart';
import 'error_middleware.dart';

const _companyKey = 'bacheca.company';
const _tokenKey = 'bacheca.token';

Company? currentCompany(Request request) =>
    request.context[_companyKey] as Company?;
String? currentToken(Request request) => request.context[_tokenKey] as String?;

Middleware authMiddleware(TokenService tokens, CompanyDao companies) =>
    (Handler inner) => (Request request) {
      var authenticated = request;
      final header = request.headers['authorization'];
      if (header != null && header.toLowerCase().startsWith('bearer ')) {
        final token = header.substring(7).trim();
        final id = tokens.companyIdFor(token);
        final company = id == null ? null : companies.findById(id);
        if (company != null) {
          authenticated = request.change(
            context: {_companyKey: company, _tokenKey: token},
          );
        }
      }
      return inner(authenticated);
    };

Handler guard(Handler handler) => (Request request) {
  if (currentCompany(request) == null) {
    return jsonError(401, 'Accedi con il tuo account azienda.');
  }
  return handler(request);
};
