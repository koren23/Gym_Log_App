/// How much a visit's star rating should count toward trend analysis — lets
/// the user flag a session where how they felt wasn't really about the
/// workout itself (e.g. feeling sick), without deleting the rating outright.
enum RatingRelevance {
  /// Counts fully, same as always.
  normal,

  /// Counts at half weight in rating-trend calculations.
  halfRelated,

  /// Excluded entirely from rating-trend calculations.
  unrelated,
}

extension RatingRelevanceX on RatingRelevance {
  double get weight => switch (this) {
    RatingRelevance.normal => 1.0,
    RatingRelevance.halfRelated => 0.5,
    RatingRelevance.unrelated => 0.0,
  };

  /// Exact string stored in the sheet's `ratingRelevance` column.
  String get sheetValue => switch (this) {
    RatingRelevance.normal => 'normal',
    RatingRelevance.halfRelated => 'half',
    RatingRelevance.unrelated => 'unrelated',
  };

  String get label => switch (this) {
    RatingRelevance.normal => 'Normal',
    RatingRelevance.halfRelated => 'Half-related',
    RatingRelevance.unrelated => 'Not related',
  };
}

/// Parses the sheet's `ratingRelevance` column — blank, missing, or any
/// unrecognized value (including every row logged before this column
/// existed) defaults to [RatingRelevance.normal].
RatingRelevance ratingRelevanceFromSheetValue(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'half':
      return RatingRelevance.halfRelated;
    case 'unrelated':
      return RatingRelevance.unrelated;
    default:
      return RatingRelevance.normal;
  }
}
