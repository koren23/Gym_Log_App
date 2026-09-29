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
    version: '1.3.1',
    date: '2026-09-29',
    changes: [
      'Removed the Program feature added in 1.3.0 (per-exercise sets/rep '
          'targets, editable from Home) — reverted to the simpler '
          'workout-day system from before.',
    ],
  ),
  ChangelogEntry(
    version: '1.3.0',
    date: '2026-09-29',
    changes: [
      'Renamed "premade workout" to Program and moved editing to the '
          'Homepage — every day card in "This week" now has an Edit '
          'program button, and it\'s gone from Settings.',
      'A program now sets a target number of sets and a rep range per '
          'exercise (not just a name list), edited in a screen grouped by '
          'muscle, matching the log page.',
      'Logging now shows both "Last time" and the program\'s "Target: N '
          'sets · X-Y reps" together on each exercise, and the rep-range '
          'hint/starting set count use the program\'s target when there\'s '
          'no history yet.',
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
      'Added premade workout templates: save a planned exercise list/order '
          'per workout day, edit it any time, and it now drives the '
          'suggested checklist and order for that day.',
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
