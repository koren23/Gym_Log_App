import '../../models/analysis_result.dart';
import '../../models/rating_relevance.dart';

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

  /// [history] must be sorted chronologically ascending (oldest first).
  /// [bodyWeightTrend] is the user's overall body-weight trend over a
  /// comparable recent window (see `bodyWeightTrend` in
  /// analysis_providers.dart) — left `unknown` if not available.
  AnalysisFinding? analyze({
    required String subjectName,
    required List<HistoryPoint> history,
    required List<String> alternativeExerciseNames,
    required Set<String> recentlySuggestedAlternatives,
    TrendDirection bodyWeightTrend = TrendDirection.unknown,
  }) {
    if (history.length < minHistoryPoints) return null;

    final weightTrend = _weightTrend(history);
    final rawWeightPlateaued = _isPlateaued(history);
    final volumeTrend = _volumeTrend(history);
    // Weight alone looking stuck doesn't mean progress has actually
    // stopped — more reps or more sets at the same weight is still real
    // overload. Only call it a plateau when volume isn't climbing either.
    final isPlateaued = rawWeightPlateaued && volumeTrend != TrendDirection.up;
    final ratingTrend = _ratingTrend(history);
    final repRangeChanged = _repRangeChanged(history);

    if (rawWeightPlateaued && volumeTrend == TrendDirection.up) {
      return AnalysisFinding(
        subjectName: subjectName,
        weightTrend: TrendDirection.up,
        ratingTrend: ratingTrend,
        isPlateaued: false,
        repRangeChanged: repRangeChanged,
        message:
            '$subjectName — weight has held steady, but you\'re doing more '
            'reps or sets than before. That still counts as progress.',
        priority: 0,
      );
    }

    // A raw weight plateau with flat/declining volume can still be worth a
    // second look if recent sets have been marked (optionally, via the
    // per-set thumbs feedback) as feeling strong — a lighter signal than
    // the volume-trend override above, so it only applies once that one
    // doesn't.
    if (rawWeightPlateaued &&
        volumeTrend != TrendDirection.up &&
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

    // Either a genuine weight plateau or a declining rating is reason
    // enough on its own — a plateau while ratings are merely flat (not
    // improving) still deserves a heads-up, and a rating that's dropping
    // even while weight climbs is worth flagging too.
    final ratingDeclining = ratingTrend == TrendDirection.down;
    final needsAttention = isPlateaued || ratingDeclining;

    if (!needsAttention && weightTrend == TrendDirection.up) {
      return AnalysisFinding(
        subjectName: subjectName,
        weightTrend: weightTrend,
        ratingTrend: ratingTrend,
        isPlateaued: false,
        repRangeChanged: repRangeChanged,
        message:
            '$subjectName is trending up — recent sessions show steady '
            'weight progress. Keep the current rep range and pace.',
        priority: 0,
      );
    }

    if (!needsAttention && weightTrend == TrendDirection.down) {
      return AnalysisFinding(
        subjectName: subjectName,
        weightTrend: weightTrend,
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
        weightTrend: weightTrend,
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
    final lowRatings =
        avgRecentRating != null && avgRecentRating < ratingVeryLowThreshold;
    final thumbsDownCluster = _recentThumbsDownCluster(history);
    if (lowRatings || thumbsDownCluster) {
      suggestion =
          '${lowRatings ? 'Ratings have been low' : 'Recent sets have felt bad'} '
          'regardless of weight trend — consider a deload (reduce working '
          'weight ~10%) or double-check form before pushing further.';
      priority = 3;
    } else if (!repRangeChanged) {
      final low = history.last.repRangeLow;
      final high = history.last.repRangeHigh;
      final suggestedLow = low + 2;
      final suggestedHigh = high + 2;
      suggestion =
          'Try switching the rep range to $suggestedLow-$suggestedHigh reps '
          'for a few sessions before increasing weight again.';
      priority = 2;
    } else {
      final alt = _pickAlternative(
        alternativeExerciseNames,
        recentlySuggestedAlternatives,
      );
      suggestion = alt != null
          ? 'Progress has stalled even after a rep-range change — try '
                'swapping in $alt for a few weeks.'
          : 'Progress has stalled — consider swapping this exercise for a '
                'variation targeting the same muscle group.';
      priority = 2;
    }

    final message = isPlateaued
        ? '$subjectName has been stuck for the last $plateauWindow sessions'
              '${avgRecentRating != null ? ' and ratings have been ${avgRecentRating <= ratingLowThreshold ? 'low' : 'flat'}' : ''}.'
        : '$subjectName — ratings on this exercise have been dropping, even '
              'though the weight itself is fine. Worth a closer look.';

    return AnalysisFinding(
      subjectName: subjectName,
      weightTrend: weightTrend,
      ratingTrend: ratingTrend,
      isPlateaued: true,
      repRangeChanged: repRangeChanged,
      message: message,
      suggestion: suggestion,
      priority: priority,
    );
  }

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

  String? _pickAlternative(
    List<String> candidates,
    Set<String> recentlySuggested,
  ) {
    if (candidates.isEmpty) return null;
    for (final c in candidates) {
      if (!recentlySuggested.contains(c)) return c;
    }
    return candidates.first;
  }
}
