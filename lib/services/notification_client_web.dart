import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'notification_api.dart';

/// Web Push registration: asks for browser permission, subscribes the
/// dedicated `notification_sw.js` service worker, and persists the
/// resulting endpoint + keys into `notification_targets`.
///
/// The VAPID public key has to be provided to the browser at subscribe
/// time. We read it from the `<meta name="vapid-public-key">` tag
/// emitted by the host page so the same Flutter build can ship to
/// multiple environments without a recompile. If the meta is missing
/// (or empty), registration silently no-ops.
abstract final class NotificationClient {
  static const _swScope = '/push/';
  static const _swUrl = '/notification_sw.js';

  static Future<bool> register(String userId) async {
    if (userId.isEmpty) return false;

    final vapid = _readVapidPublicKey();
    if (vapid == null || vapid.isEmpty) {
      debugPrint('[notify] no <meta vapid-public-key> on the page — skipping');
      return false;
    }

    try {
      // Permission first. We accept either `default` (will prompt) or
      // a prior `granted`. `denied` means the user explicitly refused —
      // we don't try to re-prompt; settings UI can offer to retry.
      final permission = await web.Notification.requestPermission().toDart;
      if (permission.toDart != 'granted') {
        debugPrint('[notify] permission=${permission.toDart}');
        return false;
      }

      final sw = web.window.navigator.serviceWorker;
      // Register our SW under a sibling scope so it doesn't collide
      // with the Flutter web SW.
      final registration = await sw
          .register(
            _swUrl.toJS,
            web.RegistrationOptions(scope: _swScope),
          )
          .toDart;

      // Don't await `sw.ready` here — it resolves only when a service
      // worker controls the current page's scope, but ours is scoped
      // to /push/ to avoid colliding with Flutter web's own SW at /.
      // The PushManager on the returned registration is usable as soon
      // as the SW is installed (no need to wait for `active`).

      // Existing subscription? Reuse it — re-registering is free side
      // of the network call but it keeps `updated_at` fresh in our DB.
      final existing = await registration.pushManager.getSubscription().toDart;
      final subscription = existing ??
          await registration.pushManager
              .subscribe(
                web.PushSubscriptionOptionsInit(
                  userVisibleOnly: true,
                  applicationServerKey:
                      _urlBase64ToUint8List(vapid).toJS,
                ),
              )
              .toDart;

      final endpoint = subscription.endpoint;
      final p256dh = _readSubscriptionKey(subscription, 'p256dh');
      final auth = _readSubscriptionKey(subscription, 'auth');
      if (p256dh == null || auth == null) {
        debugPrint('[notify] subscription missing keys, aborting');
        return false;
      }

      final ok = await NotificationApi.registerWebPush(
        userId: userId,
        endpoint: endpoint,
        p256dh: p256dh,
        auth: auth,
        userAgent: web.window.navigator.userAgent,
      );
      debugPrint('[notify] registered web push → ok=$ok endpoint=$endpoint');
      return ok;
    } catch (e) {
      debugPrint('[notify] register failed: $e');
      return false;
    }
  }

  static Future<void> unregister(String userId) async {
    try {
      final sw = web.window.navigator.serviceWorker;
      final reg = await sw.getRegistration(_swScope).toDart;
      if (reg == null) return;
      final sub = await reg.pushManager.getSubscription().toDart;
      if (sub == null) return;
      await NotificationApi.deleteByEndpoint(
        userId: userId,
        endpoint: sub.endpoint,
      );
      await sub.unsubscribe().toDart;
    } catch (e) {
      debugPrint('[notify] unregister failed: $e');
    }
  }

  /// Reads `<meta name="vapid-public-key" content="…">` from the host
  /// document. Returns null when missing so the caller can skip.
  static String? _readVapidPublicKey() {
    final list = web.document.getElementsByTagName('meta');
    for (var i = 0; i < list.length; i++) {
      final el = list.item(i) as web.HTMLMetaElement?;
      if (el == null) continue;
      if (el.name == 'vapid-public-key') {
        final content = el.content.trim();
        return content.isEmpty ? null : content;
      }
    }
    return null;
  }

  /// `PushSubscription.getKey(name)` returns an ArrayBuffer. The Web
  /// Push protocol expects URL-safe base64.
  static String? _readSubscriptionKey(
    web.PushSubscription sub,
    String name,
  ) {
    final buffer = sub.getKey(name);
    if (buffer == null) return null;
    final bytes = buffer.toDart.asUint8List();
    return _uint8ListToUrlBase64(bytes);
  }

  /// VAPID public keys are distributed as URL-safe base64 without
  /// padding; PushManager.subscribe needs the raw bytes as a typed
  /// array. Pure-Dart impl to avoid a `crypto`-package dependency.
  static Uint8List _urlBase64ToUint8List(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return _base64Decode(s);
  }

  static String _uint8ListToUrlBase64(Uint8List bytes) {
    final s = _base64Encode(bytes);
    return s.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  }

  static Uint8List _base64Decode(String s) {
    // dart:convert.base64.decode would be lighter, but importing it
    // here pulls in extra fluff. Browsers already expose atob() — use
    // that and convert to bytes.
    final binary = web.window.atob(s);
    final out = Uint8List(binary.length);
    for (var i = 0; i < binary.length; i++) {
      out[i] = binary.codeUnitAt(i);
    }
    return out;
  }

  static String _base64Encode(Uint8List bytes) {
    final chars = StringBuffer();
    for (final b in bytes) {
      chars.writeCharCode(b);
    }
    return web.window.btoa(chars.toString());
  }
}
