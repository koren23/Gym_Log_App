import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_page_route.dart';
import '../../models/app_colors.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';
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

  // Raw swipe-to-change-tabs tracking, mirroring the pinch-zoom approach in
  // SimpleLineChart: a Listener (not a GestureDetector) so it never
  // contests the gesture arena against a tab's own scrolling/chart
  // gestures — it just watches alongside them and acts on release.
  bool _chartInteractionActive = false;
  int? _swipePointer;
  double _swipeStartX = 0;
  double _swipeStartY = 0;

  void _onChartInteractionChanged(bool active) {
    _chartInteractionActive = active;
  }

  void _onBodyPointerDown(PointerDownEvent event) {
    if (_chartInteractionActive || _swipePointer != null) return;
    _swipePointer = event.pointer;
    _swipeStartX = event.position.dx;
    _swipeStartY = event.position.dy;
  }

  void _onBodyPointerMove(PointerMoveEvent event) {
    if (event.pointer != _swipePointer) return;
    // The chart's own pinch/pan/tooltip-scrub claimed this touch partway
    // through (e.g. a second finger just came down) — stop treating it as
    // a tab swipe.
    if (_chartInteractionActive) _swipePointer = null;
  }

  void _onBodyPointerUpOrCancel(PointerEvent event) {
    if (event.pointer != _swipePointer) return;
    _swipePointer = null;
    final dx = event.position.dx - _swipeStartX;
    final dy = event.position.dy - _swipeStartY;
    const threshold = 60.0;
    if (dx.abs() < threshold || dx.abs() < dy.abs() * 1.5) return;
    if (dx < 0 && _selectedIndex < 2) {
      setState(() => _selectedIndex++);
      HapticFeedback.selectionClick();
    } else if (dx > 0 && _selectedIndex > 0) {
      setState(() => _selectedIndex--);
      HapticFeedback.selectionClick();
    }
  }

  @override
  void initState() {
    super.initState();
    // Both one-time-per-launch and safe to call unconditionally: each is
    // gated by its own persisted flag/date check and no-ops once done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(snapshotProvider.notifier).cleanupDuplicateWorkoutDays();
      _maybeRotateThemeForToday();
    });
  }

  void _maybeRotateThemeForToday() {
    final settings = ref.read(appSettingsServiceProvider);
    if (!settings.autoThemeRotationEnabled) return;
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    if (settings.lastAutoThemeChangeDate == today) return;
    final current = ref.read(appColorsProvider);
    final choices = [
      for (final preset in kAppThemePresets)
        if (preset.colors != current) preset.colors,
    ];
    if (choices.isEmpty) return;
    final picked = choices[Random().nextInt(choices.length)];
    ref.read(appColorsProvider.notifier).applyPreset(picked);
    settings.setLastAutoThemeChangeDate(today);
  }

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
            ).push(AppPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Listener(
        // `translucent` (not the default `deferToChild`) so this still sees
        // every pointer event even when the touch starts on an empty gap in
        // a tab's layout (e.g. the spacing between Home's boxes) where no
        // descendant claims the hit — deferToChild silently dropped those,
        // which is why swiping was unreliable specifically on Home (Graphs/
        // History are filled edge-to-edge by a scrollable/chart, so a
        // descendant always claimed the hit there).
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onBodyPointerDown,
        onPointerMove: _onBodyPointerMove,
        onPointerUp: _onBodyPointerUpOrCancel,
        onPointerCancel: _onBodyPointerUpOrCancel,
        child: _TabSlideBody(
          index: _selectedIndex,
          children: [
            const HomeTab(),
            GraphsScreen(onChartInteractionChanged: _onChartInteractionChanged),
            const HistoryScreen(),
          ],
        ),
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
            onPressed: () => Navigator.of(
              context,
            ).push(AppPageRoute(builder: (_) => const BodyWeightEntryScreen())),
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
            ).push(AppPageRoute(builder: (_) => const LogWorkoutScreen())),
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

/// Like [IndexedStack] (every tab stays mounted so its state survives
/// switching away and back) but animates a horizontal slide between the
/// previous and new index instead of an instant cut. Only the from/to tabs
/// are kept onstage and hit-testable at any time — the others sit `Offstage`
/// with ticking disabled, exactly as cheap as a plain `IndexedStack`.
class _TabSlideBody extends StatefulWidget {
  const _TabSlideBody({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_TabSlideBody> createState() => _TabSlideBodyState();
}

class _TabSlideBodyState extends State<_TabSlideBody>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late int _fromIndex;
  late int _toIndex;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.index;
    _toIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void didUpdateWidget(_TabSlideBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _fromIndex = oldWidget.index;
      _toIndex = widget.index;
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        final direction = _toIndex > _fromIndex ? 1 : -1;
        return Stack(
          children: [
            for (var i = 0; i < widget.children.length; i++)
              Positioned.fill(
                child: Offstage(
                  offstage: i != _fromIndex && i != _toIndex,
                  child: TickerMode(
                    enabled: i == _fromIndex || i == _toIndex,
                    child: IgnorePointer(
                      ignoring: i != _toIndex,
                      child: FractionalTranslation(
                        translation: Offset(
                          i == _fromIndex && _fromIndex != _toIndex
                              ? -direction * t
                              : i == _toIndex && _fromIndex != _toIndex
                              ? direction * (1 - t)
                              : 0,
                          0,
                        ),
                        child: widget.children[i],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
