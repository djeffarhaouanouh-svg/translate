// Platform-specific notification registration: prompts the user for
// permission, gets a transport token / subscription, then upserts it
// into `public.notification_targets` via [NotificationApi].
//
// Picked at compile time:
//   * Web build (dart.library.html available) →
//     notification_client_web.dart — service worker + PushManager.
//   * Native (mobile / desktop) →
//     notification_client_stub.dart — currently a no-op; the next
//     commit wires firebase_messaging here.
//
// Public surface is intentionally tiny so screens can call this from
// `_onSignedIn` without caring about the platform.
export 'notification_client_stub.dart'
    if (dart.library.html) 'notification_client_web.dart';
