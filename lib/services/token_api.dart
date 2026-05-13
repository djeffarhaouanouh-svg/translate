import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class LiveKitTokenResponse {
  LiveKitTokenResponse({
    required this.url,
    required this.token,
    required this.roomName,
  });

  final String url;
  final String token;
  final String roomName;

  /// Web (dart2js) can decode JSON values that are not strictly typed as [String]; never use raw `as String`.
  factory LiveKitTokenResponse.fromJson(Map<String, dynamic> j) {
    String reqStr(String key) {
      final v = j[key];
      if (v == null) return '';
      if (v is String) return v;
      return v.toString();
    }

    return LiveKitTokenResponse(
      url: reqStr('url'),
      token: reqStr('token'),
      roomName: reqStr('roomName'),
    );
  }
}

class TokenApiException implements Exception {
  TokenApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'TokenApiException($statusCode): $message';
}

Uri _liveKitTokenUri() {
  const fromEnv = String.fromEnvironment('TOKEN_API_BASE');
  if (fromEnv.isNotEmpty) {
    final b = fromEnv.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$b/livekit/token');
  }
  if (kIsWeb) {
    final o = Uri.base.removeFragment();
    return Uri(
      scheme: o.scheme,
      host: o.host,
      port: o.hasPort ? o.port : null,
      path: '/livekit/token',
    );
  }
  final b = resolvedTokenApiBase().replaceAll(RegExp(r'/$'), '');
  return Uri.parse('$b/livekit/token');
}

Map<String, dynamic> _decodeObjectMap(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  throw FormatException('response is not a JSON object');
}

Future<LiveKitTokenResponse> fetchLiveKitToken({
  required String roomName,
  required String identity,
  required String displayName,
  String sourceLang = '',
  String targetLang = '',
}) async {
  final uri = _liveKitTokenUri();
  final res = await http.post(
    uri,
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({
      'roomName': roomName,
      'identity': identity,
      'displayName': displayName,
      'sourceLang': sourceLang,
      'targetLang': targetLang,
    }),
  );
  if (res.statusCode != 200) {
    throw TokenApiException(res.body, statusCode: res.statusCode);
  }
  try {
    final map = _decodeObjectMap(res.body);
    final out = LiveKitTokenResponse.fromJson(map);
    if (out.url.isEmpty || out.token.isEmpty || out.roomName.isEmpty) {
      throw TokenApiException(
        'Token response missing url, token, or roomName: ${res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body}',
        statusCode: res.statusCode,
      );
    }
    return out;
  } on FormatException catch (e) {
    throw TokenApiException('Bad JSON from token server: $e', statusCode: res.statusCode);
  }
}
