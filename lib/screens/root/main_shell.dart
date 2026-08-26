import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_providers.dart';
import '../../widgets/sync_status_chip.dart';
import '../body_weight/body_weight_entry_screen.dart';
import '../graphs/graphs_screen.dart';
import '../history/history_screen.dart';
import '../home/home_screen.dart';
import '../log_workout/log_workout_screen.dart';
import '../settings/settings_screen.dart';

/// Persistent app shell: one AppBar + bottom nav across the Home, Graphs
/// and History tabs, plus a global "Log workout" FAB. Settings stays a
/// pushed route from the AppBar gear icon (as before) rather than a 4th tab.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _selectedIndex = 0;

  static const _tabTitles = ['', 'Progress', 'Workout history'];

  @override
  Widget build(BuildContext context) {
    final displayName = ref.watch(appDisplayNameProvider);
    final colors = ref.watch(appColorsProvider);

    final title = _selectedIndex == 0
        ? displayName
        : _tabTitles[_selectedIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: false,
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Center(child: SyncStatusChip()),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [HomeTab(), GraphsScreen(), HistoryScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Graphs'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BodyWeightEntryScreen()),
            ),
            backgroundColor: colors.dashboardButtons,
            foregroundColor: Colors.white,
            tooltip: 'Log body weight',
            shape: const CircleBorder(),
            child: const Icon(Icons.monitor_weight_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const LogWorkoutScreen())),
            backgroundColor: colors.logWorkoutHero,
            foregroundColor: Colors.white,
            tooltip: 'Log workout',
            shape: const CircleBorder(),
            child: const Icon(Icons.fitness_center),
          ),
        ],
      ),
    );
  }
}
