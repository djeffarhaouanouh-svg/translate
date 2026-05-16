# Push notifications setup

Two transports share `public.notification_targets` and the backend
`/api/notify` endpoint:

| Transport | Targets | Status |
|---|---|---|
| **Web Push** (RFC 8030) | Browsers (Chrome / Firefox / Edge / Safari ≥ 16.4) | ✅ wired |
| **FCM** | iOS + Android native builds | ⏳ template, needs your config |

## 1. Web Push (5 minutes)

```bash
cd backend
npx web-push generate-vapid-keys
```

You get two strings. Then:

1. Paste the **public** key into `web/index.html`:
   ```html
   <meta name="vapid-public-key" content="BPaste...PublicKey...Here">
   ```
2. Paste **both** keys into your backend env (Railway / `.env`):
   ```
   VAPID_PUBLIC_KEY=BPaste...PublicKey...Here
   VAPID_PRIVATE_KEY=Paste...PrivateKey...Here
   VAPID_SUBJECT=mailto:you@yourdomain.com
   ```
3. Add the Supabase service-role key so the dispatcher can read
   targets across users:
   ```
   SUPABASE_URL=https://xxx.supabase.co
   SUPABASE_SERVICE_ROLE_KEY=ey...
   ```
4. Install backend deps:
   ```bash
   cd backend && npm install
   ```
5. Redeploy backend + redeploy Flutter web. Reload the app — when the
   user signs in next, the browser will prompt for permission and
   register the subscription.

## 2. FCM (iOS + Android — 1-2 hours)

### Prerequisites

- **Apple Developer account** (99 USD/year) for iOS push.
- **Firebase project** (free) for orchestration.
- **APNs Authentication Key** (.p8) generated in Apple Developer →
  Keys → Create → "Apple Push Notifications service". Upload it in
  Firebase → Project Settings → Cloud Messaging → APNs.

### Code wiring

```bash
# In the project root:
flutter pub add firebase_core firebase_messaging
dart pub global activate flutterfire_cli
flutterfire configure
# Pick your Firebase project, both iOS + Android. This drops:
#  - lib/firebase_options.dart
#  - android/app/google-services.json
#  - ios/Runner/GoogleService-Info.plist
```

Then:

1. Rename `lib/services/notification_client_io_firebase.dart.template`
   →  `notification_client_io.dart` (drop the .template suffix).
2. Edit `lib/services/notification_client.dart` to dispatch on
   `dart.library.io` too:
   ```dart
   export 'notification_client_stub.dart'
       if (dart.library.html) 'notification_client_web.dart'
       if (dart.library.io)   'notification_client_io.dart';
   ```
3. In `lib/main.dart`, init Firebase right after `initSupabase()`:
   ```dart
   import 'package:firebase_core/firebase_core.dart';
   import 'firebase_options.dart';
   // …
   await Firebase.initializeApp(
     options: DefaultFirebaseOptions.currentPlatform,
   );
   ```
4. Backend env: paste the Firebase **service-account JSON** (Firebase
   → Project Settings → Service accounts → Generate new private key)
   either inline:
   ```
   FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
   ```
   or as a file path on Railway:
   ```
   FIREBASE_SERVICE_ACCOUNT_FILE=/etc/secrets/firebase-sa.json
   ```

### iOS-specific gotchas

- Open `ios/Runner.xcworkspace` in Xcode.
- Signing & Capabilities → add **Push Notifications** capability.
- Signing & Capabilities → add **Background Modes** → enable **Remote
  notifications**.
- Bump the deployment target to ≥ iOS 13.

### Android-specific gotchas

- `android/app/build.gradle` should already get `google-services.json`
  via the FlutterFire CLI. If not, ensure the bottom of the file has:
  ```gradle
  apply plugin: 'com.google.gms.google-services'
  ```
- `android/build.gradle`:
  ```gradle
  buildscript {
    dependencies {
      classpath 'com.google.gms:google-services:4.4.2'
    }
  }
  ```

## 3. Wiring events (next commit)

Once the transport is live, the four event triggers — incoming call,
new message, friend request, like — will call `/api/notify`. Until
then, registrations land in the DB but nothing dispatches yet.
