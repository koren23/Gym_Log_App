import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_colors.dart';
import '../../providers/auth_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../widgets/app_snack_bar.dart';
import 'add_workout_day_dialog.dart';
import 'algorithms_info_screen.dart';
import 'changelog_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _backfilling = false;

  Future<void> _confirmBackfillExerciseInfo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fill in missing exercise info?'),
        content: const Text(
          "This writes to your sheet's Exercises tab: any exercise missing "
          "a unit gets kg, and any exercise missing a muscle-group entry "
          "gets added to its muscle's column (based on where it already "
          "appears in your logs). Nothing already set is changed.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Fill in'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _backfilling = true);
    final result = await ref
        .read(snapshotProvider.notifier)
        .backfillMissingExerciseInfo();
    if (!mounted) return;
    setState(() => _backfilling = false);

    final message = result.unitsFilled == 0 && result.musclesFilled == 0
        ? 'Nothing was missing — every exercise already had a unit and '
              'muscle group.'
        : 'Filled in ${result.unitsFilled} unit '
              '${result.unitsFilled == 1 ? 'entry' : 'entries'} and '
              '${result.musclesFilled} muscle-group '
              '${result.musclesFilled == 1 ? 'entry' : 'entries'}.';
    showAppSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final spreadsheetUrl = ref.watch(appSettingsServiceProvider).spreadsheetUrl;
    ref.watch(snapshotProvider); // rebuild this screen when a sync completes.
    final pendingItems = ref.watch(pendingSyncQueueProvider).getAll();
    final currentColors = ref.watch(appColorsProvider);
    final dayDefs = ref.watch(workoutDayDefsProvider);
    final autoThemeEnabled = ref
        .watch(appSettingsServiceProvider)
        .autoThemeRotationEnabled;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SettingsSection(
            title: 'Account',
            children: [
              ListTile(
                title: const Text('Signed in as'),
                subtitle: Text(authState.account?.email ?? 'Not signed in'),
              ),
              ListTile(
                title: const Text('Spreadsheet'),
                subtitle: Text(spreadsheetUrl ?? 'Not set'),
              ),
              ListTile(
                title: const Text('Change sheet'),
                leading: const Icon(Icons.swap_horiz),
                onTap: () async {
                  await ref.read(spreadsheetIdProvider.notifier).clear();
                },
              ),
              ListTile(
                title: const Text('Sign out'),
                leading: const Icon(Icons.logout),
                onTap: () async {
                  await ref.read(authStateProvider.notifier).signOut();
                },
              ),
            ],
          ),
          _SettingsSection(
            title: 'Sync',
            children: [
              ListTile(
                title: Text('Pending syncs: ${pendingItems.length}'),
                trailing: pendingItems.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => ref
                            .read(snapshotProvider.notifier)
                            .retryPendingSyncs(),
                        child: const Text('Retry now'),
                      ),
              ),
              for (final item in pendingItems)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.cloud_off, size: 18),
                  title: Text(item.payloadType.name),
                  subtitle: item.lastError == null
                      ? const Text('Not synced yet')
                      : Text(
                          'Retried ${item.retryCount}x — ${item.lastError}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ListTile(
                title: const Text('Fill in missing exercise info'),
                subtitle: const Text(
                  'One-time: adds a unit (default kg) and/or muscle-group '
                  'entry in the Exercises tab for any exercise that\'s '
                  'missing one, without touching anything already set.',
                ),
                trailing: _backfilling
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.auto_fix_high),
                        tooltip: 'Fill in missing exercise info',
                        onPressed: _confirmBackfillExerciseInfo,
                      ),
              ),
            ],
          ),
          _SettingsSection(
            title: 'Appearance',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final preset in kAppThemePresets)
                      _ThemeSwatch(
                        preset: preset,
                        selected: preset.colors == currentColors,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref
                              .read(appColorsProvider.notifier)
                              .applyPreset(preset.colors);
                        },
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('Rotate theme automatically'),
                subtitle: const Text(
                  'Picks a random theme above once a day, on its own.',
                ),
                value: autoThemeEnabled,
                onChanged: (value) async {
                  await ref
                      .read(appSettingsServiceProvider)
                      .setAutoThemeRotationEnabled(value);
                  setState(() {});
                },
              ),
            ],
          ),
          _SettingsSection(
            title: 'Workout days',
            subtitle:
                'Backed up to your sheet\'s "WorkoutDays" tab. Push, Pull, '
                'and Legs start out seeded for you but are ordinary days you '
                'can rename, edit, or delete like any other — name your own '
                'anything you like and pick which muscles belong to it.',
            children: [
              for (final d in dayDefs)
                ListTile(
                  dense: true,
                  title: Text(d.label),
                  subtitle: Text(
                    d.muscleGroups.map((g) => g.sheetHeader).join(', '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final result = await showAddWorkoutDayDialog(
                            context,
                            existing: d,
                          );
                          if (result == null) return;
                          HapticFeedback.lightImpact();
                          await ref
                              .read(workoutDayDefsProvider.notifier)
                              .updateCustomDay(
                                d.id,
                                result.label,
                                result.muscleGroups,
                              );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          ref
                              .read(workoutDayDefsProvider.notifier)
                              .removeCustomDay(d.id);
                        },
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add workout day'),
                  onPressed: () async {
                    final result = await showAddWorkoutDayDialog(context);
                    if (result == null) return;
                    HapticFeedback.lightImpact();
                    await ref
                        .read(workoutDayDefsProvider.notifier)
                        .addCustomDay(result.label, result.muscleGroups);
                  },
                ),
              ),
            ],
          ),
          _SettingsSection(
            title: 'About',
            children: [
              ListTile(
                title: const Text('How suggestions work'),
                subtitle: const Text(
                  'Plain-language explanation of the app\'s recommendation '
                  'and trend-detection logic',
                ),
                leading: const Icon(Icons.info_outline),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AlgorithmsInfoScreen(),
                  ),
                ),
              ),
              ListTile(
                title: const Text("What's new"),
                subtitle: const Text(
                  'Current app version and past release notes',
                ),
                leading: const Icon(Icons.new_releases_outlined),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChangelogScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Visually groups a related set of settings into a card with a header,
/// replacing what used to be one flat, undifferentiated `ListView`.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, subtitle == null ? 4 : 2),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                subtitle!,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 88,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _dot(preset.colors.appBar),
                const SizedBox(width: 4),
                _dot(preset.colors.dashboardButtons),
                const SizedBox(width: 4),
                _dot(preset.colors.logWorkoutHero),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              preset.name,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black26),
    ),
  );
}
