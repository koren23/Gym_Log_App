import 'package:flutter/material.dart';

/// The app's small set of user-customizable theme colors, matching the
/// hand-tuned defaults from earlier design passes.
class AppColors {
  const AppColors({
    required this.appBar,
    required this.background,
    required this.dashboardButtons,
    required this.logWorkoutHero,
  });

  final Color appBar;
  final Color background;
  final Color dashboardButtons;
  final Color logWorkoutHero;

  static const Color kDefaultAppBar = Color(0xFF5B6E4F);
  static const Color kDefaultBackground = Color(0xFFF2E3BE);
  static const Color kDefaultDashboardButtons = Color(0xFF5A8AA3);
  static const Color kDefaultLogWorkoutHero = Color(0xFF7C9968);

  static const AppColors defaults = AppColors(
    appBar: kDefaultAppBar,
    background: kDefaultBackground,
    dashboardButtons: kDefaultDashboardButtons,
    logWorkoutHero: kDefaultLogWorkoutHero,
  );

  AppColors copyWith({
    Color? appBar,
    Color? background,
    Color? dashboardButtons,
    Color? logWorkoutHero,
  }) {
    return AppColors(
      appBar: appBar ?? this.appBar,
      background: background ?? this.background,
      dashboardButtons: dashboardButtons ?? this.dashboardButtons,
      logWorkoutHero: logWorkoutHero ?? this.logWorkoutHero,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppColors &&
      other.appBar == appBar &&
      other.background == background &&
      other.dashboardButtons == dashboardButtons &&
      other.logWorkoutHero == logWorkoutHero;

  @override
  int get hashCode =>
      Object.hash(appBar, background, dashboardButtons, logWorkoutHero);
}

/// A named, ready-made [AppColors] palette shown in Settings — users pick
/// one of these instead of choosing each of the 4 colors individually.
class AppThemePreset {
  const AppThemePreset({required this.name, required this.colors});

  final String name;
  final AppColors colors;
}

const List<AppThemePreset> kAppThemePresets = [
  AppThemePreset(name: 'Forest', colors: AppColors.defaults),
  AppThemePreset(
    name: 'Ocean',
    colors: AppColors(
      appBar: Color(0xFF2C5F7C),
      background: Color(0xFFE8F1F5),
      dashboardButtons: Color(0xFF4A90A4),
      logWorkoutHero: Color(0xFF3A7CA5),
    ),
  ),
  AppThemePreset(
    name: 'Sunset',
    colors: AppColors(
      appBar: Color(0xFF8C4A3C),
      background: Color(0xFFFCEBDD),
      dashboardButtons: Color(0xFFD97848),
      logWorkoutHero: Color(0xFFE8703A),
    ),
  ),
  AppThemePreset(
    name: 'Berry',
    colors: AppColors(
      appBar: Color(0xFF5C3D5C),
      background: Color(0xFFF5E9F2),
      dashboardButtons: Color(0xFF9C5A8C),
      logWorkoutHero: Color(0xFF7A4A6B),
    ),
  ),
  AppThemePreset(
    name: 'Mint',
    colors: AppColors(
      appBar: Color(0xFF3D7A5C),
      background: Color(0xFFE6F4EC),
      dashboardButtons: Color(0xFF4A9B7A),
      logWorkoutHero: Color(0xFF5CAD8A),
    ),
  ),
  AppThemePreset(
    name: 'Slate',
    colors: AppColors(
      appBar: Color(0xFF3D4B52),
      background: Color(0xFFEDEFF0),
      dashboardButtons: Color(0xFF5C7A8A),
      logWorkoutHero: Color(0xFF4A6572),
    ),
  ),
  AppThemePreset(
    name: 'Midnight',
    colors: AppColors(
      appBar: Color(0xFF1B2838),
      background: Color(0xFF10151C),
      dashboardButtons: Color(0xFF3B82C4),
      logWorkoutHero: Color(0xFF4A90D9),
    ),
  ),
  AppThemePreset(
    name: 'Charcoal',
    colors: AppColors(
      appBar: Color(0xFF2E2E2E),
      background: Color(0xFF181818),
      dashboardButtons: Color(0xFFB08347),
      logWorkoutHero: Color(0xFFC99A5B),
    ),
  ),
  AppThemePreset(
    name: 'Forest Night',
    colors: AppColors(
      appBar: Color(0xFF1F3B2C),
      background: Color(0xFF122019),
      dashboardButtons: Color(0xFF3D7A5C),
      logWorkoutHero: Color(0xFF4A9B72),
    ),
  ),
  AppThemePreset(
    name: 'Rose',
    colors: AppColors(
      appBar: Color(0xFF9C4A5C),
      background: Color(0xFFFBEAEE),
      dashboardButtons: Color(0xFFD46A80),
      logWorkoutHero: Color(0xFFC65A72),
    ),
  ),
  AppThemePreset(
    name: 'Sand',
    colors: AppColors(
      appBar: Color(0xFF8A6D3F),
      background: Color(0xFFF7EDDC),
      dashboardButtons: Color(0xFFC9A063),
      logWorkoutHero: Color(0xFFB98A4A),
    ),
  ),
  AppThemePreset(
    name: 'Plum Night',
    colors: AppColors(
      appBar: Color(0xFF3B2545),
      background: Color(0xFF1A1220),
      dashboardButtons: Color(0xFF7A4A8C),
      logWorkoutHero: Color(0xFF8C5AA0),
    ),
  ),
  AppThemePreset(
    name: 'Steel',
    colors: AppColors(
      appBar: Color(0xFF33424E),
      background: Color(0xFF141B20),
      dashboardButtons: Color(0xFF5C7A8A),
      logWorkoutHero: Color(0xFF6E8FA0),
    ),
  ),
];
