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

  factory LiveKitTokenResponse.fromJson(Map<String, dynamic> j) {
    return LiveKitTokenResponse(
      url: j['url'] as String,
      token: j['token'] as String,
      roomName: j['roomName'] as String,
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
  final map = jsonDecode(res.body) as Map<String, dynamic>;
  return LiveKitTokenResponse.fromJson(map);
}
