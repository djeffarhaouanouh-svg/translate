import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web-only in-app alert for an incoming call.
///
/// Triggers:
///   * `navigator.vibrate(...)` repeated every two seconds — no-op on
///     desktop browsers (API missing) and on iOS Safari (Apple still
///     refuses to ship the Vibration API). Works on Chrome / Firefox /
///     Edge on Android, which covers most mobile-web cases.
///   * A flashing tab title that alternates between the original page
///     title and a "📞 Appel entrant…" marker every 800ms, so the user
///     notices a call even when the tab isn't focused.
///
/// The dialog itself (rendered by [RootShell._IncomingCallDialog]) is
/// the visual / interactive piece — this class only adds the sensory
/// cues around it.
abstract final class CallAlert {
  static Timer? _vibTimer;
  static Timer? _titleTimer;
  static String? _origTitle;

  static void start({String? callerName}) {
    // Defensive: if start() is called twice without a stop() in between,
    // collapse to a single set of timers so we don't leak.
    stop();
    _vibrateOnce();
    _vibTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _vibrateOnce(),
    );

    _origTitle = web.document.title;
    final flashLabel = (callerName != null && callerName.isNotEmpty)
        ? '📞 $callerName…'
        : '📞 Appel entrant…';
    var on = true;
    _titleTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      web.document.title = on ? flashLabel : (_origTitle ?? '');
      on = !on;
    });
  }

  /// Pattern: 300ms on / 200ms off / 300ms on / 200ms off / 600ms on.
  /// Approximates a classic ring "brrring-brrring".
  static void _vibrateOnce() {
    try {
      final pattern = <int>[300, 200, 300, 200, 600].map((v) => v.toJS).toList().toJS;
      web.window.navigator.vibrate(pattern);
    } catch (_) {
      // Desktop browsers + iOS Safari throw or no-op here — fine.
    }
  }

  static void stop() {
    _vibTimer?.cancel();
    _vibTimer = null;
    _titleTimer?.cancel();
    _titleTimer = null;
    if (_origTitle != null) {
      web.document.title = _origTitle!;
      _origTitle = null;
    }
    // Cancel any in-flight vibration.
    try {
      web.window.navigator.vibrate(0.toJS);
    } catch (_) {}
  }
}
