import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/analysis/tile_trend.dart';
import '../../core/constants/muscle_groups.dart';
import '../../core/constants/sheet_layout.dart';
import '../../core/utils/iso_week.dart';
import '../../core/utils/text.dart';
import '../../models/exercise.dart';
import '../../models/exercise_muscle_info.dart';
import '../../models/history_entry.dart';
import '../../models/set_feedback.dart';
import '../../models/workout_day_def.dart';
import '../../models/workout_visit.dart';
import '../../models/year_sheet_data.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../widgets/exercise_tile.dart';
import '../history/edit_visit_screen.dart';
import 'add_new_exercise_dialog.dart';
import 'last_workout_insight_screen.dart';
import 'rating_screen.dart';

class LogWorkoutScreen extends ConsumerStatefulWidget {
  const LogWorkoutScreen({super.key});

  @override
  ConsumerState<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends ConsumerState<LogWorkoutScreen> {
  WorkoutDayDef? _selectedDay;
  DateTime _selectedDate = DateTime.now();
  final Map<String, ExerciseDraft> _drafts = {};

  /// Checked/selected exercise names, in the order they should end up in
  /// the visit — normally the order they were checked in, but draggable
  /// (via the "Workout so far" summary) once an exercise is complete.
  final List<String> _checked = [];
  final List<Exercise> _addedExercises = [];
  final _noteController = TextEditingController();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  /// The exercise currently shown in "Suggested next" — sticky once
  /// checked-but-not-complete, so ticking it doesn't immediately swap in a
  /// different suggestion and yank the weight/set editor out from under
  /// the user before they've had a chance to fill it in.
  String? _pinnedSuggestionName;

  /// Which checked exercises currently count as "complete" for *display*
  /// purposes (the "Workout so far" summary and "Suggested next" pinning).
  /// Deliberately refreshed only on field blur/toggle, not on every
  /// keystroke — see [_handleFieldBlur]. Publish-time validation in
  /// [_continue] always reads [ExerciseDraft.isComplete] live via
  /// `draft.toEntry()`, never this snapshot, so this is purely
  /// presentational and can't mask an incomplete exercise at publish time.
  final Set<String> _completedSnapshot = {};

  Timer? _saveDraftDebounce;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    _refreshCompletionSnapshot();
  }

  void _refreshCompletionSnapshot() {
    _completedSnapshot
      ..clear()
      ..addAll(ExerciseDraft.completedNamesFrom(_checked, _drafts));
  }

  /// The one point where completing the last field of an exercise is
  /// allowed to restructure the screen — deferring that off the completing
  /// keystroke itself is what removes the keyboard flicker/scroll jump.
  void _handleFieldBlur() {
    _saveDraftDebounce?.cancel();
    _saveDraftDebounce = null;
    setState(_refreshCompletionSnapshot);
    _saveDraft();
  }

  /// Coalesces the draft autosave across a burst of keystrokes instead of a
  /// full JSON-encode + SharedPreferences write on every character.
  void _scheduleSaveDraft() {
    _saveDraftDebounce?.cancel();
    _saveDraftDebounce = Timer(const Duration(milliseconds: 400), () {
      _saveDraftDebounce = null;
      _saveDraft();
    });
  }

  void _restoreDraft() {
    final raw = ref.read(appSettingsServiceProvider).workoutDraftJson;
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final dayId = json['day'] as String?;
      if (dayId != null) {
        // A manual search with a null fallback, not firstWhere/orElse —
        // a custom day referenced by an old draft may have since been
        // deleted in Settings, and that shouldn't discard the rest of an
        // otherwise-valid restored draft (note, checked exercises, etc).
        for (final d in ref.read(workoutDayDefsProvider)) {
          if (d.id == dayId) {
            _selectedDay = d;
            break;
          }
        }
      }

      final dateStr = json['date'] as String?;
      if (dateStr != null) {
        _selectedDate = DateTime.tryParse(dateStr) ?? DateTime.now();
      }

      _noteController.text = json['note'] as String? ?? '';

      _checked.addAll((json['checked'] as List?)?.cast<String>() ?? const []);

      for (final raw in (json['addedExercises'] as List?) ?? const []) {
        final m = raw as Map<String, dynamic>;
        final group = MuscleGroup.values.firstWhere(
          (g) => g.name == m['muscleGroup'],
        );
        _addedExercises.add(
          Exercise(name: m['name'] as String, muscleGroup: group),
        );
      }

      // Hydrated eagerly (not lazily on first build) so every widget that
      // reads `_drafts` on the very first frame — e.g. the "Workout so
      // far" summary — already sees the restored data instead of an empty
      // map that only fills in once something else triggers a rebuild.
      final exercisesJson =
          json['exercises'] as Map<String, dynamic>? ?? const {};
      for (final entry in exercisesJson.entries) {
        final data = entry.value as Map<String, dynamic>;
        final group = MuscleGroup.values.firstWhere(
          (g) => g.name == data['muscleGroup'],
        );
        final draft = ExerciseDraft(
          Exercise(name: entry.key, muscleGroup: group),
        );
        draft.loadSets(
          weights: (data['setWeights'] as List)
              .map((w) => (w as num?)?.toDouble())
              .toList(),
          reps:
              (data['setReps'] as List?)
                  ?.map((r) => (r as num?)?.toInt())
                  .toList() ??
              List<int?>.filled(
                (data['setWeights'] as List).length,
                null,
                growable: true,
              ),
          approxReps: (data['setApproxReps'] as List?)?.cast<bool>(),
          setFeedback: (data['setFeedback'] as List?)
              ?.map((f) => setFeedbackFromJson(f as String?))
              .toList(),
        );
        _drafts[entry.key] = draft;
      }
    } catch (_) {
      // Corrupt/old-format draft — ignore and start fresh.
    }
  }

  Map<String, dynamic> _draftToJson() => {
    'day': _selectedDay?.id,
    'date': _selectedDate.toIso8601String(),
    'note': _noteController.text,
    'checked': _checked.toList(),
    'addedExercises': [
      for (final e in _addedExercises)
        {'name': e.name, 'muscleGroup': e.muscleGroup.name},
    ],
    'exercises': {
      for (final entry in _drafts.entries)
        entry.key: {
          'muscleGroup': entry.value.exercise.muscleGroup.name,
          'setWeights': entry.value.setWeights,
          'setReps': entry.value.setReps,
          'setApproxReps': entry.value.setApproxReps,
          'setFeedback': [for (final f in entry.value.setFeedback) f.name],
        },
    },
  };

  bool get _hasDraftContent =>
      _selectedDay != null ||
      _checked.isNotEmpty ||
      _noteController.text.trim().isNotEmpty ||
      _addedExercises.isNotEmpty;

  /// Persists (or, if the log is now empty, clears) the single draft.
  /// Called after every change so nothing is lost leaving this screen
  /// before publishing.
  void _saveDraft() {
    final service = ref.read(appSettingsServiceProvider);
    if (!_hasDraftContent) {
      service.clearWorkoutDraft();
    } else {
      service.setWorkoutDraft(jsonEncode(_draftToJson()));
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this log?'),
        content: const Text(
          "This discards everything you've entered so far. This cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _saveDraftDebounce?.cancel();
    _saveDraftDebounce = null;
    setState(() {
      _selectedDay = null;
      _selectedDate = DateTime.now();
      for (final draft in _drafts.values) {
        draft.dispose();
      }
      _drafts.clear();
      _checked.clear();
      _addedExercises.clear();
      _pinnedSuggestionName = null;
      _completedSnapshot.clear();
      _noteController.clear();
      _searchController.clear();
      _searchQuery = '';
    });
    await ref.read(appSettingsServiceProvider).clearWorkoutDraft();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    _saveDraft();
  }

  void _selectDay(WorkoutDayDef d) {
    setState(() {
      _selectedDay = d;
      _pinnedSuggestionName = null;
    });
    _saveDraft();
  }

  /// Up to the last 2 visits for [day] (most-recent first) — the window
  /// "usual" patterns (starter exercise, what follows X, common exercises)
  /// are computed over. Kept deliberately short so the suggestion tracks
  /// your actual current order (what you did last time, or the time before)
  /// instead of being diluted/outvoted by an older order from further back.
  /// Works for any day (legacy-linked or a fully custom muscle set) via
  /// [historyEntryBelongsToDay].
  List<HistoryEntry> _recentVisitsFor(WorkoutDayDef day) {
    final snapshot = ref.read(snapshotProvider).value?.snapshot;
    if (snapshot == null) return const [];
    final yearsAscending = snapshot.yearData.values.toList()
      ..sort((a, b) => a.year.compareTo(b.year));
    final dayDefs = ref.read(workoutDayDefsProvider);
    return buildHistoryEntries(yearsAscending, workoutDays: dayDefs)
        .where((e) => historyEntryBelongsToDay(e, day))
        .take(2)
        .toList();
  }

  /// The most frequent name in [names]; ties broken by whichever occurs in
  /// the most recent of [recentVisitsMostRecentFirst].
  String? _modeOfNames(
    List<String> names,
    List<HistoryEntry> recentVisitsMostRecentFirst,
  ) {
    if (names.isEmpty) return null;
    final counts = <String, int>{};
    for (final n in names) {
      counts[n] = (counts[n] ?? 0) + 1;
    }
    final maxCount = counts.values.reduce((a, b) => a > b ? a : b);
    final candidates = counts.entries
        .where((e) => e.value == maxCount)
        .map((e) => e.key)
        .toSet();
    if (candidates.length == 1) return candidates.first;
    for (final visit in recentVisitsMostRecentFirst) {
      for (final name in visit.exerciseNames) {
        if (candidates.contains(name)) return name;
      }
    }
    return candidates.first;
  }

  /// Tiered "what should I log next for [day]" recommendation:
  ///  1. Nothing completed yet this session -> the exercise usually
  ///     started with.
  ///  2. Otherwise -> whatever usually follows the last *completed*
  ///     exercise, if that pattern exists.
  ///  3. Otherwise -> any other exercise commonly done for this day that
  ///     isn't checked yet.
  /// Returns null if recent history has nothing usable (caller falls back
  /// to the first not-yet-checked exercise in that case).
  String? _suggestedNextExerciseName(WorkoutDayDef day) {
    final recentVisits = _recentVisitsFor(day);
    if (recentVisits.isEmpty) return null;

    final completedNames = _checked
        .where(_completedSnapshot.contains)
        .toList();

    if (completedNames.isEmpty) {
      final starters = [
        for (final v in recentVisits)
          if (v.exerciseNames.isNotEmpty) v.exerciseNames.first,
      ];
      final starter = _modeOfNames(starters, recentVisits);
      if (starter != null && !_checked.contains(starter)) return starter;
    }

    if (completedNames.isNotEmpty) {
      final lastDone = completedNames.last;
      final successors = <String>[];
      for (final v in recentVisits) {
        final idx = v.exerciseNames.indexOf(lastDone);
        if (idx != -1 && idx + 1 < v.exerciseNames.length) {
          successors.add(v.exerciseNames[idx + 1]);
        }
      }
      final successor = _modeOfNames(successors, recentVisits);
      if (successor != null && !_checked.contains(successor)) return successor;
    }

    final allNames = [
      for (final v in recentVisits) ...v.exerciseNames,
    ].where((n) => !_checked.contains(n)).toList();
    return _modeOfNames(allNames, recentVisits);
  }

  /// Last-resort fallback when recent history gives no usable pattern
  /// (brand new day, or everything it suggests is already checked): the
  /// first not-yet-checked exercise, in the same muscle-then-name order
  /// the checklist itself renders in.
  String? _fallbackFirstUnchecked(
    List<Exercise> availableExercises,
    Map<String, ExerciseMuscleInfo> muscleByName,
  ) {
    final sorted = List<Exercise>.of(availableExercises)
      ..sort((a, b) {
        final ma =
            muscleByName[a.name.toLowerCase()]?.muscleGroup.sheetHeader ??
            a.muscleGroup.sheetHeader;
        final mb =
            muscleByName[b.name.toLowerCase()]?.muscleGroup.sheetHeader ??
            b.muscleGroup.sheetHeader;
        final cmp = ma.toLowerCase().compareTo(mb.toLowerCase());
        return cmp != 0 ? cmp : a.name.compareTo(b.name);
      });
    for (final e in sorted) {
      if (!_checked.contains(e.name)) return e.name;
    }
    return null;
  }

  Exercise? _findByName(List<Exercise> exercises, String name) {
    for (final e in exercises) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// The name to show in "Suggested next" this build: keeps showing the
  /// currently-pinned exercise as long as it's checked but not yet
  /// complete (so its weight/set editor doesn't disappear mid-entry),
  /// otherwise computes a fresh recommendation and pins that instead.
  String? _resolveSuggestion(
    WorkoutDayDef day,
    List<Exercise> availableExercises,
    Map<String, ExerciseMuscleInfo> muscleByName,
  ) {
    final pinned = _pinnedSuggestionName;
    if (pinned != null &&
        _checked.contains(pinned) &&
        !_completedSnapshot.contains(pinned)) {
      return pinned;
    }
    final fresh =
        _suggestedNextExerciseName(day) ??
        _fallbackFirstUnchecked(availableExercises, muscleByName);
    _pinnedSuggestionName = fresh;
    return fresh;
  }

  /// Reorders only the *completed* exercises (shown in the "Workout so
  /// far" summary) relative to each other, leaving not-yet-completed
  /// checked exercises pinned at their existing spots in [_checked].
  void _reorderCompleted(int oldIndex, int newIndex) {
    final completedSet = Set<String>.of(_completedSnapshot);
    final completedNames = _checked.where(completedSet.contains).toList();
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = completedNames.removeAt(oldIndex);
    completedNames.insert(newIndex, moved);

    final reordered = <String>[];
    var i = 0;
    for (final name in _checked) {
      if (completedSet.contains(name)) {
        reordered.add(completedNames[i]);
        i++;
      } else {
        reordered.add(name);
      }
    }
    setState(() {
      _checked
        ..clear()
        ..addAll(reordered);
    });
    _saveDraft();
  }

  ExerciseDraft _draftFor(Exercise exercise, List<YearSheetData> yearsAscending) =>
      _drafts.putIfAbsent(exercise.name, () {
        final defaults = ref.read(workoutDefaultsProvider);
        final historicalSetCount = historicalAverageSetCount(
          yearsAscending: yearsAscending,
          exerciseName: exercise.name,
        );
        return ExerciseDraft(
          exercise,
          setCount: historicalSetCount ?? kDefaultSetCount,
          repRangeLow: defaults.repRangeLow,
          repRangeHigh: defaults.repRangeHigh,
        );
      });

  double? _previousWeightFor(
    String exerciseName,
    List<YearSheetData> yearsAscending,
  ) {
    final history = buildExerciseHistory(
      yearsAscending: yearsAscending,
      exerciseName: exerciseName,
    );
    return history.isEmpty ? null : history.last.avgWeight;
  }

  @override
  void dispose() {
    if (_saveDraftDebounce != null) {
      _saveDraftDebounce!.cancel();
      _saveDraft();
    }
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    _noteController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yearData = ref.watch(currentYearDataProvider);
    final muscleByName = ref.watch(exerciseMuscleByNameProvider);
    final exerciseMuscleInfo = ref.watch(exerciseMuscleInfoProvider);
    final snapshotState = ref.watch(snapshotProvider).value;
    final yearsAscending = snapshotState?.snapshot.yearData.values.toList()
      ?..sort((a, b) => a.year.compareTo(b.year));
    final day = _selectedDay;
    final groups = day?.muscleGroups ?? const <MuscleGroup>[];
    final dayDefs = ref.watch(workoutDayDefsProvider);

    final selectedCount = _checked.length;

    final availableExercises = day == null
        ? const <Exercise>[]
        : _exercisesForDay(yearData, groups, exerciseMuscleInfo);
    final suggestedNextName = day == null
        ? null
        : _resolveSuggestion(day, availableExercises, muscleByName);
    final suggestedExercise = suggestedNextName == null
        ? null
        : _findByName(availableExercises, suggestedNextName);
    final completedNames = _checked
        .where(_completedSnapshot.contains)
        .toList();

    // Computed once per build (not per tile) — the trend stripe on each
    // ExerciseTile. Reuses analyzeExercises, the same batch analysis entry
    // point the post-save/last-workout insight screens already use.
    final trendByName = <String, TileTrend>{
      for (final f in analyzeExercises(
        yearsAscending: yearsAscending ?? const <YearSheetData>[],
        exerciseNames: [for (final e in availableExercises) e.name],
        bodyWeightEntries: ref.watch(bodyWeightEntriesProvider),
      ))
        f.subjectName: classifyTrend(f),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Log workout')),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  key: const ValueKey('sliver_day_chips'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final d in dayDefs) ...[
                            SizedBox(
                              width: 84,
                              child: _DayChip(
                                day: d,
                                selected: day?.id == d.id,
                                onTap: () => _selectDay(d),
                              ),
                            ),
                            if (d != dayDefs.last) const SizedBox(width: 10),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (day != null && completedNames.isNotEmpty)
                  SliverToBoxAdapter(
                    key: const ValueKey('sliver_completed_summary'),
                    child: _CompletedSummary(
                      names: completedNames,
                      drafts: _drafts,
                      onReorder: _reorderCompleted,
                      onChanged: () {
                        setState(() {});
                        _scheduleSaveDraft();
                      },
                      onFocusLost: _handleFieldBlur,
                    ),
                  ),
                if (day != null)
                  SliverToBoxAdapter(
                    key: const ValueKey('sliver_day_controls'),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(
                                DateUtils.isSameDay(_selectedDate, DateTime.now())
                                    ? 'Today'
                                    : '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                              ),
                              onPressed: _pickDate,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('Add new exercise'),
                                onPressed: () async {
                                  final result = await showAddNewExerciseDialog(
                                    context,
                                    muscleGroupOptions: day.muscleGroups,
                                    allMuscleInfo: muscleByName.values.toList(),
                                  );
                                  if (result == null) return;
                                  setState(
                                    () => _addedExercises.add(result.exercise),
                                  );
                                  _saveDraft();

                                  final columnIndex = result.muscleColumnIndex;
                                  if (columnIndex != null) {
                                    final ok = await ref
                                        .read(snapshotProvider.notifier)
                                        .addExerciseMuscle(
                                          exerciseName: result.exercise.name,
                                          columnIndex: columnIndex,
                                        );
                                    if (!ok && context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not save the muscle to your sheet — added locally only.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                              const Spacer(),
                              TextButton.icon(
                                icon: const Icon(Icons.insights_outlined),
                                label: Text('Last ${day.label} day'),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        LastWorkoutInsightScreen(day: day),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: TextField(
                            controller: _noteController,
                            decoration: const InputDecoration(
                              labelText: 'Note (optional)',
                              hintText: 'e.g. felt tired, gym was crowded...',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => _saveDraft(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              labelText: 'Search exercises',
                              isDense: true,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    ),
                            ),
                            onChanged: (v) => setState(
                              () => _searchQuery = v.trim().toLowerCase(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (day == null)
                  const SliverFillRemaining(
                    key: ValueKey('sliver_empty_state'),
                    child: Center(
                      child: Text('Pick a day to start.'),
                    ),
                  )
                else
                  SliverPadding(
                    key: const ValueKey('sliver_exercise_list'),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (suggestedExercise != null)
                          _buildMuscleSection(
                            context,
                            'Suggested next',
                            [suggestedExercise],
                            yearsAscending ?? const <YearSheetData>[],
                            trendByName,
                            sectionKey: const ValueKey('section_suggested'),
                          ),
                        ..._buildMuscleSections(
                          context,
                          availableExercises,
                          muscleByName,
                          yearsAscending ?? const <YearSheetData>[],
                          trendByName,
                          // Already shown above under "Suggested next" — don't
                          // also render it here, so the list's shape doesn't
                          // change out from under the user the moment a
                          // keystroke completes it and the suggestion moves on.
                          excludeName: suggestedExercise?.name,
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: _hasDraftContent ? _confirmClear : null,
                    child: const Text('Clear log'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: selectedCount == 0 ? null : _continue,
                      child: Text('Publish log ($selectedCount)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// All of the selected day's exercises (sheet-known + custom-added +
  /// muscle-tagged extras from other days), not yet filtered by search.
  /// Also pulls in exercises whose muscle (per the Exercises tab) is
  /// shared with another day — e.g. "Abdominals" listed under both Push
  /// and Legs — so an exercise like Crunches can be logged from either
  /// day and still accumulate into the same weight history/graph, even
  /// though its own matrix section only lives under one [MuscleGroup].
  List<Exercise> _exercisesForDay(
    YearSheetData? yearData,
    List<MuscleGroup> groups,
    List<ExerciseMuscleInfo> exerciseMuscleInfo,
  ) {
    final exercises = <Exercise>[
      for (final group in groups) ...?yearData?.muscleGroupSections[group],
    ];
    final existingNames = exercises.map((e) => e.name.toLowerCase()).toSet();
    for (final added in _addedExercises) {
      if (!groups.contains(added.muscleGroup)) continue;
      if (existingNames.contains(added.name.toLowerCase())) continue;
      exercises.add(added);
      existingNames.add(added.name.toLowerCase());
    }

    // Bonus inclusion: any exercise whose muscle (per the Exercises tab) is
    // one of this day's muscle groups, even if the matrix tab itself hasn't
    // filed it under the same group yet (e.g. newly added but not yet
    // logged) — works uniformly for built-in and custom days alike now
    // that a day's muscle groups and the Exercises tab share one taxonomy.
    for (final info in exerciseMuscleInfo) {
      if (!groups.contains(info.muscleGroup)) continue;
      if (existingNames.contains(info.exerciseName.toLowerCase())) continue;
      final exercise = yearData?.findExercise(info.exerciseName);
      if (exercise == null) continue;
      exercises.add(exercise);
      existingNames.add(info.exerciseName.toLowerCase());
    }
    return exercises;
  }

  /// Groups [exercises] by muscle (from the "Exercises" reference tab when
  /// known — falling back to the broader matrix-tab [MuscleGroup] for
  /// exercises not yet listed there), sorted alphabetically by muscle
  /// name, and applies the current search filter.
  List<Widget> _buildMuscleSections(
    BuildContext context,
    List<Exercise> exercises,
    Map<String, ExerciseMuscleInfo> muscleByName,
    List<YearSheetData> yearsAscending,
    Map<String, TileTrend> trendByName, {
    String? excludeName,
  }) {
    final filtered = exercises.where(
      (e) =>
          (_searchQuery.isEmpty ||
              e.name.toLowerCase().contains(_searchQuery)) &&
          e.name != excludeName,
    );

    final byMuscle = <String, List<Exercise>>{};
    for (final exercise in filtered) {
      final muscle =
          muscleByName[exercise.name.toLowerCase()]?.muscleGroup.sheetHeader ??
          exercise.muscleGroup.sheetHeader;
      byMuscle.putIfAbsent(muscle, () => []).add(exercise);
    }
    final muscleNames = byMuscle.keys.toList()..sort();

    return [
      for (final muscle in muscleNames)
        _buildMuscleSection(
          context,
          muscle,
          byMuscle[muscle]!,
          yearsAscending,
          trendByName,
          sectionKey: ValueKey('section_$muscle'),
        ),
    ];
  }

  Widget _buildMuscleSection(
    BuildContext context,
    String muscle,
    List<Exercise> exercises,
    List<YearSheetData> yearsAscending,
    Map<String, TileTrend> trendByName, {
    Key? sectionKey,
  }) {
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            titleCase(muscle),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        for (final exercise in exercises)
          ExerciseTile(
            // GlobalObjectKey (not ValueKey): when this exercise is pinned
            // as "Suggested next" and unpins itself mid-keystroke (see
            // _resolveSuggestion), it moves to a different Column next
            // build. A plain key can't follow an Element across parents, so
            // it gets disposed/reinflated, dropping focus and cutting off
            // the keystroke. Safe as a GlobalKey since _buildMuscleSections
            // already excludes the pinned exercise from the normal list.
            key: GlobalObjectKey(exercise.name),
            draft: _draftFor(exercise, yearsAscending),
            previousWeight: _previousWeightFor(exercise.name, yearsAscending),
            trend: trendByName[exercise.name] ?? TileTrend.unknown,
            selected: _checked.contains(exercise.name),
            onToggle: (v) {
              setState(() {
                if (v) {
                  if (!_checked.contains(exercise.name))
                    _checked.add(exercise.name);
                } else {
                  _checked.remove(exercise.name);
                }
                _refreshCompletionSnapshot();
              });
              _saveDraft();
            },
            onChanged: () {
              setState(() {});
              _scheduleSaveDraft();
            },
            onFocusLost: _handleFieldBlur,
          ),
      ],
    );
  }

  /// The already-logged visit on [_selectedDate], if any — used to enforce
  /// one workout per calendar day rather than letting a second visit the
  /// same day quietly coexist (which is exactly what produced the
  /// cross-day contamination this app used to have).
  MetaRow? _existingVisitOnSelectedDate() {
    final snapshot = ref.read(snapshotProvider).value?.snapshot;
    final year = snapshot?.yearData[isoWeekYear(_selectedDate)];
    for (final m in year?.metaRows ?? const <MetaRow>[]) {
      if (DateUtils.isSameDay(m.date, _selectedDate)) return m;
    }
    return null;
  }

  Future<void> _showAlreadyLoggedDialog(MetaRow existing) async {
    final formattedDate =
        '${existing.date.year}-${existing.date.month.toString().padLeft(2, '0')}-'
        '${existing.date.day.toString().padLeft(2, '0')}';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Already logged that day'),
        content: Text(
          "You've already logged a workout on $formattedDate. Log only "
          'one workout per day — edit that visit instead, or pick a '
          'different date.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditVisitScreen(
                    metaRow: existing,
                    initialNote: existing.note,
                  ),
                ),
              );
            },
            child: const Text('Edit that visit'),
          ),
        ],
      ),
    );
  }

  void _continue() {
    final existingVisit = _existingVisitOnSelectedDate();
    if (existingVisit != null) {
      _showAlreadyLoggedDialog(existingVisit);
      return;
    }

    final entries = <ExerciseEntry>[];
    for (final name in _checked) {
      final draft = _drafts[name];
      final entry = draft?.toEntry();
      if (entry == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fill in all set weights for $name.')),
        );
        return;
      }
      entries.add(entry);
    }
    if (entries.isEmpty) return;

    final date = _selectedDate;
    final note = _noteController.text.trim();
    final visit = WorkoutVisit(
      visitId: const Uuid().v4(),
      date: date,
      isoWeek: isoWeekNumber(date),
      isoYear: isoWeekYear(date),
      entries: entries,
      note: note.isEmpty ? null : note,
      workoutDayId: _selectedDay?.id,
    );

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RatingScreen(visit: visit)));
  }
}

/// "Workout so far": a live, reorderable summary of exercises that are
/// fully filled in, shown at the top of the page so the final result is
/// visible without scrolling through the muscle-grouped checklist below.
class _CompletedSummary extends StatelessWidget {
  const _CompletedSummary({
    required this.names,
    required this.drafts,
    required this.onReorder,
    required this.onChanged,
    this.onFocusLost,
  });

  final List<String> names;
  final Map<String, ExerciseDraft> drafts;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onChanged;
  final VoidCallback? onFocusLost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Workout so far — tap an exercise to edit',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: onReorder,
            children: [
              for (var i = 0; i < names.length; i++)
                _CompletedRow(
                  key: ValueKey(names[i]),
                  index: i,
                  name: names[i],
                  draft: drafts[names[i]]!,
                  onChanged: onChanged,
                  onFocusLost: onFocusLost,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompletedRow extends StatefulWidget {
  const _CompletedRow({
    super.key,
    required this.index,
    required this.name,
    required this.draft,
    required this.onChanged,
    this.onFocusLost,
  });

  final int index;
  final String name;
  final ExerciseDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onFocusLost;

  @override
  State<_CompletedRow> createState() => _CompletedRowState();
}

class _CompletedRowState extends State<_CompletedRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final setsSummary = [
      for (var i = 0; i < draft.setWeights.length; i++)
        '${draft.setWeights[i]!.toStringAsFixed(1)}×'
            '${draft.setApproxReps[i] ? '~' : ''}${draft.repsFor(i)}',
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: Icon(
                      Icons.drag_handle,
                      size: 18,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$setsSummary kg',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 8),
              child: SetsEditor(
                draft: draft,
                onChanged: widget.onChanged,
                onFocusLost: widget.onFocusLost,
              ),
            ),
        ],
      ),
    );
  }
}

const Map<WorkoutDay, List<Color>> _kDayColors = {
  WorkoutDay.push: [Color(0xFFFF8A5B), Color(0xFFFF5E7E)],
  WorkoutDay.pull: [Color(0xFF4FACFE), Color(0xFF3E7BFA)],
  WorkoutDay.legs: [Color(0xFF6DD5A8), Color(0xFF3FB68A)],
};

const Map<WorkoutDay, IconData> _kDayIcons = {
  WorkoutDay.push: Icons.arrow_upward_rounded,
  WorkoutDay.pull: Icons.arrow_downward_rounded,
  WorkoutDay.legs: Icons.directions_walk_rounded,
};

const List<Color> _kFullBodyColors = [Color(0xFFB08347), Color(0xFFC99A5B)];

/// Colors for Full Body/custom days, which have no fixed entry in
/// [_kDayColors]: Full Body gets a fixed gold look, and a custom day gets a
/// deterministic hue derived from its id, so no extra color-picker UI is
/// needed when creating one.
List<Color> _colorsForDay(WorkoutDayDef d) {
  final legacy = d.legacyDay;
  if (legacy != null) return _kDayColors[legacy]!;
  if (d.isFullBody) return _kFullBodyColors;
  final hue = (d.id.hashCode % 360).abs().toDouble();
  return [
    HSLColor.fromAHSL(1, hue, 0.55, 0.55).toColor(),
    HSLColor.fromAHSL(1, hue, 0.55, 0.4).toColor(),
  ];
}

IconData _iconForDay(WorkoutDayDef d) {
  final legacy = d.legacyDay;
  if (legacy != null) return _kDayIcons[legacy]!;
  if (d.isFullBody) return Icons.all_inclusive;
  return Icons.fitness_center;
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final WorkoutDayDef day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsForDay(day);
    return Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected
                ? null
                : Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Column(
            children: [
              Icon(
                _iconForDay(day),
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                day.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
