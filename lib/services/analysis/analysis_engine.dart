import '../../core/utils/exercise_value_format.dart';
import '../../models/analysis_result.dart';
import '../../models/exercise.dart';
import '../../models/exercise_unit.dart';
import '../../models/rating_relevance.dart';
import '../../models/set_feedback.dart';

/// One historical data point for a single exercise (or, for muscle-group
/// level analysis, one week's aggregate across that group's exercises).
class HistoryPoint {
  const HistoryPoint({
    required this.isoYear,
    required this.isoWeek,
    required this.date,
    required this.avgWeight,
    required this.repRangeLow,
    required this.repRangeHigh,
    this.rating,
    this.ratingRelevance = RatingRelevance.normal,
    this.exactDateKnown = true,
    this.totalSets,
    this.avgReps,
    this.thumbsUpCount = 0,
    this.thumbsDownCount = 0,
    this.actualRepsPerSet = const [],
    this.actualWeightsPerSet = const [],
    this.perSetFeedback = const [],
  });

  final int isoYear;
  final int isoWeek;

  /// Best-known date for this point. When [exactDateKnown] is false, this
  /// is only an approximation used for chart ordering — display code
  /// should show "Week [isoWeek], [isoYear]" instead of formatting it as a
  /// real date.
  final DateTime date;
  final double avgWeight;
  final int repRangeLow;
  final int repRangeHigh;
  final double? rating;

  /// How much [rating] should count toward trend analysis — see
  /// [RatingRelevance].
  final RatingRelevance ratingRelevance;
  final bool exactDateKnown;

  /// Number of sets actually performed, and the average reps per set —
  /// both null for visits logged before per-set reps were tracked.
  final int? totalSets;
  final double? avgReps;

  /// Count of sets marked thumbs-up/down (see [SetFeedback]) in this visit
  /// — 0 for visits logged before this was tracked, or with no feedback
  /// set. A light, optional signal — see [AnalysisEngine
  /// ._thumbsSuggestOverridePlateau].
  final int thumbsUpCount;
  final int thumbsDownCount;

  /// Raw per-set reps/weights/feedback for this visit, in set order —
  /// empty for visits logged before per-set data was tracked. Used by
  /// [AnalysisEngine._findWeakSet]/[AnalysisEngine._allSetsTopOfRangeStreak]
  /// to reason about one specific set rather than only the exercise-wide
  /// average.
  final List<int> actualRepsPerSet;
  final List<double> actualWeightsPerSet;
  final List<SetFeedback> perSetFeedback;
}

/// On-device, rule-based analysis of an exercise's (or muscle group's)
/// history. No network, no LLM — see plan doc for the rationale and the
/// concrete thresholds below.
class AnalysisEngine {
  const AnalysisEngine();

  static const int minHistoryPoints = 3;
  static const int plateauWindow = 4;
  static const double weightTrendThresholdPct = 0.01; // 1% per data point
  static const int ratingDeclineWindow = 3;
  static const double ratingLowThreshold = 2.5;
  static const double ratingVeryLowThreshold = 2.0;
  static const int repRangeModeWindow = 5;
  static const int proactiveScanWindowWeeks = 8;
  static const double bodyWeightTrendThresholdPct =
      0.015; // 1.5% over the window

  /// Net (thumbs-up minus thumbs-down) sets over [plateauWindow] needed to
  /// downgrade a raw weight plateau — a light, capped nudge (never a
  /// replacement for the objective weight/rep numbers): recent sets that
  /// genuinely felt strong are worth noting even if the number on the bar
  /// hasn't moved yet.
  static const int thumbsPlateauOverrideThreshold = 2;

  /// Recent thumbs-down sets (with no offsetting thumbs-up) needed to count
  /// alongside [ratingVeryLowThreshold] toward suggesting a deload.
  static const int thumbsDeloadSuggestThreshold = 3;

  /// Sessions considered when looking for one specific set trailing its
  /// siblings (see [_findWeakSet]).
  static const int perSetWindow = 4;

  /// Minimum sessions with per-set data required before judging any one set
  /// weak — too few and normal session-to-session noise looks like a
  /// pattern.
  static const int perSetMinSessions = 3;

  /// A set must average this many reps below its siblings (over
  /// [perSetWindow]) to count as trailing.
  static const double perSetRepDeficitThreshold = 2.0;

  /// Net thumbs-down at one specific set index (over [perSetWindow]) that,
  /// alone, is enough to flag that set even without a rep deficit.
  static const int perSetFeedbackDownThreshold = 2;

  /// Consecutive sessions where every single set hit its own session's
  /// target-high, needed before suggesting a straight weight increase.
  static const int topOfRangeStreak = 3;

  static const double standardWeightIncrementKg = 2.5;
  static const double deloadPct = 0.10;

  /// Smaller, single-set version of [deloadPct] — used when only one set is
  /// underperforming, not the whole exercise.
  static const double weakSetDeloadPct = 0.08;

  /// [history] must be sorted chronologically ascending (oldest first).
  /// [bodyWeightTrend] is the user's overall body-weight trend over a
  /// comparable recent window (see `bodyWeightTrend` in
  /// analysis_providers.dart) — left `unknown` if not available. [unit] is
  /// the exercise's logged unit (see [ExerciseUnit]) — for
  /// [ExerciseUnit.bodyweight], where added weight is frequently 0/
  /// unchanging, volume (sets×reps) is treated as the primary "is this
  /// improving" signal instead of weight, with weight only checked as the
  /// secondary signal (mirroring, with the two swapped, how a plain
  /// kg exercise treats volume as its secondary signal).
  ///
  /// [recentlySuggestedAlternatives] avoids repeating the exact same
  /// replacement-exercise name when picking a [SuggestionKind.changeExercise]
  /// candidate. [recentlySuggestedKinds] is broader — any suggestion kind
  /// shown recently for this subject — and causes the engine to fall
  /// through to the next applicable kind instead of repeating one that was
  /// just shown; see the "stuck" ladder below.
  AnalysisFinding? analyze({
    required String subjectName,
    required List<HistoryPoint> history,
    required List<Exercise> alternativeExercises,
    required Set<String> recentlySuggestedAlternatives,
    Set<SuggestionKind> recentlySuggestedKinds = const {},
    TrendDirection bodyWeightTrend = TrendDirection.unknown,
    ExerciseUnit unit = ExerciseUnit.kg,
    String? customUnitLabel,
  }) {
    if (history.length < minHistoryPoints) return null;

    final isBodyweight = unit == ExerciseUnit.bodyweight;
    final weightTrend = _weightTrend(history);
    final volumeTrend = _volumeTrend(history);
    // The trend that drives "is this improving" — volume for a bodyweight
    // exercise (since added weight is often 0/unchanging), weight for
    // everything else. The other one is only consulted as a secondary
    // signal below, with the two roles fully swapped for bodyweight.
    final primaryTrend = isBodyweight ? volumeTrend : weightTrend;
    final secondaryTrend = isBodyweight ? weightTrend : volumeTrend;
    final rawPlateaued = isBodyweight
        ? _isVolumePlateaued(history)
        : _isPlateaued(history);
    // A primary metric alone looking stuck doesn't mean progress has
    // actually stopped — real overload via the secondary metric still
    // counts. Only call it a plateau when the secondary metric isn't
    // climbing either.
    final isPlateaued = rawPlateaued && secondaryTrend != TrendDirection.up;
    final ratingTrend = _ratingTrend(history);
    final repRangeChanged = _repRangeChanged(history);

    if (rawPlateaued && secondaryTrend == TrendDirection.up) {
      return AnalysisFinding(
        subjectName: subjectName,
        weightTrend: TrendDirection.up,
        ratingTrend: ratingTrend,
        isPlateaued: false,
        repRangeChanged: repRangeChanged,
        message: isBodyweight
            ? '$subjectName — reps/sets have held steady, but you\'re adding '
                  'more weight than before. That still counts as progress.'
            : '$subjectName — weight has held steady, but you\'re doing more '
                  'reps or sets than before. That still counts as progress.',
        priority: 0,
      );
    }

    // A raw plateau with a flat/declining secondary metric can still be
    // worth a second look if recent sets have been marked (optionally, via
    // the per-set thumbs feedback) as feeling strong — a lighter signal
    // than the trend override above, so it only applies once that one
    // doesn't.
    if (rawPlateaued &&
        secondaryTrend != TrendDirection.up &&
        _thumbsSuggestOverridePlateau(history)) {
      return AnalysisFinding(
        subjectName: subjectName,
        weightTrend: TrendDirection.flat,
        ratingTrend: ratingTrend,
        isPlateaued: false,
        repRangeChanged: repRangeChanged,
        message:
            '$subjectName — weight has held steady, but recent sets have '
            "felt strong — that's still worth noting before calling it a "
            'plateau.',
        priority: 0,
      );
    }

    // A deliberate body-weight cut naturally drags working weight down a
    // little — a flat or slightly-down lifting weight during a cut isn't a
    // stall, it's expected, so don't flag it.
    if (bodyWeightTrend == TrendDirection.down &&
        (isPlateaued || weightTrend == TrendDirection.down)) {
      return AnalysisFinding(
        subjectName: subjectName,
        weightTrend: TrendDirection.flat,
        ratingTrend: ratingTrend,
        isPlateaued: false,
        repRangeChanged: repRangeChanged,
        message:
            '$subjectName has held roughly steady while your body weight '
            'has been trending down — a slight dip in working weight during '
            'a cut is expected, not a stall.',
        priority: 0,
      );
    }

    final ratedPoints = history
        .where(
          (h) =>
              h.rating != null &&
              h.ratingRelevance != RatingRelevance.unrelated,
        )
        .toList();
    final recentRatedPoints = ratedPoints.length >= ratingDeclineWindow
        ? ratedPoints.sublist(ratedPoints.length - ratingDeclineWindow)
        : ratedPoints;
    final avgRecentRating = _weightedMean(recentRatedPoints);

    // Either a genuine plateau or a declining rating is reason enough on
    // its own — a plateau while ratings are merely flat (not improving)
    // still deserves a heads-up, and a rating that's dropping even while
    // the primary metric climbs is worth flagging too.
    final ratingDeclining = ratingTrend == TrendDirection.down;
    final needsAttention = isPlateaued || ratingDeclining;
    final metricNoun = _metricNoun(unit, customUnitLabel);

    if (!needsAttention && primaryTrend == TrendDirection.up) {
      // Not just "trending up" but every set maxing out its own target —
      // that's a concrete "go heavier" moment, not just a compliment.
      final readyForMore =
          !isBodyweight && _allSetsTopOfRangeStreak(history);
      if (readyForMore) {
        final newWeight = history.last.avgWeight + standardWeightIncrementKg;
        return AnalysisFinding(
          subjectName: subjectName,
          weightTrend: primaryTrend,
          ratingTrend: ratingTrend,
          isPlateaued: false,
          repRangeChanged: repRangeChanged,
          message:
              '$subjectName is trending up — every set has hit the top of '
              'its rep range for the last $topOfRangeStreak sessions.',
          suggestion:
              'Try ${formatExerciseValue(unit, newWeight, customLabel: customUnitLabel)} '
              'next time.',
          priority: 1,
          kind: SuggestionKind.changeTotalWeight,
          payload: WeightSuggestionPayload(newWeight: newWeight),
        );
      }
      return AnalysisFinding(
        subjectName: subjectName,
        weightTrend: primaryTrend,
        ratingTrend: ratingTrend,
        isPlateaued: false,
        repRangeChanged: repRangeChanged,
        message:
            '$subjectName is trending up — recent sessions show steady '
            '$metricNoun progress. Keep the current rep range and pace.',
        priority: 0,
      );
    }

    if (!needsAttention && primaryTrend == TrendDirection.down) {
      return AnalysisFinding(
        subjectName: subjectName,
        weightTrend: primaryTrend,
        ratingTrend: ratingTrend,
        isPlateaued: false,
        repRangeChanged: repRangeChanged,
        message:
            '$subjectName has dipped slightly in recent sessions — not '
            'enough yet to call it a plateau, but worth keeping an eye on.',
        priority: 0,
      );
    }

    if (!needsAttention) {
      return AnalysisFinding(
        subjectName: subjectName,
        weightTrend: primaryTrend,
        ratingTrend: ratingTrend,
        isPlateaued: false,
        repRangeChanged: repRangeChanged,
        message:
            '$subjectName looks stable — no plateau or rating '
            'decline detected.',
        priority: 0,
      );
    }

    String suggestion;
    int priority;
    SuggestionKind kind;
    SuggestionPayload? payload;
    final lowRatings =
        avgRecentRating != null && avgRecentRating < ratingVeryLowThreshold;
    final thumbsDownCluster = _recentThumbsDownCluster(history);
    if (lowRatings || thumbsDownCluster) {
      final newWeight = history.last.avgWeight * (1 - deloadPct);
      suggestion =
          '${lowRatings ? 'Ratings have been low' : 'Recent sets have felt bad'} '
          'regardless of trend — consider a deload (reduce $metricNoun ~10%, '
          'to about ${formatExerciseValue(unit, newWeight, customLabel: customUnitLabel)}) '
          'or double-check form before pushing further.';
      priority = 3;
      kind = SuggestionKind.deload;
      payload = WeightSuggestionPayload(newWeight: newWeight);
    } else {
      // A ladder of candidate remedies, most specific first — walked in
      // order and skipped past whenever its kind was already suggested
      // recently, so the same nudge doesn't repeat every session. Falls
      // back to a plain (non-actionable) message only once every rung is
      // on cooldown.
      final rungs =
          <({SuggestionKind kind, String suggestion, SuggestionPayload? payload})>[];

      final weakSet = _findWeakSet(history);
      if (weakSet != null) {
        final setNum = weakSet.index + 1;
        if (weakSet.avgAtIndex < history.last.repRangeLow) {
          final currentWeightAtIndex =
              weakSet.index < history.last.actualWeightsPerSet.length
              ? history.last.actualWeightsPerSet[weakSet.index]
              : history.last.avgWeight;
          final newWeight = currentWeightAtIndex * (1 - weakSetDeloadPct);
          rungs.add((
            kind: SuggestionKind.changeWeightForSet,
            suggestion:
                'Set $setNum has been trailing your other sets — try '
                'dropping just that set to '
                '${formatExerciseValue(unit, newWeight, customLabel: customUnitLabel)}.',
            payload: WeightSuggestionPayload(
              setIndex: weakSet.index,
              newWeight: newWeight,
            ),
          ));
        } else {
          final newLow = weakSet.avgAtIndex.round() - 1;
          final newHigh = weakSet.avgAtIndex.round() + 1;
          rungs.add((
            kind: SuggestionKind.changeRepRangeForSet,
            suggestion:
                'Set $setNum has been trailing your other sets — try '
                'giving it its own target of $newLow-$newHigh reps instead.',
            payload: RepRangeSuggestionPayload(
              setIndex: weakSet.index,
              newLow: newLow,
              newHigh: newHigh,
            ),
          ));
        }
      }

      if (!repRangeChanged) {
        final low = history.last.repRangeLow;
        final high = history.last.repRangeHigh;
        final newLow = low + 2;
        final newHigh = high + 2;
        rungs.add((
          kind: SuggestionKind.changeRepRangeOverall,
          suggestion:
              'Try switching the rep range to $newLow-$newHigh reps for a '
              'few sessions before increasing weight again.',
          payload: RepRangeSuggestionPayload(newLow: newLow, newHigh: newHigh),
        ));
      }

      final alt = _pickAlternative(
        alternativeExercises,
        recentlySuggestedAlternatives,
      );
      rungs.add((
        kind: SuggestionKind.changeExercise,
        suggestion: alt != null
            ? 'Progress has stalled — try swapping in ${alt.name} for a '
                  'few weeks.'
            : 'Progress has stalled — consider swapping this exercise for '
                  'a variation targeting the same muscle group.',
        payload: alt != null ? ExerciseSwapPayload(replacement: alt) : null,
      ));

      final chosenIndex = rungs.indexWhere(
        (r) => !recentlySuggestedKinds.contains(r.kind),
      );
      if (chosenIndex == -1) {
        suggestion =
            "You've already gotten a few different suggestions for this "
            'recently — still worth keeping an eye on, nothing new to try '
            'just yet.';
        kind = SuggestionKind.none;
        payload = null;
      } else {
        final chosen = rungs[chosenIndex];
        suggestion = chosen.suggestion;
        kind = chosen.kind;
        payload = chosen.payload;
      }
      priority = 2;
    }

    final message = isPlateaued
        ? '$subjectName has been stuck for the last $plateauWindow sessions'
              '${avgRecentRating != null ? ' and ratings have been ${avgRecentRating <= ratingLowThreshold ? 'low' : 'flat'}' : ''}.'
        : '$subjectName — ratings on this exercise have been dropping, even '
              'though the $metricNoun itself is fine. Worth a closer look.';

    return AnalysisFinding(
      subjectName: subjectName,
      weightTrend: primaryTrend,
      ratingTrend: ratingTrend,
      isPlateaued: true,
      repRangeChanged: repRangeChanged,
      message: message,
      suggestion: suggestion,
      priority: priority,
      kind: kind,
      payload: payload,
    );
  }

  /// The right noun for [unit] when a message needs to name "the number
  /// that's stuck/climbing/dropping" — e.g. "consider a deload (reduce
  /// $noun ~10%)".
  String _metricNoun(ExerciseUnit unit, String? customUnitLabel) =>
      switch (unit) {
        ExerciseUnit.kg => 'working weight',
        ExerciseUnit.bodyweight => 'added weight',
        ExerciseUnit.time => 'hold time',
        ExerciseUnit.custom => customUnitLabel ?? 'value',
      };

  TrendDirection _weightTrend(List<HistoryPoint> history) {
    final points = history.length > 6
        ? history.sublist(history.length - 6)
        : history;
    if (points.length < 2) return TrendDirection.unknown;

    final half = points.length ~/ 2;
    if (half == 0) return TrendDirection.flat;
    final firstHalf = points.sublist(0, half);
    final secondHalf = points.sublist(points.length - half);
    final firstAvg =
        firstHalf.map((h) => h.avgWeight).reduce((a, b) => a + b) /
        firstHalf.length;
    final secondAvg =
        secondHalf.map((h) => h.avgWeight).reduce((a, b) => a + b) /
        secondHalf.length;
    if (firstAvg == 0) return TrendDirection.flat;

    final pctChangePerPoint = (secondAvg - firstAvg) / firstAvg / half;
    if (pctChangePerPoint >= weightTrendThresholdPct) return TrendDirection.up;
    if (pctChangePerPoint <= -weightTrendThresholdPct) {
      return TrendDirection.down;
    }
    return TrendDirection.flat;
  }

  /// Same idea as [_weightTrend] but tracking sets×reps instead of weight
  /// — points without reps/sets data (legacy visits) are skipped rather
  /// than treated as zero, so old history doesn't drag a real recent
  /// upward trend back down to "unknown".
  TrendDirection _volumeTrend(List<HistoryPoint> history) {
    final withVolume = [
      for (final h in history)
        if (h.totalSets != null && h.avgReps != null) h,
    ];
    if (withVolume.length < 2) return TrendDirection.unknown;
    final points = withVolume.length > 6
        ? withVolume.sublist(withVolume.length - 6)
        : withVolume;
    if (points.length < 2) return TrendDirection.unknown;

    final half = points.length ~/ 2;
    if (half == 0) return TrendDirection.flat;
    double volume(HistoryPoint h) => h.totalSets! * h.avgReps!;
    final firstHalf = points.sublist(0, half);
    final secondHalf = points.sublist(points.length - half);
    final firstAvg =
        firstHalf.map(volume).reduce((a, b) => a + b) / firstHalf.length;
    final secondAvg =
        secondHalf.map(volume).reduce((a, b) => a + b) / secondHalf.length;
    if (firstAvg == 0) return TrendDirection.flat;

    final pctChangePerPoint = (secondAvg - firstAvg) / firstAvg / half;
    if (pctChangePerPoint >= weightTrendThresholdPct) return TrendDirection.up;
    if (pctChangePerPoint <= -weightTrendThresholdPct) {
      return TrendDirection.down;
    }
    return TrendDirection.flat;
  }

  bool _isPlateaued(List<HistoryPoint> history) {
    if (history.length < plateauWindow + 1) return false;
    final last4 = history.sublist(history.length - plateauWindow);
    final maxLast4 = last4
        .map((h) => h.avgWeight)
        .reduce((a, b) => a > b ? a : b);
    final fifthBack = history[history.length - plateauWindow - 1].avgWeight;
    return maxLast4 <= fifthBack;
  }

  /// Same idea as [_isPlateaued] but tracking sets×reps instead of weight —
  /// used for [ExerciseUnit.bodyweight], where added weight is often
  /// 0/unchanging by design. Points without reps/sets data are skipped
  /// (see [_volumeTrend]); returns false (never "plateaued") if there
  /// aren't enough such points to judge.
  bool _isVolumePlateaued(List<HistoryPoint> history) {
    final withVolume = [
      for (final h in history)
        if (h.totalSets != null && h.avgReps != null) h,
    ];
    if (withVolume.length < plateauWindow + 1) return false;
    double volume(HistoryPoint h) => h.totalSets! * h.avgReps!;
    final last4 = withVolume.sublist(withVolume.length - plateauWindow);
    final maxLast4 = last4.map(volume).reduce((a, b) => a > b ? a : b);
    final fifthBack = volume(withVolume[withVolume.length - plateauWindow - 1]);
    return maxLast4 <= fifthBack;
  }

  TrendDirection _ratingTrend(List<HistoryPoint> history) {
    final ratedPoints = history
        .where(
          (h) =>
              h.rating != null &&
              h.ratingRelevance != RatingRelevance.unrelated,
        )
        .toList();
    if (ratedPoints.length < 2) return TrendDirection.unknown;
    final recentPoints = ratedPoints.length >= ratingDeclineWindow
        ? ratedPoints.sublist(ratedPoints.length - ratingDeclineWindow)
        : ratedPoints;
    final avg = _weightedMean(recentPoints)!;
    final recent = [for (final p in recentPoints) p.rating!];

    var strictlyDecreasing = true;
    for (var i = 1; i < recent.length; i++) {
      if (recent[i] > recent[i - 1]) {
        strictlyDecreasing = false;
        break;
      }
    }
    final hasStrictDrop = recent.length > 1 && recent.last < recent.first;

    if (avg <= ratingLowThreshold || (strictlyDecreasing && hasStrictDrop)) {
      return TrendDirection.down;
    }
    if (avg >= 4.0) return TrendDirection.up;
    return TrendDirection.flat;
  }

  /// Whether recent per-set thumbs feedback (see [SetFeedback]) leans
  /// clearly positive over the last [plateauWindow] visits — a small,
  /// optional signal that a raw weight plateau shouldn't necessarily be
  /// read as a real stall, on top of (not instead of) the objective
  /// weight/volume numbers.
  bool _thumbsSuggestOverridePlateau(List<HistoryPoint> history) {
    final recent = history.length > plateauWindow
        ? history.sublist(history.length - plateauWindow)
        : history;
    final net = recent.fold<int>(
      0,
      (sum, h) => sum + h.thumbsUpCount - h.thumbsDownCount,
    );
    return net >= thumbsPlateauOverrideThreshold;
  }

  /// Whether recent per-set thumbs feedback leans clearly negative over the
  /// last [ratingDeclineWindow] visits — mirrors
  /// [_thumbsSuggestOverridePlateau] but toward a deload suggestion instead
  /// of overriding a plateau.
  bool _recentThumbsDownCluster(List<HistoryPoint> history) {
    final recent = history.length > ratingDeclineWindow
        ? history.sublist(history.length - ratingDeclineWindow)
        : history;
    final net = recent.fold<int>(
      0,
      (sum, h) => sum + h.thumbsDownCount - h.thumbsUpCount,
    );
    return net >= thumbsDeloadSuggestThreshold;
  }

  /// Weighted mean of [points]' ratings, discounting anything flagged
  /// [RatingRelevance.halfRelated] to half weight ([RatingRelevance
  /// .unrelated] points are assumed already filtered out by the caller).
  /// Null if there's nothing to average.
  double? _weightedMean(List<HistoryPoint> points) {
    var totalWeight = 0.0;
    var weightedSum = 0.0;
    for (final p in points) {
      final rating = p.rating;
      if (rating == null) continue;
      final weight = p.ratingRelevance.weight;
      totalWeight += weight;
      weightedSum += rating * weight;
    }
    if (totalWeight == 0) return null;
    return weightedSum / totalWeight;
  }

  bool _repRangeChanged(List<HistoryPoint> history) {
    if (history.length < 2) return false;
    final windowSize = history.length > repRangeModeWindow + 1
        ? repRangeModeWindow
        : history.length - 1;
    if (windowSize <= 0) return false;
    final prior = history.sublist(
      history.length - 1 - windowSize,
      history.length - 1,
    );
    final counts = <String, int>{};
    for (final h in prior) {
      final key = '${h.repRangeLow}-${h.repRangeHigh}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (counts.isEmpty) return false;
    final modeKey = counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    final latest = history.last;
    return modeKey != '${latest.repRangeLow}-${latest.repRangeHigh}';
  }

  Exercise? _pickAlternative(
    List<Exercise> candidates,
    Set<String> recentlySuggested,
  ) {
    if (candidates.isEmpty) return null;
    for (final c in candidates) {
      if (!recentlySuggested.contains(c.name)) return c;
    }
    return candidates.first;
  }

  /// Looks for one specific set index that's been consistently trailing its
  /// siblings (fewer reps, or a net negative thumbs-feedback cluster) over
  /// the last [perSetWindow] sessions that have per-set data — e.g. a
  /// shoulder that fatigues faster than usual on the final set. Only
  /// evaluated by [analyze] once an exercise already needs attention
  /// (plateaued or rating-declining), so it never nags about an
  /// intentionally lighter set in a deliberate pyramid/drop-set structure
  /// on an otherwise healthy exercise. Returns null if there isn't enough
  /// per-set data, only one set is logged, or no set qualifies.
  ({int index, double avgAtIndex})? _findWeakSet(List<HistoryPoint> history) {
    final withPerSet = [
      for (final h in history)
        if (h.actualRepsPerSet.isNotEmpty) h,
    ];
    if (withPerSet.length < perSetMinSessions) return null;
    final points = withPerSet.length > perSetWindow
        ? withPerSet.sublist(withPerSet.length - perSetWindow)
        : withPerSet;
    if (points.length < perSetMinSessions) return null;

    final minSetCount = points
        .map((p) => p.actualRepsPerSet.length)
        .reduce((a, b) => a < b ? a : b);
    if (minSetCount < 2) return null;

    int? weakIndex;
    double weakDeficit = 0;
    double weakAvgAtIndex = 0;
    for (var idx = 0; idx < minSetCount; idx++) {
      final atIndex = <int>[];
      final others = <int>[];
      var feedbackNet = 0;
      for (final p in points) {
        atIndex.add(p.actualRepsPerSet[idx]);
        for (var j = 0; j < p.actualRepsPerSet.length; j++) {
          if (j != idx) others.add(p.actualRepsPerSet[j]);
        }
        if (idx < p.perSetFeedback.length) {
          if (p.perSetFeedback[idx] == SetFeedback.down) feedbackNet++;
          if (p.perSetFeedback[idx] == SetFeedback.up) feedbackNet--;
        }
      }
      if (others.isEmpty) continue;
      final avgAtIndex = atIndex.reduce((a, b) => a + b) / atIndex.length;
      final avgOthers = others.reduce((a, b) => a + b) / others.length;
      final deficit = avgOthers - avgAtIndex;
      final qualifies =
          deficit >= perSetRepDeficitThreshold ||
          feedbackNet >= perSetFeedbackDownThreshold;
      // The first qualifying index always wins, so a set flagged purely by
      // bad feedback (deficit near zero or negative) isn't silently passed
      // over just because it doesn't beat an initial deficit of 0 — after
      // that, a strictly larger deficit among other qualifying sets can
      // still take over as "the" weak one.
      if (qualifies && (weakIndex == null || deficit > weakDeficit)) {
        weakDeficit = deficit;
        weakIndex = idx;
        weakAvgAtIndex = avgAtIndex;
      }
    }
    if (weakIndex == null) return null;
    return (index: weakIndex, avgAtIndex: weakAvgAtIndex);
  }

  /// Whether every set in the last [topOfRangeStreak] sessions (that have
  /// per-set data) hit at least that session's own target-high — a
  /// concrete "ready to go heavier" signal, stronger than just "trending
  /// up".
  bool _allSetsTopOfRangeStreak(List<HistoryPoint> history) {
    final withPerSet = [
      for (final h in history)
        if (h.actualRepsPerSet.isNotEmpty) h,
    ];
    if (withPerSet.length < topOfRangeStreak) return false;
    final points = withPerSet.sublist(withPerSet.length - topOfRangeStreak);
    return points.every(
      (p) => p.actualRepsPerSet.every((reps) => reps >= p.repRangeHigh),
    );
  }
}
