import 'dart:async';

import 'package:flutter/foundation.dart';

import 'profile_api.dart';

/// Tracks elapsed call time and debits the user's translation credits
/// periodically. Designed to be `start()`-ed when the call screen mounts
/// and `stop()`-ed when it tears down — flushing any partial period so
/// quitting mid-tick doesn't lose the seconds already spent.
///
/// Why client-side: the v1 model is honor-system. The decrement runs
/// against Supabase under the user's RLS, so they could in theory cheat
/// it by editing the request. If/when that matters, move the decrement
/// into a Postgres `SECURITY DEFINER` function and call it via RPC.
abstract final class UsageTracker {
  /// TEMPORARY: when true, every public method becomes a no-op and the
  /// reactive notifiers stay at "infinite credits / never exhausted".
  /// Used to remove the time gate while testing long calls (~1h+) end-
  /// to-end. Flip back to false and redeploy to re-enable the credit
  /// system before going to production.
  static const bool _kDisabled = true;

  /// Public mirror so callers (CallScreen) can also skip their own
  /// credit gates when tracking is off.
  static bool get isDisabled => _kDisabled;

  /// Flush window. Every [_tickSeconds] we push the accumulated time to
  /// Supabase. Short enough that closing the tab mid-call only loses a few
  /// seconds; long enough that we're not hammering the DB.
  static const _tickSeconds = 30;

  static Timer? _timer;
  static String _userId = '';
  static int _pendingSeconds = 0;

  /// Reactive snapshot of remaining credits. The Profile screen and Call
  /// screen both watch this so they see decrements live.
  static final ValueNotifier<int> creditsRemaining = ValueNotifier<int>(0);

  /// Fires once when [creditsRemaining] crosses from >0 to 0 during this
  /// tracking session. The Call screen uses this to disable translation
  /// without ending the call.
  static final ValueNotifier<bool> creditsExhausted =
      ValueNotifier<bool>(false);

  static bool get isRunning => _timer != null;

  /// Start tracking for [userId] with the known starting credit balance.
  /// Safe to call repeatedly — restarts the timer if the user changed,
  /// no-ops if already running for the same user.
  static void start({
    required String userId,
    required int initialCredits,
  }) {
    if (_kDisabled) {
      // Force "infinite credits" so the call screen never disables
      // translation and the profile doesn't render an empty bar.
      creditsRemaining.value = 1 << 30;
      creditsExhausted.value = false;
      return;
    }
    if (userId.isEmpty) return;
    if (_timer != null && _userId == userId) return;
    stop(); // cancel previous if any
    _userId = userId;
    _pendingSeconds = 0;
    creditsRemaining.value = initialCredits;
    creditsExhausted.value = initialCredits <= 0;
    _timer = Timer.periodic(
      const Duration(seconds: _tickSeconds),
      (_) => _onTick(),
    );
  }

  static void _onTick() {
    _pendingSeconds += _tickSeconds;
    // Optimistic local decrement so the UI feels live; the authoritative
    // value comes back from `consumeCredits` and overwrites this.
    final localNext = (creditsRemaining.value - _tickSeconds).clamp(0, 1 << 31);
    creditsRemaining.value = localNext;
    if (localNext == 0 && !creditsExhausted.value) {
      creditsExhausted.value = true;
    }
    unawaited(_flush());
  }

  static Future<void> _flush() async {
    if (_userId.isEmpty || _pendingSeconds <= 0) return;
    final amount = _pendingSeconds;
    _pendingSeconds = 0;
    final remaining =
        await ProfileApi.consumeCredits(userId: _userId, seconds: amount);
    if (remaining != null) {
      creditsRemaining.value = remaining;
      if (remaining == 0 && !creditsExhausted.value) {
        creditsExhausted.value = true;
      }
    }
  }

  /// Stop the periodic timer and flush any partial seconds so we don't
  /// lose what was already used since the last tick.
  static Future<void> stop({int extraSeconds = 0}) async {
    if (_kDisabled) return;
    _timer?.cancel();
    _timer = null;
    _pendingSeconds += extraSeconds;
    await _flush();
    _userId = '';
  }

  /// Wipe local state (e.g. on sign-out). Does NOT flush — caller should
  /// stop first if there's anything to persist.
  static void reset() {
    _timer?.cancel();
    _timer = null;
    _userId = '';
    _pendingSeconds = 0;
    creditsRemaining.value = 0;
    creditsExhausted.value = false;
  }
}
