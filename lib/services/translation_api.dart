import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class TranslationApiException implements Exception {
  TranslationApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'TranslationApiException($statusCode): $message';
}

Uri _translationSessionUri() {
  const fromEnv = String.fromEnvironment('TOKEN_API_BASE');
  if (fromEnv.isNotEmpty) {
    final b = fromEnv.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$b/translation/realtime/session');
  }
  if (kIsWeb) {
    final o = Uri.base.removeFragment();
    return Uri(
      scheme: o.scheme,
      host: o.host,
      port: o.hasPort ? o.port : null,
      path: '/translation/realtime/session',
    );
  }
  final b = resolvedTokenApiBase().replaceAll(RegExp(r'/$'), '');
  return Uri.parse('$b/translation/realtime/session');
}

Uri _translationCallsUri() {
  const fromEnv = String.fromEnvironment('TOKEN_API_BASE');
  if (fromEnv.isNotEmpty) {
    final b = fromEnv.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$b/translation/realtime/calls');
  }
  if (kIsWeb) {
    final o = Uri.base.removeFragment();
    return Uri(
      scheme: o.scheme,
      host: o.host,
      port: o.hasPort ? o.port : null,
      path: '/translation/realtime/calls',
    );
  }
  final b = resolvedTokenApiBase().replaceAll(RegExp(r'/$'), '');
  return Uri.parse('$b/translation/realtime/calls');
}

Map<String, dynamic> _decodeObjectMap(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  throw FormatException('response is not a JSON object');
}

/// Extract ephemeral client secret from OpenAI `client_secrets` JSON (shapes vary).
String? pickClientSecret(Map<String, dynamic> j) {
  final cs = j['client_secret'];
  if (cs is String && cs.isNotEmpty) return cs;
  if (cs is Map) {
    final v = cs['value'];
    if (v is String && v.isNotEmpty) return v;
  }
  final top = j['value'];
  if (top is String && top.isNotEmpty) return top;
  return null;
}

Future<Map<String, dynamic>> fetchTranslationSession({
  required String outputLanguage,
}) async {
  final uri = _translationSessionUri();
  final res = await http.post(
    uri,
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'outputLanguage': outputLanguage}),
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw TranslationApiException(
      res.body.length > 400 ? '${res.body.substring(0, 400)}…' : res.body,
      statusCode: res.statusCode,
    );
  }
  return _decodeObjectMap(res.body);
}

Future<String> postTranslationCallsSdp({
  required String clientSecret,
  required String sdpOffer,
}) async {
  final uri = _translationCallsUri();
  final res = await http.post(
    uri,
    headers: {
      'Authorization': 'Bearer $clientSecret',
      'Content-Type': 'application/sdp',
    },
    body: sdpOffer,
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw TranslationApiException(
      res.body.length > 400 ? '${res.body.substring(0, 400)}…' : res.body,
      statusCode: res.statusCode,
    );
  }
  return res.body;
}
