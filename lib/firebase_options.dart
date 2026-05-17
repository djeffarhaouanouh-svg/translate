// Hand-rolled equivalent of what `flutterfire configure` would have
// produced. Values copied from `android/app/google-services.json` and
// `ios/Runner/GoogleService-Info.plist` — keep them in sync if you ever
// regenerate either file.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web push is disabled in this app — Firebase is native-only.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for $defaultTargetPlatform — '
          'rerun `flutterfire configure` or extend firebase_options.dart.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCVOs0pE6YPrkMfBCpb90VAbivo6ITFrK0',
    appId: '1:368302337524:android:4973f39f34292e459cdda1',
    messagingSenderId: '368302337524',
    projectId: 'swayco-bfe93',
    storageBucket: 'swayco-bfe93.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyARRsNitr3WaUMG39zWvmVKvZ3ohykFPY8',
    appId: '1:368302337524:ios:f8008b62a0ae53989cdda1',
    messagingSenderId: '368302337524',
    projectId: 'swayco-bfe93',
    storageBucket: 'swayco-bfe93.firebasestorage.app',
    iosBundleId: 'com.translate.livekit.livekitTranslate',
  );
}
