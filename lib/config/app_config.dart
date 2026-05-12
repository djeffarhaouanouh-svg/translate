import 'token_api_resolve_io.dart' if (dart.library.html) 'token_api_resolve_web.dart'
    as resolve;

/// Base URL of the token server (no trailing slash). Override at compile time:
/// `flutter run --dart-define=TOKEN_API_BASE=http://192.168.1.10:8787`
String resolvedTokenApiBase() {
  const fromEnv = String.fromEnvironment('TOKEN_API_BASE');
  if (fromEnv.isNotEmpty) return fromEnv;
  return resolve.defaultTokenApiBase();
}
