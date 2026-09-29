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
    version: '1.0.0',
    date: '2026-01-01',
    changes: ['Initial release.'],
  ),
];
