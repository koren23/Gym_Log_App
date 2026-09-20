import 'package:flutter/material.dart';

import '../core/analysis/tile_trend.dart';
import '../core/constants/semantic_colors.dart';
import '../core/constants/sheet_layout.dart';
import '../core/utils/exercise_value_format.dart';
import '../models/analysis_result.dart';
import '../models/exercise.dart';
import '../models/exercise_unit.dart';
import '../models/pending_suggestion.dart';
import '../models/set_feedback.dart';
import '../models/workout_visit.dart';

/// Mutable per-exercise editing state used while building up a workout
/// visit in the log-workout flow. Owns the [TextEditingController]s for
/// its own set fields so the same draft can be edited from more than one
/// place on screen (the checklist tile and the "Workout so far" summary)
/// and stay in sync, and so a value the user already typed survives
/// unrelated rebuilds instead of appearing blank.
class ExerciseDraft {
  ExerciseDraft(
    this.exercise, {
    int setCount = kDefaultSetCount,
    int repRangeLow = kDefaultRepRangeLow,
    int repRangeHigh = kDefaultRepRangeHigh,
  }) : _repsMid = (repRangeLow + repRangeHigh) ~/ 2,
       setWeights = List<double?>.filled(setCount, null, growable: true),
       setReps = List<int?>.filled(setCount, null, growable: true),
       setApproxReps = List<bool>.filled(setCount, false, growable: true),
       setFeedback = List<SetFeedback>.filled(
         setCount,
         SetFeedback.none,
         growable: true,
       ),
       targetRepRangeLowOverridePerSet = List<int?>.filled(
         setCount,
         null,
         growable: true,
       ),
       targetRepRangeHighOverridePerSet = List<int?>.filled(
         setCount,
         null,
         growable: true,
       ),
       targetWeightOverridePerSet = List<double?>.filled(
         setCount,
         null,
         growable: true,
       ),
       weightControllers = List.generate(
         setCount,
         (_) => TextEditingController(),
         growable: true,
       ),
       repsControllers = List.generate(
         setCount,
         (_) => TextEditingController(),
         growable: true,
       );

  final Exercise exercise;
  final int _repsMid;
  List<double?> setWeights;
  List<int?> setReps;
  List<bool> setApproxReps;
  List<SetFeedback> setFeedback;

  /// Per-set target overrides from an accepted suggestion (see
  /// `SuggestionKind.changeRepRangeForSet`/`changeRepRangeOverall`/
  /// `changeWeightForSet`) — null where no override applies, in which case
  /// [repsFor] falls back to the plain historical hint.
  List<int?> targetRepRangeLowOverridePerSet;
  List<int?> targetRepRangeHighOverridePerSet;
  List<double?> targetWeightOverridePerSet;
  final List<TextEditingController> weightControllers;
  final List<TextEditingController> repsControllers;

  bool get isComplete => setWeights.every(
    (w) => w != null && (w > 0 || (w == 0 && exercise.unit.allowsZeroAsRealValue)),
  );

  int repsFor(int index) {
    if (setReps[index] != null) return setReps[index]!;
    final lo = index < targetRepRangeLowOverridePerSet.length
        ? targetRepRangeLowOverridePerSet[index]
        : null;
    final hi = index < targetRepRangeHighOverridePerSet.length
        ? targetRepRangeHighOverridePerSet[index]
        : null;
    if (lo != null && hi != null) return (lo + hi) ~/ 2;
    return _repsMid;
  }

  /// True when [index] has a target from an accepted suggestion, distinct
  /// from the plain global-default hint — used to show a small badge.
  bool hasSuggestedTarget(int index) =>
      (index < targetRepRangeLowOverridePerSet.length &&
          targetRepRangeLowOverridePerSet[index] != null) ||
      (index < targetWeightOverridePerSet.length &&
          targetWeightOverridePerSet[index] != null);

  /// Applies an accepted [suggestion] into this draft's fields — pre-filling
  /// a specific set's target reps/weight (or, for exercise-wide kinds,
  /// every set), so the next time this exercise is logged the change is
  /// already reflected instead of just remembered as text.
  void applyPendingSuggestion(PendingSuggestion suggestion) {
    switch (suggestion.kind) {
      case SuggestionKind.changeRepRangeForSet:
        final i = suggestion.setIndex;
        if (i != null && i < targetRepRangeLowOverridePerSet.length) {
          targetRepRangeLowOverridePerSet[i] = suggestion.newRepRangeLow;
          targetRepRangeHighOverridePerSet[i] = suggestion.newRepRangeHigh;
        }
      case SuggestionKind.changeRepRangeOverall:
        for (var i = 0; i < targetRepRangeLowOverridePerSet.length; i++) {
          targetRepRangeLowOverridePerSet[i] = suggestion.newRepRangeLow;
          targetRepRangeHighOverridePerSet[i] = suggestion.newRepRangeHigh;
        }
      case SuggestionKind.changeWeightForSet:
        final i = suggestion.setIndex;
        if (i != null &&
            i < weightControllers.length &&
            suggestion.newWeight != null) {
          setWeights[i] = suggestion.newWeight;
          weightControllers[i].text = suggestion.newWeight!.toStringAsFixed(1);
          targetWeightOverridePerSet[i] = suggestion.newWeight;
        }
      case SuggestionKind.changeTotalWeight:
      case SuggestionKind.deload:
        if (suggestion.newWeight != null) {
          for (var i = 0; i < weightControllers.length; i++) {
            setWeights[i] = suggestion.newWeight;
            weightControllers[i].text = suggestion.newWeight!.toStringAsFixed(
              1,
            );
            targetWeightOverridePerSet[i] = suggestion.newWeight;
          }
        }
      case SuggestionKind.changeExercise:
      case SuggestionKind.changeWorkoutDay:
      case SuggestionKind.none:
        break;
    }
  }

  /// Names from [checked], in order, whose draft in [drafts] is complete —
  /// the pure rule behind the "Workout so far" / suggestion-pinning filter.
  static List<String> completedNamesFrom(
    List<String> checked,
    Map<String, ExerciseDraft> drafts,
  ) => checked.where((n) => drafts[n]?.isComplete == true).toList();

  void addSet() {
    setWeights.add(null);
    setReps.add(null);
    setApproxReps.add(false);
    setFeedback.add(SetFeedback.none);
    targetRepRangeLowOverridePerSet.add(null);
    targetRepRangeHighOverridePerSet.add(null);
    targetWeightOverridePerSet.add(null);
    weightControllers.add(TextEditingController());
    repsControllers.add(TextEditingController());
  }

  void removeLastSet() {
    if (setWeights.length <= 1) return;
    setWeights.removeLast();
    setReps.removeLast();
    setApproxReps.removeLast();
    setFeedback.removeLast();
    targetRepRangeLowOverridePerSet.removeLast();
    targetRepRangeHighOverridePerSet.removeLast();
    targetWeightOverridePerSet.removeLast();
    weightControllers.removeLast().dispose();
    repsControllers.removeLast().dispose();
  }

  /// Replaces all set data (used when applying a persisted/restored draft),
  /// rebuilding the controllers so their displayed text matches.
  void loadSets({
    required List<double?> weights,
    required List<int?> reps,
    List<bool>? approxReps,
    List<SetFeedback>? setFeedback,
  }) {
    for (final c in weightControllers) {
      c.dispose();
    }
    for (final c in repsControllers) {
      c.dispose();
    }
    setWeights = weights;
    setReps = reps;
    setApproxReps =
        approxReps ?? List<bool>.filled(weights.length, false, growable: true);
    this.setFeedback =
        setFeedback ??
        List<SetFeedback>.filled(weights.length, SetFeedback.none, growable: true);
    targetRepRangeLowOverridePerSet = List<int?>.filled(
      weights.length,
      null,
      growable: true,
    );
    targetRepRangeHighOverridePerSet = List<int?>.filled(
      weights.length,
      null,
      growable: true,
    );
    targetWeightOverridePerSet = List<double?>.filled(
      weights.length,
      null,
      growable: true,
    );
    weightControllers
      ..clear()
      ..addAll([
        for (final w in weights)
          TextEditingController(text: w?.toString() ?? ''),
      ]);
    repsControllers
      ..clear()
      ..addAll([
        for (final r in reps) TextEditingController(text: r?.toString() ?? ''),
      ]);
  }

  void dispose() {
    for (final c in weightControllers) {
      c.dispose();
    }
    for (final c in repsControllers) {
      c.dispose();
    }
  }

  ExerciseEntry? toEntry() {
    if (!isComplete) return null;
    final sets = [
      for (var i = 0; i < setWeights.length; i++)
        SetEntry(
          weight: setWeights[i]!,
          reps: repsFor(i),
          approxReps: setApproxReps[i],
          feedback: setFeedback[i],
        ),
    ];
    final repsUsed = sets.map((s) => s.reps).toList();
    return ExerciseEntry(
      exercise: exercise,
      sets: sets,
      targetRepRangeLow: repsUsed.reduce((a, b) => a < b ? a : b),
      targetRepRangeHigh: repsUsed.reduce((a, b) => a > b ? a : b),
      targetRepRangeLowPerSet: List<int?>.from(targetRepRangeLowOverridePerSet),
      targetRepRangeHighPerSet: List<int?>.from(
        targetRepRangeHighOverridePerSet,
      ),
      targetWeightPerSet: List<double?>.from(targetWeightOverridePerSet),
    );
  }
}

/// A checkable exercise row that expands into a set-entry editor when
/// selected.
class ExerciseTile extends StatelessWidget {
  const ExerciseTile({
    super.key,
    required this.draft,
    required this.selected,
    required this.onToggle,
    required this.onChanged,
    this.onFocusLost,
    this.previousWeight,
    this.trend = TileTrend.unknown,
  });

  final ExerciseDraft draft;
  final bool selected;
  final ValueChanged<bool> onToggle;
  final VoidCallback onChanged;

  /// Fired when a set field in this tile loses focus (not on every
  /// keystroke) — used to defer UI reflow (e.g. "Workout so far" updating)
  /// until the user is done typing, instead of on the completing keystroke.
  final VoidCallback? onFocusLost;

  /// Most recently logged average weight for this exercise, if any —
  /// shown as a subtitle so the user can tell what they lifted last time
  /// before entering today's weights.
  final double? previousWeight;

  /// Recent improving/stuck/steady classification for this exercise, shown
  /// as a colored left-border stripe. [TileTrend.unknown] (new exercise, or
  /// not enough history yet) renders with no stripe at all.
  final TileTrend trend;

  @override
  Widget build(BuildContext context) {
    final colors = semanticTrendColors(
      Theme.of(context).scaffoldBackgroundColor,
    );
    final stripeColor = switch (trend) {
      TileTrend.improving => colors.improving,
      TileTrend.stuck => colors.stuck,
      TileTrend.steady => colors.steady,
      TileTrend.unknown => Colors.transparent,
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: stripeColor, width: 4)),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            CheckboxListTile(
              title: Text(draft.exercise.name),
              subtitle: previousWeight == null
                  ? null
                  : Text(
                      'Last time: ${formatExerciseValue(draft.exercise.unit, previousWeight!, customLabel: draft.exercise.customUnitLabel)}',
                    ),
              value: selected,
              onChanged: (v) => onToggle(v ?? false),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SetsEditor(
                  draft: draft,
                  onChanged: onChanged,
                  onFocusLost: onFocusLost,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The add/remove-set controls plus the per-set weight/reps/approx field
/// grid for [draft] — shared by the log-workout exercise editor, the
/// "Workout so far" inline editor, and the edit-visit screen.
class SetsEditor extends StatelessWidget {
  const SetsEditor({
    super.key,
    required this.draft,
    required this.onChanged,
    this.onFocusLost,
  });

  final ExerciseDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onFocusLost;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Sets: ${draft.setWeights.length}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Remove set',
              onPressed: draft.setWeights.length <= 1
                  ? null
                  : () {
                      draft.removeLastSet();
                      onChanged();
                    },
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Add set',
              onPressed: () {
                draft.addSet();
                onChanged();
              },
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < draft.setWeights.length; i++)
              _SetEditorRow(
                key: ValueKey('${draft.exercise.name}_set_$i'),
                setIndex: i,
                draft: draft,
                onChanged: onChanged,
                onFocusLost: onFocusLost,
              ),
          ],
        ),
        if (draft.isComplete)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Average: ${formatExerciseValue(draft.exercise.unit, draft.toEntry()!.averageWeight, customLabel: draft.exercise.customUnitLabel)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _SetEditorRow extends StatefulWidget {
  const _SetEditorRow({
    super.key,
    required this.setIndex,
    required this.draft,
    required this.onChanged,
    this.onFocusLost,
  });

  final int setIndex;
  final ExerciseDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onFocusLost;

  @override
  State<_SetEditorRow> createState() => _SetEditorRowState();
}

class _SetEditorRowState extends State<_SetEditorRow> {
  final _weightFocus = FocusNode();
  final _repsFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _weightFocus.addListener(_scrollIntoViewOnFocus);
    _repsFocus.addListener(_scrollIntoViewOnFocus);
    _weightFocus.addListener(_handleFocusLost);
    _repsFocus.addListener(_handleFocusLost);
  }

  void _scrollIntoViewOnFocus() {
    if (!_weightFocus.hasFocus && !_repsFocus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.3,
        duration: const Duration(milliseconds: 200),
      );
    });
  }

  /// Fires [ExerciseTile.onFocusLost] once neither of this row's fields is
  /// focused, rechecked a frame later so tabbing weight->reps within the
  /// same row doesn't falsely count as leaving the row.
  void _handleFocusLost() {
    if (_weightFocus.hasFocus || _repsFocus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_weightFocus.hasFocus || _repsFocus.hasFocus) return;
      widget.onFocusLost?.call();
    });
  }

  @override
  void dispose() {
    _weightFocus.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final i = widget.setIndex;
    // Sets can be removed via the "Remove set" button while this row's
    // element is still around for one frame; guard against a stale index.
    if (i >= draft.setWeights.length) return const SizedBox.shrink();
    final approx = draft.setApproxReps[i];
    final feedback = draft.setFeedback[i];
    final theme = Theme.of(context);
    return SizedBox(
      width: 268,
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: draft.weightControllers[i],
              focusNode: _weightFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    'Set ${i + 1} (${draft.exercise.unit.labelSuffix(customLabel: draft.exercise.customUnitLabel)})',
                isDense: true,
              ),
              onChanged: (text) {
                draft.setWeights[i] = double.tryParse(text);
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextFormField(
              controller: draft.repsControllers[i],
              focusNode: _repsFocus,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Reps',
                isDense: true,
                hintText: '${draft.repsFor(i)}',
                suffixIcon: draft.hasSuggestedTarget(i)
                    ? const Tooltip(
                        message: 'Target updated from a recent suggestion',
                        child: Icon(Icons.auto_awesome, size: 16),
                      )
                    : null,
              ),
              onChanged: (text) {
                draft.setReps[i] = int.tryParse(text);
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: approx ? 'Marked approximate' : 'Mark reps as approximate',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                draft.setApproxReps[i] = !approx;
                widget.onChanged();
              },
              child: CircleAvatar(
                radius: 14,
                backgroundColor: approx
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  '~',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: approx
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: switch (feedback) {
              SetFeedback.none => 'Mark this set good/bad',
              SetFeedback.up => 'Marked extra good — tap for bad',
              SetFeedback.down => 'Marked extra bad — tap to clear',
            },
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                draft.setFeedback[i] = switch (feedback) {
                  SetFeedback.none => SetFeedback.up,
                  SetFeedback.up => SetFeedback.down,
                  SetFeedback.down => SetFeedback.none,
                };
                widget.onChanged();
              },
              child: CircleAvatar(
                radius: 14,
                backgroundColor: feedback == SetFeedback.none
                    ? theme.colorScheme.surfaceContainerHighest
                    : theme.colorScheme.primaryContainer,
                child: Icon(
                  switch (feedback) {
                    SetFeedback.none => Icons.thumbs_up_down_outlined,
                    SetFeedback.up => Icons.thumb_up,
                    SetFeedback.down => Icons.thumb_down,
                  },
                  size: 14,
                  color: switch (feedback) {
                    SetFeedback.none => theme.colorScheme.outline,
                    SetFeedback.up => Colors.green,
                    SetFeedback.down => Colors.red,
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
