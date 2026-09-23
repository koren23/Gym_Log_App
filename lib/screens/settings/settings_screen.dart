import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_colors.dart';
import '../../providers/auth_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';
import 'add_workout_day_dialog.dart';
import 'algorithms_info_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final spreadsheetUrl = ref.watch(appSettingsServiceProvider).spreadsheetUrl;
    ref.watch(snapshotProvider); // rebuild this screen when a sync completes.
    final pendingItems = ref.watch(pendingSyncQueueProvider).getAll();
    final currentColors = ref.watch(appColorsProvider);
    final dayDefs = ref.watch(workoutDayDefsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
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
            title: Text('Pending syncs: ${pendingItems.length}'),
            trailing: pendingItems.isEmpty
                ? null
                : TextButton(
                    onPressed: () =>
                        ref.read(snapshotProvider.notifier).retryPendingSyncs(),
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
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Theme', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final preset in kAppThemePresets)
                  _ThemeSwatch(
                    preset: preset,
                    selected: preset.colors == currentColors,
                    onTap: () => ref
                        .read(appColorsProvider.notifier)
                        .applyPreset(preset.colors),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Workout days',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Backed up to your sheet\'s "WorkoutDays" tab. Push, Pull, and '
              'Legs start out seeded for you but are ordinary days you can '
              'rename, edit, or delete like any other — name your own '
              'anything you like and pick which muscles belong to it.',
              style: TextStyle(fontSize: 12),
            ),
          ),
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
                    onPressed: () => ref
                        .read(workoutDayDefsProvider.notifier)
                        .removeCustomDay(d.id),
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
                await ref
                    .read(workoutDayDefsProvider.notifier)
                    .addCustomDay(result.label, result.muscleGroups);
              },
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('How suggestions work'),
            subtitle: const Text(
              'Plain-language explanation of the app\'s recommendation and '
              'trend-detection logic',
            ),
            leading: const Icon(Icons.info_outline),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AlgorithmsInfoScreen()),
            ),
          ),
          const Divider(),
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

