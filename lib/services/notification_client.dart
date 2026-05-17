// Native push (FCM) registration entry point. Web push is intentionally
// disabled — see commit history if you want to revive it.
//
// On native targets (iOS / Android), the build picks up
// `notification_client_io.dart` once `flutterfire configure` has been
// run and the matching deps are in `pubspec.yaml`. Until that point
// (or on any non-io target), the stub is used and registration is a
// silent no-op.
export 'notification_client_stub.dart'
    if (dart.library.io) 'notification_client_io.dart';
