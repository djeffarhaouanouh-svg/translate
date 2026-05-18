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

Uri _translationTextUri() {
  const fromEnv = String.fromEnvironment('TOKEN_API_BASE');
  if (fromEnv.isNotEmpty) {
    final b = fromEnv.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$b/translation/text');
  }
  if (kIsWeb) {
    final o = Uri.base.removeFragment();
    return Uri(
      scheme: o.scheme,
      host: o.host,
      port: o.hasPort ? o.port : null,
      path: '/translation/text',
    );
  }
  final b = resolvedTokenApiBase().replaceAll(RegExp(r'/$'), '');
  return Uri.parse('$b/translation/text');
}

Map<String, dynamic> _decodeObjectMap(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  throw FormatException('response is not a JSON object');
}

/// Extract [expires_at] from OpenAI `client_secrets` response (seconds or ms since epoch).
DateTime? pickSessionExpiresAt(Map<String, dynamic> j) {
  num? n;
  final cs = j['client_secret'];
  if (cs is Map && cs['expires_at'] != null) {
    final v = cs['expires_at'];
    if (v is num) {
      n = v;
    } else if (v is String) {
      n = num.tryParse(v.trim());
    }
  }
  if (n == null && j['expires_at'] != null) {
    final v = j['expires_at'];
    if (v is num) {
      n = v;
    } else if (v is String) {
      n = num.tryParse(v.trim());
    }
  }
  if (n == null) return null;
  final v = n.toDouble();
  if (v > 1e12) {
    return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  }
  return DateTime.fromMillisecondsSinceEpoch((v * 1000).toInt());
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
  String? inputLanguage,
}) async {
  final uri = _translationSessionUri();
  final body = <String, dynamic>{'outputLanguage': outputLanguage};
  if (inputLanguage != null && inputLanguage.trim().isNotEmpty) {
    body['inputLanguage'] = inputLanguage;
  }
  final res = await http.post(
    uri,
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode(body),
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

Uri _backendUri(String path) {
  const fromEnv = String.fromEnvironment('TOKEN_API_BASE');
  if (fromEnv.isNotEmpty) {
    final b = fromEnv.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$b$path');
  }
  if (kIsWeb) {
    final o = Uri.base.removeFragment();
    return Uri(
      scheme: o.scheme,
      host: o.host,
      port: o.hasPort ? o.port : null,
      path: path,
    );
  }
  final b = resolvedTokenApiBase().replaceAll(RegExp(r'/$'), '');
  return Uri.parse('$b$path');
}

class TranslationProviderInfo {
  TranslationProviderInfo({required this.provider, this.botIdentityPrefix});
  final String provider;
  final String? botIdentityPrefix;
}

/// Queries the backend for its active translation provider (OpenAI WebRTC
/// realtime vs. Mistral via backend bot). Defaults to OpenAI on any failure
/// so the existing pipeline keeps working.
Future<TranslationProviderInfo> fetchTranslationProvider() async {
  try {
    final res = await http.get(_backendUri('/translation/provider'));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return TranslationProviderInfo(provider: 'openai');
    }
    final j = _decodeObjectMap(res.body);
    final provider = (j['provider'] is String) ? j['provider'] as String : 'openai';
    final botPrefix = j['botIdentityPrefix'];
    return TranslationProviderInfo(
      provider: provider,
      botIdentityPrefix: botPrefix is String ? botPrefix : null,
    );
  } catch (_) {
    return TranslationProviderInfo(provider: 'openai');
  }
}

class EnsureAgentResult {
  EnsureAgentResult({required this.identity, this.botIdentityPrefix});
  final String identity;
  final String? botIdentityPrefix;
}

/// Asks the backend to (idempotently) spawn a Mistral translation bot
/// in the given LiveKit room. Throws on backend errors so the caller
/// can retry.
Future<EnsureAgentResult> ensureTranslationAgent({required String roomName}) async {
  final res = await http.post(
    _backendUri('/translation/agent/ensure'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'roomName': roomName}),
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw TranslationApiException(res.body, statusCode: res.statusCode);
  }
  final j = _decodeObjectMap(res.body);
  final id = j['identity'];
  return EnsureAgentResult(
    identity: id is String ? id : '',
    botIdentityPrefix: 'xlate-bot',
  );
}

/// Tells the backend to shut the bot down. Best-effort.
Future<void> stopTranslationAgent({required String roomName}) async {
  await http.post(
    _backendUri('/translation/agent/stop'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'roomName': roomName}),
  );
}

/// One-shot text translation via the backend (`/translation/text` →
/// Mistral Chat Completions). Returns the translated string; falls back to
/// the original [text] on any error so the UI never goes blank.
Future<String> fetchTextTranslation({
  required String text,
  required String to,
  String? from,
}) async {
  if (text.trim().isEmpty) return text;
  final uri = _translationTextUri();
  try {
    final res = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'text': text,
        if (from != null && from.isNotEmpty) 'from': from,
        'to': to,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return text;
    }
    final j = _decodeObjectMap(res.body);
    final t = j['translated'];
    return t is String && t.isNotEmpty ? t : text;
  } catch (_) {
    return text;
  }
}
