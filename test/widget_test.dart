import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:livekit_translate/main.dart';
import 'package:livekit_translate/services/user_prefs.dart';

void main() {
  testWidgets('shows join screen after onboarding is done', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      UserPrefs.keyOnboardingDone: true,
      UserPrefs.keyFirstName: 'Alex',
      UserPrefs.keySourceLang: 'en',
      UserPrefs.keyTargetLang: 'fr',
    });

    await tester.pumpWidget(const LiveKitTranslateApp());
    await tester.pumpAndSettle();

    expect(find.text('Calls'), findsOneWidget);
    expect(find.text('Join a room'), findsOneWidget);
  });
}
