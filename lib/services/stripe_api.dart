import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Thin client for the backend's Stripe routes:
///   * POST /api/stripe/checkout {tier} → returns the Checkout URL
///   * POST /api/stripe/portal           → returns the Customer Portal URL
///
/// Both endpoints expect the caller's Supabase access token in the
/// `Authorization: Bearer …` header; backend uses the service-role
/// key to verify the JWT and resolve the user id.
abstract final class StripeApi {
  static Uri _endpoint(String path) {
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

  static String? _token() =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  /// Start a Checkout Session for [tier] (`'pro'` or `'ultra'`).
  /// Returns the URL the client should redirect to, or `null` on error.
  static Future<String?> startCheckout(String tier) async {
    final token = _token();
    if (token == null) {
      debugPrint('StripeApi.startCheckout: no auth session');
      return null;
    }
    try {
      final res = await http
          .post(
            _endpoint('/api/stripe/checkout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'tier': tier}),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        debugPrint(
          'StripeApi.startCheckout failed: ${res.statusCode} ${res.body}',
        );
        return null;
      }
      final j = jsonDecode(res.body);
      final url = j is Map<String, dynamic> ? j['url'] : null;
      return url is String ? url : null;
    } catch (e) {
      debugPrint('StripeApi.startCheckout exception: $e');
      return null;
    }
  }

  /// Open the Customer Portal (manage / cancel / change subscription).
  /// Returns the URL the client should redirect to, or `null` on error.
  static Future<String?> openPortal() async {
    final token = _token();
    if (token == null) return null;
    try {
      final res = await http
          .post(
            _endpoint('/api/stripe/portal'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        debugPrint(
          'StripeApi.openPortal failed: ${res.statusCode} ${res.body}',
        );
        return null;
      }
      final j = jsonDecode(res.body);
      final url = j is Map<String, dynamic> ? j['url'] : null;
      return url is String ? url : null;
    } catch (e) {
      debugPrint('StripeApi.openPortal exception: $e');
      return null;
    }
  }
}
