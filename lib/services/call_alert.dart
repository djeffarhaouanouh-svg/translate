// Public entry point — the actual implementation is picked at compile
// time based on whether `dart:html` is available (i.e. the web build).
//
// On native (mobile / desktop) the stub is a no-op: the OS rings the
// phone for incoming calls and we don't want an extra layer of in-app
// noise. On the web build the real implementation vibrates the device
// (when supported), and flashes the browser tab title so the user
// notices a call even when this tab isn't focused.
export 'call_alert_stub.dart' if (dart.library.html) 'call_alert_web.dart';
