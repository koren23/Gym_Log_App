import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/settings_providers.dart';
import 'services/settings/app_settings_service.dart';
import 'services/sync/pending_sync_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        appSettingsServiceProvider.overrideWithValue(AppSettingsService(prefs)),
        pendingSyncQueueProvider.overrideWithValue(PendingSyncQueue(prefs)),
      ],
      child: const GymTrackerApp(),
    ),
  );
}
