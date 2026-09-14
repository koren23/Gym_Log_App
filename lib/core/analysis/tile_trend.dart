import '../../models/analysis_result.dart';

/// A simplified 4-way classification of an exercise's recent trend, used to
/// color its tile on the log-workout screen. Reuses the exact
/// improving/stuck/steady bucketing `WeeklyInsightBox` already applies to
/// [AnalysisFinding]s for its own "Last few weeks" summary, rather than
/// inventing new thresholds.
enum TileTrend {
  /// Weight trending up and not plateaued.
  improving,

  /// Flagged as a plateau.
  stuck,

  /// Neither improving nor stuck — flat/down but not a genuine plateau.
  steady,

  /// No finding available (brand-new exercise, or fewer than
  /// `AnalysisEngine.minHistoryPoints` history points) — renders with no
  /// color, not a 4th visible hue.
  unknown,
}

TileTrend classifyTrend(AnalysisFinding? finding) {
  if (finding == null) return TileTrend.unknown;
  if (finding.weightTrend == TrendDirection.up && !finding.isPlateaued) {
    return TileTrend.improving;
  }
  if (finding.isPlateaued) return TileTrend.stuck;
  return TileTrend.steady;
}
