import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gym_tracker/app.dart';
import 'package:gym_tracker/providers/settings_providers.dart';
import 'package:gym_tracker/services/settings/app_settings_service.dart';
import 'package:gym_tracker/services/sync/pending_sync_queue.dart';

void main() {
  testWidgets('shows onboarding when no spreadsheet is configured', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(
            AppSettingsService(prefs),
          ),
          pendingSyncQueueProvider.overrideWithValue(PendingSyncQueue(prefs)),
        ],
        child: const GymTrackerApp(),
      ),
    );

    expect(find.text('Connect your sheet'), findsOneWidget);
  });
}
