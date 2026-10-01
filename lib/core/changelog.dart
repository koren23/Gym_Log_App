/// Hand-maintained "what's new" history shown in Settings. Prepend a new
/// entry here (and bump `pubspec.yaml`'s `version:`) each time a further
/// change ships — this file is the single source of truth for the
/// changelog screen's content.
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });

  final String version;
  final String date;
  final List<String> changes;
}

const List<ChangelogEntry> kChangelog = [
  ChangelogEntry(
    version: '1.4.2',
    date: '2026-10-01',
    changes: [
      'Fixed the "not 100%" flag (and a visit note) reverting after fully '
          'closing and reopening the app: the startup data fetch was '
          'silently requesting a column range that cut off those fields, '
          'so the correct value was saved to the sheet but never read back.',
    ],
  ),
  ChangelogEntry(
    version: '1.4.1',
    date: '2026-10-01',
    changes: [
      'Fixed the "not 100%" flag still reverting: saving a workout\'s note '
          'afterward could re-fetch from the sheet before the flag had '
          'finished saving there, silently undoing it. Note saves now '
          'always happen first.',
      'Fixed an already-logged exercise using bodyweight or a custom unit '
          'showing as reset to kg when reopening it to edit, which could '
          'also wrongly block saving a bodyweight set logged as 0.',
    ],
  ),
  ChangelogEntry(
    version: '1.4.0',
    date: '2026-09-30',
    changes: [
      'Fixed a newly-created exercise reappearing on the log page after '
          'being deleted.',
      'Added a Settings action to fill in any exercise missing a unit or '
          'muscle group in the Exercises sheet, without touching entries '
          'that are already set.',
      'You can now add a free-text note to a specific exercise, or to a '
          'specific set, while logging or editing a workout — shown in '
          'History alongside that exercise.',
      'Fixed "Feeling sick / not 100%?" not actually excluding that '
          'workout from Home\'s "last workout" card or the next session\'s '
          '"Last time" weight hint.',
      'History/Calendar now shows a "Not 100%" label on a workout marked '
          'that way.',
      'Fixed the "not 100%" checkbox sometimes showing unchecked again '
          'right after saving it, when reopening the same workout to edit.',
    ],
  ),
  ChangelogEntry(
    version: '1.2.0',
    date: '2026-09-29',
    changes: [
      'Fixed exercise-unit edits not always saving (and losing the unit '
          'if the app restarted mid-session) — a failed save is now '
          'queued and retried automatically instead of silently lost.',
      'This changelog is now built from the app\'s real release history '
          'instead of placeholder text.',
      'History now shows the correct day name for older workouts logged '
          'before day-tagging existed, matching what Home shows.',
      'The Graphs page now defaults to Body weight, and charts can be '
          'zoomed in further (including scroll-wheel/trackpad zoom on '
          'desktop and web).',
      'Marking a workout "Feeling sick / not 100%?" now excludes it from '
          'weight/volume/plateau suggestions too, not just star ratings — '
          'the last normal session becomes the reference instead.',
      'The "~" (approximate) marker on a set now gives it a real ±1 rep '
          'tolerance in suggestion logic, not just a cosmetic label.',
      'The History/edit-workout page now supports full exercise editing '
          '(name, muscle, unit, delete) and shows a "last time" preview, '
          'matching the log page.',
      'Fixed a new custom workout day sometimes prefilling with another '
          'day\'s exercises via a muscle-overlap false match.',
    ],
  ),
  ChangelogEntry(
    version: '1.1.0',
    date: '2026-09-29',
    changes: [
      'Fixed the History/Calendar page showing the wrong workout name for '
          'custom workout days (it now matches what Home shows).',
      'You can now rename an exercise, change its muscle group, and change '
          'its unit from the log page\'s edit-exercise dialog — all three '
          'now stick for future logs, not just the current one.',
      'Added a way to delete an accidentally-created exercise, gated '
          'behind a deliberate confirmation (a cooldown, then typing the '
          'exercise name, then a final confirm).',
      'Added this "What\'s new" changelog to Settings.',
      'Suggested-next-exercise logic now skips a muscle group you already '
          'covered this session with a substitute exercise, and correctly '
          'recommends whatever you skipped if you do your usual exercises '
          'out of order.',
    ],
  ),
  ChangelogEntry(
    version: '1.0.8',
    date: '2026-09-23',
    changes: [
      'Removed exercise-unit editing from Settings (now edited from the '
          'log page only).',
    ],
  ),
  ChangelogEntry(
    version: '1.0.7',
    date: '2026-09-23',
    changes: ['Added a tappable unit chip directly on each exercise in the log page.'],
  ),
  ChangelogEntry(
    version: '1.0.6',
    date: '2026-09-23',
    changes: [
      "Every exercise's unit (kg/bodyweight/time/custom) now saves to the "
          'Exercises sheet.',
    ],
  ),
  ChangelogEntry(
    version: '1.0.5',
    date: '2026-09-23',
    changes: [
      'Fixed exercise-unit save failing when the Exercises tab doesn\'t '
          'exist yet.',
    ],
  ),
  ChangelogEntry(
    version: '1.0.4',
    date: '2026-09-22',
    changes: [
      'Fixed silent unit-edit save failures.',
      'Grouped Settings exercises by muscle.',
      'Added support for adding/removing an exercise when editing a '
          'logged workout.',
    ],
  ),
  ChangelogEntry(
    version: '1.0.3',
    date: '2026-09-20',
    changes: [
      "Added a unit-edit button directly on each exercise's log-page row.",
    ],
  ),
  ChangelogEntry(
    version: '1.0.2',
    date: '2026-09-20',
    changes: [
      'Updated docs for weight-units/suggestion-variety features and fixed '
          'remaining gaps.',
    ],
  ),
  ChangelogEntry(
    version: '1.0.1',
    date: '2026-09-20',
    changes: [
      'Added per-exercise weight units and varied, actionable post-workout '
          'suggestions.',
    ],
  ),
  ChangelogEntry(
    version: '1.0.0',
    date: '2026-08-26',
    changes: [
      'Initial release: Google Sheets-backed workout tracker for '
          'Android, iOS, and web.',
      'Added one-workout-per-day support, per-set feedback/trends, a '
          'draft-persistence fix, a last-workout preview, and fixes for '
          'phantom workouts/typing jank.',
      'Replaced web Google sign-in with an OAuth PKCE refresh-token flow.',
      'Fixed phantom history entries for weeks with a pre-workoutDayId '
          'visit.',
    ],
  ),
];
