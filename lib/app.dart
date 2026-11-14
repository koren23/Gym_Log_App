import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_providers.dart';
import 'providers/db_providers.dart';
import 'providers/settings_providers.dart';
import 'providers/sheet_data_providers.dart';
import 'screens/onboarding/sign_in_screen.dart';
import 'screens/root/main_shell.dart';
import 'services/db/default_exercise_details_seeder.dart';

class GymTrackerApp extends ConsumerWidget {
  const GymTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(appColorsProvider);
    // Both light and dark theme presets share this one ThemeData — brightness
    // and text/icon tones are derived from the preset's own background color
    // rather than the phone's system setting, so a dark preset reads correctly
    // (light text on dark surfaces) and a light preset does too, regardless of
    // which the user picks.
    final isDarkBackground =
        ThemeData.estimateBrightnessForColor(colors.background) ==
        Brightness.dark;
    final brightness = isDarkBackground ? Brightness.dark : Brightness.light;
    final baseScheme = ColorScheme.fromSeed(
      seedColor: colors.appBar,
      brightness: brightness,
    );
    // surfaceContainerHigh backs every "box" (Last few weeks, Push/Pull/Legs,
    // calendar day detail...). The Material-3 seed-generated tone doesn't
    // track our custom `background` color, so it's overridden here to always
    // read a touch brighter than whatever background the user picks —
    // otherwise some presets end up with boxes barely distinguishable from
    // the page behind them.
    final boxColor = _lighten(colors.background, 0.08);
    return MaterialApp(
      title: "Koren's Gym Log",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: baseScheme.copyWith(surfaceContainerHigh: boxColor),
        brightness: brightness,
        useMaterial3: true,
        scaffoldBackgroundColor: colors.background,
        appBarTheme: AppBarTheme(
          backgroundColor: colors.appBar,
          foregroundColor: Colors.white,
          // Flutter's Material-3 AppBar already listens for bubbling scroll
          // notifications and raises `scrolledUnderElevation` automatically
          // once a tab's content scrolls — explicit `shadowColor` is the only
          // thing missing, since the default is transparent and the tint-only
          // effect barely shows against a custom solid background color.
          elevation: 0,
          scrolledUnderElevation: 4,
          shadowColor: Colors.black,
        ),
      ),
      // The theme itself (not the phone's system setting) decides light vs.
      // dark now, based on the picked preset's background — see above.
      themeMode: ThemeMode.light,
      home: const _RootScreen(),
    );
  }
}

class _RootScreen extends ConsumerStatefulWidget {
  const _RootScreen();

  @override
  ConsumerState<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends ConsumerState<_RootScreen> {
  // Audited: this already does the minimal-UI silent-auth sequence
  // correctly (attemptLightweightAuthentication -> authorizationForScopes,
  // both no-UI, cache-only), exactly once on cold start, and nothing in
  // this app invalidates the cached grant except the explicit Settings
  // "Sign out" button. The two-prompt sign-in flow (identity, then Sheets
  // access) below is a confirmed hard `google_sign_in`/Google Identity
  // Services limitation — separate consent surfaces on every platform, no
  // combined API exists — not something fixable from this app's code.
  // Don't re-investigate this as a mystery bug later.
  bool _attemptedSilentSignIn = false;

  // Guards the one-time v3.0.0 upgrade migration (see
  // AppSettingsService.hasMigratedToLocalDb): only ever fired once per
  // app launch from here, right before MainShell is reachable either way
  // (no sheet ever connected, or a sheet connected and already signed in).
  bool _migrationAttempted = false;

  Future<void> _runMigrationIfNeeded() async {
    final settings = ref.read(appSettingsServiceProvider);
    if (settings.hasMigratedToLocalDb) return;
    try {
      final spreadsheetId = ref.read(spreadsheetIdProvider);
      if (spreadsheetId != null) {
        await ref.read(snapshotProvider.notifier).retryPendingSyncs();
        await ref.read(snapshotProvider.notifier).importFromSheet();
      }
      await settings.setHasMigratedToLocalDb(true);
    } catch (_) {
      // Best-effort — the flag stays unset, so this safely retries on the
      // next launch rather than ever being skipped.
    }
  }

  // Guards the one-time curated-starter-exercise notes/photo seed (see
  // AppSettingsService.hasSeededDefaultExerciseDetails) — fired right
  // alongside the v3.0.0 migration above, same once-per-launch gating.
  bool _exerciseDetailsSeedAttempted = false;

  Future<void> _seedDefaultExerciseDetailsIfNeeded() async {
    final settings = ref.read(appSettingsServiceProvider);
    if (settings.hasSeededDefaultExerciseDetails) return;
    try {
      await seedDefaultExerciseDetails(ref.read(exerciseDaoProvider));
      await settings.setHasSeededDefaultExerciseDetails(true);
    } catch (_) {
      // Best-effort — the flag stays unset, so this safely retries on the
      // next launch rather than ever being skipped.
    }
  }

  @override
  Widget build(BuildContext context) {
    // A connected sheet is optional (v3.0.0: local DB is the source of
    // truth) — only attempt sign-in/sheet access at all once the user has
    // actually set a spreadsheetId (via Settings). With no spreadsheetId,
    // fall straight through to MainShell so the app is fully usable offline
    // with no Google account involved.
    final spreadsheetId = ref.watch(spreadsheetIdProvider);
    if (spreadsheetId != null) {
      final authState = ref.watch(authStateProvider);
      if (!authState.isSignedIn || !authState.hasSheetsAccess) {
        if (!_attemptedSilentSignIn && !authState.isLoading) {
          _attemptedSilentSignIn = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(authStateProvider.notifier).signInSilently();
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (authState.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const SignInScreen();
      }
    }

    if (!_migrationAttempted) {
      _migrationAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runMigrationIfNeeded();
      });
    }

    if (!_exerciseDetailsSeedAttempted) {
      _exerciseDetailsSeedAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _seedDefaultExerciseDetailsIfNeeded();
      });
    }

    return const MainShell();
  }
}

Color _lighten(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}
