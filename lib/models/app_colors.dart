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
  AppThemePreset(name: 'Lavender', colors: AppColors(
    appBar: Color(0xFF5A4E7C), background: Color(0xFFEFEAF7),
    dashboardButtons: Color(0xFF8673B0), logWorkoutHero: Color(0xFF7A66A3))),
  AppThemePreset(name: 'Coral', colors: AppColors(
    appBar: Color(0xFFB85C52), background: Color(0xFFFDEDE9),
    dashboardButtons: Color(0xFFE8897B), logWorkoutHero: Color(0xFFDE7A6B))),
  AppThemePreset(name: 'Olive', colors: AppColors(
    appBar: Color(0xFF5C5A33), background: Color(0xFFF3F1E0),
    dashboardButtons: Color(0xFF8C8A4A), logWorkoutHero: Color(0xFF7A7840))),
  AppThemePreset(name: 'Teal', colors: AppColors(
    appBar: Color(0xFF2C6B6B), background: Color(0xFFE6F3F2),
    dashboardButtons: Color(0xFF4AA3A0), logWorkoutHero: Color(0xFF3D8F8C))),
  AppThemePreset(name: 'Sky', colors: AppColors(
    appBar: Color(0xFF3E7FB0), background: Color(0xFFEAF4FB),
    dashboardButtons: Color(0xFF6BB4DE), logWorkoutHero: Color(0xFF5AA3CC))),
  AppThemePreset(name: 'Pumpkin', colors: AppColors(
    appBar: Color(0xFF9C5420), background: Color(0xFFFBEADA),
    dashboardButtons: Color(0xFFD98A42), logWorkoutHero: Color(0xFFCB7A34))),
  AppThemePreset(name: 'Clay', colors: AppColors(
    appBar: Color(0xFF7A4F3D), background: Color(0xFFF2E6DC),
    dashboardButtons: Color(0xFFA97C5F), logWorkoutHero: Color(0xFF96694F))),
  AppThemePreset(name: 'Obsidian', colors: AppColors(
    appBar: Color(0xFF1A1A22), background: Color(0xFF0D0D12),
    dashboardButtons: Color(0xFF6B6BD6), logWorkoutHero: Color(0xFF5A5AC2))),
  AppThemePreset(name: 'Navy Night', colors: AppColors(
    appBar: Color(0xFF16293D), background: Color(0xFF0B141F),
    dashboardButtons: Color(0xFF3D6FA0), logWorkoutHero: Color(0xFF4A82B5))),
  AppThemePreset(name: 'Amber Dusk', colors: AppColors(
    appBar: Color(0xFF2E2418), background: Color(0xFF17120C),
    dashboardButtons: Color(0xFFC98B3D), logWorkoutHero: Color(0xFFDBA24E))),
  AppThemePreset(name: 'Emerald Night', colors: AppColors(
    appBar: Color(0xFF13302A), background: Color(0xFF0A1714),
    dashboardButtons: Color(0xFF2F9E7A), logWorkoutHero: Color(0xFF3BB58C))),
  AppThemePreset(name: 'Wine', colors: AppColors(
    appBar: Color(0xFF3A1A28), background: Color(0xFF190D13),
    dashboardButtons: Color(0xFF8C3D5C), logWorkoutHero: Color(0xFFA3486B))),
  AppThemePreset(name: 'Lagoon', colors: AppColors(
    appBar: Color(0xFF1F6E78), background: Color(0xFFE2F3F3),
    dashboardButtons: Color(0xFF3FA6A6), logWorkoutHero: Color(0xFF2F8F93))),
  AppThemePreset(name: 'Peach', colors: AppColors(
    appBar: Color(0xFFC46A4A), background: Color(0xFFFDEADD),
    dashboardButtons: Color(0xFFF0A074), logWorkoutHero: Color(0xFFE88E5F))),
  AppThemePreset(name: 'Moss', colors: AppColors(
    appBar: Color(0xFF445C2E), background: Color(0xFFEAF0DF),
    dashboardButtons: Color(0xFF6F9448), logWorkoutHero: Color(0xFF5C8038))),
  AppThemePreset(name: 'Denim', colors: AppColors(
    appBar: Color(0xFF34506E), background: Color(0xFFE6EDF4),
    dashboardButtons: Color(0xFF5A7FA3), logWorkoutHero: Color(0xFF466D93))),
  AppThemePreset(name: 'Mustard', colors: AppColors(
    appBar: Color(0xFF8C7020), background: Color(0xFFFBF2D8),
    dashboardButtons: Color(0xFFCCA73C), logWorkoutHero: Color(0xFFBF9830))),
  AppThemePreset(name: 'Orchid', colors: AppColors(
    appBar: Color(0xFF7C3F6E), background: Color(0xFFF7E8F2),
    dashboardButtons: Color(0xFFB165A0), logWorkoutHero: Color(0xFFA0528D))),
  AppThemePreset(name: 'Ink', colors: AppColors(
    appBar: Color(0xFF14141C), background: Color(0xFF0A0A0F),
    dashboardButtons: Color(0xFF4A5570), logWorkoutHero: Color(0xFF596788))),
  AppThemePreset(name: 'Crimson Night', colors: AppColors(
    appBar: Color(0xFF330E0E), background: Color(0xFF160707),
    dashboardButtons: Color(0xFFA33B3B), logWorkoutHero: Color(0xFFBF4848))),
  AppThemePreset(name: 'Jade Night', colors: AppColors(
    appBar: Color(0xFF0E2E26), background: Color(0xFF071512),
    dashboardButtons: Color(0xFF2B8066), logWorkoutHero: Color(0xFF34977A))),
  AppThemePreset(name: 'Violet Dusk', colors: AppColors(
    appBar: Color(0xFF241433), background: Color(0xFF110919),
    dashboardButtons: Color(0xFF6B3FA0), logWorkoutHero: Color(0xFF7D4EB8))),
];
