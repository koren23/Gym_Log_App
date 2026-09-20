import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/text.dart';
import '../../models/exercise.dart';
import '../../models/exercise_unit.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../widgets/simple_line_chart.dart';
import '../body_weight/body_weight_history_screen.dart';

const _kBodyWeightOption = 'Body weight';
const _kMusclePrefix = 'muscle:';

// Fixed per-category colors for the graph picker's category title rows
// (per muscle group / Muscles / Body weight) — only the title row
// background is tinted with these; leaf items underneath use the normal
// theme colors.
const kBodyWeightColor = Colors.blue;
const kMuscleColor = Colors.brown;

String _optionLabel(String option) => option.startsWith(_kMusclePrefix)
    ? titleCase(option.substring(_kMusclePrefix.length))
    : option;

/// Y-axis legend label for a single exercise's own line (the [showingMuscle]
/// case has its own unit-agnostic "% of starting weight" label instead —
/// see the call site).
String _weightAxisLabel(Exercise? exercise) => switch (exercise?.unit) {
  null || ExerciseUnit.kg => 'Weight lifted',
  ExerciseUnit.bodyweight => 'Added weight (kg)',
  ExerciseUnit.time => 'Time held (sec)',
  ExerciseUnit.custom => exercise?.customUnitLabel ?? 'Value',
};

/// One combined graph with a searchable picker: any exercise (weight lifted
/// on the left axis, body weight overlaid in blue on an independent right
/// axis), a muscle (combining every exercise tagged with it in the
/// "Exercises" reference tab, as % of starting weight), or "Body weight"
/// itself as its own standalone graph.
class GraphsScreen extends ConsumerStatefulWidget {
  const GraphsScreen({super.key});

  @override
  ConsumerState<GraphsScreen> createState() => _GraphsScreenState();
}

class _GraphsScreenState extends ConsumerState<GraphsScreen> {
  String? _selectedOption;

  @override
  Widget build(BuildContext context) {
    final snapshotState = ref.watch(snapshotProvider).value;
    final yearsAscending = snapshotState?.snapshot.yearData.values.toList()
      ?..sort((a, b) => a.year.compareTo(b.year));

    final bodyWeightEntries = [...ref.watch(bodyWeightEntriesProvider)]
      ..sort((a, b) => a.date.compareTo(b.date));
    final bodyWeightPoints = bodyWeightEntries.length > 1
        ? [
            for (final e in bodyWeightEntries)
              ChartPoint(date: e.date, value: e.weightKg),
          ]
        : null;

    if (yearsAscending == null || yearsAscending.isEmpty) {
      return const Center(child: Text('No workout data loaded yet.'));
    }

    final exerciseMuscleInfo = ref.watch(exerciseMuscleInfoProvider);
    final allExercisesByName = <String, Exercise>{
      for (final y in yearsAscending)
        for (final e in y.allExercises) e.name: e,
    };
    final allExerciseNames = allExercisesByName.keys.toList()..sort();
    // Primary source: each exercise's own muscle tag from the year tabs
    // themselves (reliable for both legacy- and current-grouped tabs); the
    // optional legacy "Exercises" reference tab is folded in only as an
    // extra source, so this map isn't empty when that tab doesn't exist.
    // Legacy (pre-2026 Push/Pull/Legs-era) tags are excluded entirely — the
    // picker only ever browses by current muscle, never by old training day.
    final exercisesByMuscleName = <String, Set<String>>{};
    for (final entry in allExercisesByName.entries) {
      final group = entry.value.muscleGroup;
      if (entry.value.muscleGroupKnown && !group.legacy) {
        exercisesByMuscleName
            .putIfAbsent(group.sheetHeader, () => {})
            .add(entry.key);
      }
    }
    for (final i in exerciseMuscleInfo) {
      exercisesByMuscleName
          .putIfAbsent(i.muscleGroup.sheetHeader, () => {})
          .add(i.exerciseName);
    }
    final muscleNames = exercisesByMuscleName.keys.toList()..sort();

    _selectedOption ??= allExerciseNames.isEmpty
        ? _kBodyWeightOption
        : allExerciseNames.first;
    final showingBodyWeight = _selectedOption == _kBodyWeightOption;
    final showingMuscle = _selectedOption!.startsWith(_kMusclePrefix);

    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    const bodyWeightColor = kBodyWeightColor;

    List<ChartPoint> primaryPoints;
    Color primaryColorForChart;
    List<ChartPoint>? secondaryPoints;

    if (showingBodyWeight) {
      primaryPoints = bodyWeightPoints ?? const [];
      primaryColorForChart = bodyWeightColor;
      secondaryPoints = null;
    } else if (showingMuscle) {
      final muscle = _selectedOption!.substring(_kMusclePrefix.length);
      primaryPoints = buildMuscleProgressPoints(
        yearsAscending: yearsAscending,
        muscle: muscle,
        exerciseMuscleInfo: exerciseMuscleInfo,
      );
      primaryColorForChart = primaryColor;
      secondaryPoints = bodyWeightPoints;
    } else {
      final history = buildExerciseHistory(
        yearsAscending: yearsAscending,
        exerciseName: _selectedOption!,
      );
      final yearDataByYear = {for (final y in yearsAscending) y.year: y};
      primaryPoints = [
        for (final h in history)
          ChartPoint(
            date: h.date,
            value: h.avgWeight,
            label: h.exactDateKnown
                ? null
                : approximateWeekLabel(h.isoWeek, h.isoYear),
            note: yearDataByYear[h.isoYear]?.weekNotes[h.isoWeek],
            setsLabel: h.totalSets == null || h.avgReps == null
                ? null
                : '${h.totalSets}×${h.avgReps!.round()}',
          ),
      ];
      primaryColorForChart = primaryColor;
      secondaryPoints = bodyWeightPoints;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _showGraphPicker(
                    context,
                    muscleNames: muscleNames,
                    exercisesByMuscleName: exercisesByMuscleName,
                    allExerciseNames: allExerciseNames,
                  ),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Graph',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _optionLabel(_selectedOption!),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.list),
                tooltip: 'Edit body weight history',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BodyWeightHistoryScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showingMuscle)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              "Shown as % of your starting weight on each exercise — 100% = your "
              'first logged session. Switching exercises for this muscle stays on '
              'the same graph, each starting its own 100% baseline.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: SimpleLineChart(
            points: primaryPoints,
            color: primaryColorForChart,
            secondaryPoints: secondaryPoints,
            secondaryColor: bodyWeightColor,
            secondaryFloor: 45,
            secondaryCeiling: 100,
          ),
        ),
        if (secondaryPoints != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(
                  color: primaryColor,
                  label: showingMuscle
                      ? '% of starting weight'
                      : _weightAxisLabel(allExercisesByName[_selectedOption!]),
                ),
                const SizedBox(width: 20),
                _LegendDot(color: bodyWeightColor, label: 'Body weight'),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _showGraphPicker(
    BuildContext context, {
    required List<String> muscleNames,
    required Map<String, Set<String>> exercisesByMuscleName,
    required List<String> allExerciseNames,
  }) async {
    var query = '';
    final expandedMuscles = <String>{};
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final allLeaf = <String>[
              _kBodyWeightOption,
              for (final m in muscleNames) '$_kMusclePrefix$m',
              ...allExerciseNames,
            ];
            final filtered = query.isEmpty
                ? null
                : allLeaf
                      .where(
                        (o) => _optionLabel(
                          o,
                        ).toLowerCase().contains(query.toLowerCase()),
                      )
                      .toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (sheetContext, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Search',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered != null
                            ? ListView(
                                controller: scrollController,
                                children: [
                                  for (final option in filtered)
                                    ListTile(
                                      leading: option.startsWith(_kMusclePrefix)
                                          ? const Icon(Icons.accessibility_new)
                                          : null,
                                      title: Text(_optionLabel(option)),
                                      onTap: () => Navigator.of(
                                        sheetContext,
                                      ).pop(option),
                                    ),
                                ],
                              )
                            : Builder(
                                builder: (sheetContext) {
                                  final categoryBase = Theme.of(sheetContext)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700);
                                  return ListView(
                                    controller: scrollController,
                                    children: [
                                      ListTile(
                                        tileColor: kBodyWeightColor.withValues(
                                          alpha: 0.15,
                                        ),
                                        title: Text(
                                          _kBodyWeightOption,
                                          style: categoryBase,
                                        ),
                                        onTap: () => Navigator.of(
                                          sheetContext,
                                        ).pop(_kBodyWeightOption),
                                      ),
                                      for (final muscle in muscleNames)
                                        _MuscleGraphTile(
                                          muscle: muscle,
                                          exercises:
                                              exercisesByMuscleName[muscle]!
                                                  .toList()
                                                ..sort(),
                                          expanded: expandedMuscles.contains(
                                            muscle,
                                          ),
                                          titleStyle: categoryBase,
                                          onToggleExpanded: () =>
                                              setSheetState(() {
                                                if (!expandedMuscles.add(
                                                  muscle,
                                                )) {
                                                  expandedMuscles.remove(
                                                    muscle,
                                                  );
                                                }
                                              }),
                                          onSelectMuscle: () => Navigator.of(
                                            sheetContext,
                                          ).pop('$_kMusclePrefix$muscle'),
                                          onSelectExercise: (name) =>
                                              Navigator.of(
                                                sheetContext,
                                              ).pop(name),
                                        ),
                                      const SizedBox(height: 16),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
    if (selected != null) setState(() => _selectedOption = selected);
  }
}

/// A muscle row in the graph picker: tapping the row itself opens that
/// muscle's own aggregate graph; tapping the chevron only expands/collapses
/// the list of that muscle's individual exercises underneath, without
/// opening (or closing) the muscle graph — the two actions are independent.
class _MuscleGraphTile extends StatelessWidget {
  const _MuscleGraphTile({
    required this.muscle,
    required this.exercises,
    required this.expanded,
    required this.titleStyle,
    required this.onToggleExpanded,
    required this.onSelectMuscle,
    required this.onSelectExercise,
  });

  final String muscle;
  final List<String> exercises;
  final bool expanded;
  final TextStyle? titleStyle;
  final VoidCallback onToggleExpanded;
  final VoidCallback onSelectMuscle;
  final ValueChanged<String> onSelectExercise;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: kMuscleColor.withValues(alpha: 0.15),
          child: ListTile(
            leading: const Icon(Icons.accessibility_new),
            title: Text(titleCase(muscle), style: titleStyle),
            trailing: exercises.isEmpty
                ? null
                : IconButton(
                    icon: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    tooltip: expanded
                        ? 'Hide exercises'
                        : 'Show exercises for this muscle',
                    onPressed: onToggleExpanded,
                  ),
            onTap: onSelectMuscle,
          ),
        ),
        if (expanded)
          for (final name in exercises)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 32, right: 16),
              title: Text(name),
              onTap: () => onSelectExercise(name),
            ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
