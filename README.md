# Koren's Gym Log

A native Flutter Android app that reads and writes directly to a Google Sheet used
to track gym workouts, body weight, and progress over time. No separate backend —
the Sheet itself is the database.

## Features

- **Log workouts** for any workout day you define yourself (Settings →
  "Workout days" — name it anything, pick which muscles belong to it;
  supports splits like Push/Legs_A/Pull/Legs_B or Arms+Shoulders/Chest+Back/
  Legs). Push/Pull/Legs/Full Body are seeded the first time you use the app,
  but they're ordinary workout days from then on — rename, edit, or delete
  them like any other. Workout days are backed up to your sheet's
  `WorkoutDays` tab, so they survive an app reinstall or a new device. Each
  entry supports per-set weight and reps (editable from either the checklist
  or the "Workout so far" summary at the top), a picked date (defaults to
  today — can be backdated, or changed later from Edit), an optional "~"
  marker for approximate rep counts, and an optional session rating set by
  dragging directly on the star row, plus a "feeling sick?" flag (normal /
  half-related / not related) so a day you weren't feeling well doesn't
  distort the trend analysis. Adding a new exercise always asks which muscle
  it belongs to. The default number of sets for a new entry comes from your
  own logging history for that exercise, not a fixed number.
- **Edit a past workout**: adjust each set's weight and reps individually
  (not just an averaged number), reorder exercises, edit the note/rating/
  feeling-sick flag, change the date (including moving it to a different
  week or year — requires a live connection), or delete the visit.
- **Log body weight** entries from a dedicated FAB on the home screen.
- **Home tab**: a "Last few weeks" insight box (auto-detects improving vs.
  stuck exercises from recent history) above an accordion showing this
  week's most recent session per workout day you've defined.
- **Graphs tab**: searchable picker (by exercise, muscle group, or body weight)
  driving a line chart of progress over time, with a sets×reps tooltip on
  exercise points.
- **History tab**: browse and edit past workout sessions.
- **Progress detection**: on-device trend/plateau analysis that also factors
  in training volume (sets×reps), body-weight trend, and the feeling-sick
  flag — a slight dip in lifting weight during a deliberate cut isn't read
  as a stall, and a rating from a day you were sick doesn't get treated like
  a normal one. Post-workout notifications only surface for exercises that
  are genuinely stuck or whose ratings are declining. See Settings → "How
  suggestions work" for the full plain-language explanation.
- **Settings**: pick from named color themes (light and dark presets) or
  customize the app's four accent colors individually; set the default rep
  range used when starting a new exercise entry; and define your own workout
  days (see above).
- Signs in with Google and syncs against the user's own Google Sheet
  (spreadsheet ID/URL entered once during onboarding).

## Sheet format

A year tab can use any of three layouts, auto-detected per tab so all three
read correctly side by side forever with no migration:

- **Current grouped** (the layout you hand-maintain today): column A
  alternates between muscle-name section-header rows (e.g. "upper chest",
  "triceps") and the exercise rows beneath them — color-coding the header
  rows differently is just for your own readability, the app only reads the
  text. This is the primary source of exercise -> muscle categorization; you
  can add a brand-new muscle's section anywhere and the app picks it up, and
  logging a new exercise under a muscle with no section yet creates one
  automatically at the bottom of the tab.
- **Legacy grouped** (2025 and earlier): the older Push/Chest/Shoulders/...
  section-header layout — kept forever exactly as-is.
- **Flat** (no section headers at all): exercise rows × week columns only,
  muscle resolved from other years' data or the optional `Exercises` tab.

The full current muscle taxonomy (18 values: upper chest, lower chest,
triceps, lateral delt, front delt, abdominals, obliques, upper back, lats,
biceps, brachialis, rear delt, forearm, quads, glutes, hamstrings, calves,
lower back) lives in the app's `MuscleGroup` enum
(`lib/core/constants/muscle_groups.dart`) — add a new value there to
recognize a muscle you don't see yet. A handful of pluralized/abbreviated
header spellings ("front delts", "lateral delts", "abs", "hams") are
tolerated automatically via an alias table in that same file. The
`Exercises` reference tab (one column per muscle) is now entirely optional —
kept only as a fallback name->muscle source if present, not required. Workout
day definitions live in a `WorkoutDays` tab (id/label/muscleGroups columns),
auto-created the first time you use the app, and are fully editable
(add/edit/remove muscles or rename) from Settings.

## Project layout

```
lib/
  app.dart                   Theme construction (brightness-aware, from AppColors)
  main.dart                  Entry point
  core/
    constants/                Muscle group definitions, OAuth config, sheet layout
    utils/                    ISO week math, Result type, text helpers
  models/                    Plain data classes (Exercise, HistoryEntry, AppColors, ...)
  providers/                 Riverpod providers (auth, settings, sheet data, analysis)
  services/
    analysis/                 Trend/plateau detection (AnalysisEngine)
    auth/                      Google sign-in
    settings/                  Local app settings persistence
    sheets/                    Google Sheets read/write/parsing
    sync/                      Pending-sync queue (offline writes)
  screens/                   One folder per feature area (home, graphs, history,
                              log_workout, body_weight, settings, onboarding, root)
  widgets/                    Shared widgets (charts, insight box, exercise tiles, ...)
test/
  unit/                      Pure-logic tests (iso week math, sheet writer, analysis, ...)
  widget_test.dart           Onboarding smoke test
```

## Building

```
flutter pub get
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`. Application ID:
`com.korengym.gym_tracker`.

## Installing

```
adb install -r app-release.apk
```

(or copy `app-release.apk` to the phone and open it directly).
