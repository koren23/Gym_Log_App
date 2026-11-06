import '../../models/history_entry.dart';
import 'stats_engine.dart';

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
