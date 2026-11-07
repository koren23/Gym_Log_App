import '../../models/history_entry.dart';
import 'stats_engine.dart';
import 'volume.dart';

/// XP is fully recomputed from existing history on every load — never
/// persisted to the sheet, consistent with every other derived stat in
/// this app, and trivially correct after a retroactive log edit.
int computeXp({
  required List<HistoryEntry> realEntries,
  required PrsByExercise prHistory,
}) {
  final totalRealVisits = realEntries.length;
  var totalSetsLoggedAllTime = 0;
  for (final entry in realEntries) {
    final meta = entry.metaRow;
    if (meta == null) continue;
    for (final range in meta.exercises) {
      totalSetsLoggedAllTime += range.setCount ?? 0;
    }
  }

  return 10 * totalRealVisits +
      2 * totalSetsLoggedAllTime +
      25 * prHistory.weightPrCount +
      15 * prHistory.volumePrCount;
}

/// XP earned for one just-logged [HistoryEntry], broken into the same
/// per-visit/per-set/per-PR components [computeXp] folds into its all-time
/// total, plus two bonuses that only make sense per-workout: a streak-upkeep
/// bonus (this workout keeps an active weekly streak going) and an
/// improvement bonus (this workout's total volume beat its own recent
/// trailing average).
class WorkoutXpBreakdown {
  const WorkoutXpBreakdown({
    required this.base,
    required this.prBonus,
    required this.streakBonus,
    required this.improvementBonus,
  });

  /// `10` for logging a visit at all, `+2` per set.
  final int base;

  /// `25` per new weight PR set this workout, `15` per new volume PR.
  final int prBonus;

  /// Extra XP for keeping an at-least-2-week streak alive.
  final int streakBonus;

  /// Extra XP for beating this exercise set's recent trailing-average volume.
  final int improvementBonus;

  int get total => base + prBonus + streakBonus + improvementBonus;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

double? _totalVolume(HistoryEntry entry) {
  final meta = entry.metaRow;
  if (meta == null) return null;
  double? total;
  for (final range in meta.exercises) {
    final volume = instanceVolume(range);
    if (volume == null) continue;
    total = (total ?? 0) + volume;
  }
  return total;
}

/// Computes [visit]'s XP breakdown. [realEntries] must include [visit]
/// itself, and [prHistory] must be `prsByExercise(realEntries)` — same
/// inputs the caller already has on hand for [computeXp]. [allVisitDates],
/// if provided, is used for the streak bonus in place of [realEntries]'
/// dates, so Sheets-only-logged workouts also keep a streak alive.
WorkoutXpBreakdown computeWorkoutXp({
  required HistoryEntry visit,
  required List<HistoryEntry> realEntries,
  required PrsByExercise prHistory,
  List<DateTime>? allVisitDates,
}) {
  final ranges = visit.metaRow?.exercises ?? const [];
  var setCount = 0;
  for (final range in ranges) {
    setCount += range.setCount ?? 0;
  }
  final base = 10 + 2 * setCount;

  final weightPrs = prHistory.maxWeightDate.values
      .where((date) => _isSameDay(date, visit.date))
      .length;
  final volumePrs = prHistory.maxVolumeDate.values
      .where((date) => _isSameDay(date, visit.date))
      .length;
  final prBonus = 25 * weightPrs + 15 * volumePrs;

  final visitDates = allVisitDates ?? realEntries.map((e) => e.date).toList();
  final streakWeeks = currentStreakWeeks(visitDates);
  final streakBonus = streakWeeks >= 2 ? 10 * streakWeeks.clamp(0, 8) : 0;

  final priorVisits = realEntries.where((e) => e.date.isBefore(visit.date)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  var improvementBonus = 0;
  final thisVolume = _totalVolume(visit);
  if (thisVolume != null && priorVisits.isNotEmpty) {
    final window = priorVisits.length > 3
        ? priorVisits.sublist(priorVisits.length - 3)
        : priorVisits;
    final baselineVolumes = window.map(_totalVolume).whereType<double>().toList();
    if (baselineVolumes.isNotEmpty) {
      final baseline =
          baselineVolumes.reduce((a, b) => a + b) / baselineVolumes.length;
      if (baseline > 0 && thisVolume > baseline * 1.02) {
        final pctOver = ((thisVolume - baseline) / baseline * 100).clamp(0, 50);
        improvementBonus = 10 + pctOver.round();
      }
    }
  }

  return WorkoutXpBreakdown(
    base: base,
    prBonus: prBonus,
    streakBonus: streakBonus,
    improvementBonus: improvementBonus,
  );
}

class XpTier {
  const XpTier(this.name, this.minXp, this.maxXp);
  final String name;
  final int minXp;

  /// Exclusive upper bound, or null for the top (unbounded) tier.
  final int? maxXp;
}

/// Starting-point thresholds — not final; sanity-check against this user's
/// real visit/set counts once computed, and rescale if Gold would be
/// reached in weeks rather than roughly a year of active use.
const List<XpTier> kXpTiers = [
  XpTier('Bronze', 0, 500),
  XpTier('Silver', 500, 1500),
  XpTier('Gold', 1500, 3500),
  XpTier('Platinum', 3500, 7000),
  XpTier('Diamond', 7000, null),
];

XpTier xpTierFor(int xp) {
  for (final tier in kXpTiers) {
    if (xp >= tier.minXp && (tier.maxXp == null || xp < tier.maxXp!)) {
      return tier;
    }
  }
  return kXpTiers.last;
}

/// Progress (0.0-1.0) through the current tier, for the barbell bar.
double xpTierProgress(int xp) {
  final tier = xpTierFor(xp);
  if (tier.maxXp == null) return 1.0;
  final span = tier.maxXp! - tier.minXp;
  if (span <= 0) return 1.0;
  return ((xp - tier.minXp) / span).clamp(0.0, 1.0);
}
