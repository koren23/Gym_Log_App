/// Optional per-set "this rep felt extra good/bad" marker — set by the user
/// tapping a thumbs-up/down toggle while logging a set, distinct from the
/// whole-visit star rating. Factored (lightly) into future trend/suggestion
/// analysis — see `AnalysisEngine`'s thumbs-related overrides.
enum SetFeedback {
  /// No feedback given — the common case.
  none,

  /// Marked as an especially good set.
  up,

  /// Marked as an especially bad set.
  down,
}

extension SetFeedbackX on SetFeedback {
  /// Exact token stored per set in the sheet's exercises-cell feedback
  /// segment (see `SheetWriter.buildMetaAppendRow`).
  String get sheetToken => switch (this) {
    SetFeedback.none => '',
    SetFeedback.up => 'u',
    SetFeedback.down => 'd',
  };
}

/// Parses one feedback token from the sheet — blank or unrecognized
/// defaults to [SetFeedback.none] (including every set logged before this
/// was tracked).
SetFeedback setFeedbackFromSheetToken(String raw) {
  switch (raw.trim()) {
    case 'u':
      return SetFeedback.up;
    case 'd':
      return SetFeedback.down;
    default:
      return SetFeedback.none;
  }
}

/// Parses one feedback value from the JSON workout-draft blob (stored as
/// the enum's [SetFeedback.name]) — null/unrecognized defaults to
/// [SetFeedback.none]. Distinct wire format from [setFeedbackFromSheetToken]
/// (sheet uses a 1-char token, the draft uses the enum name) — don't mix them.
SetFeedback setFeedbackFromJson(String? raw) {
  switch (raw) {
    case 'up':
      return SetFeedback.up;
    case 'down':
      return SetFeedback.down;
    default:
      return SetFeedback.none;
  }
}
