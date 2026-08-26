/// ISO-8601 week-number calculation.
///
/// VERIFY BEFORE PHASE 2 WRITES: this assumes the sheet's existing week
/// numbers are true ISO-8601 week numbers (Monday-start weeks, week 1 is
/// the week containing the year's first Thursday). Spot-check a few real
/// remembered workout dates against the actual week numbers already in the
/// sheet before trusting this for writes — if the sheet instead used a
/// simpler `dayOfYear ~/ 7` scheme, [isoWeekNumber]/[isoWeekYear] below need
/// to be swapped for that scheme instead.
library;

/// Returns the ISO-8601 week number (1-53) for [date].
int isoWeekNumber(DateTime date) {
  final thursday = _thursdayOfSameIsoWeek(date);
  final firstDayOfYear = DateTime.utc(thursday.year, 1, 1);
  final dayOfYear = thursday.difference(firstDayOfYear).inDays;
  return (dayOfYear / 7).floor() + 1;
}

/// Returns the ISO week-numbering year for [date] (can differ from
/// `date.year` for a few days at the very start/end of the calendar year).
int isoWeekYear(DateTime date) => _thursdayOfSameIsoWeek(date).year;

/// Best-effort Monday date for ([isoYear], [isoWeek]), used only as a
/// fallback x-axis label for legacy sheet data logged before the app
/// existed (and so has no exact date in a metadata tab).
DateTime approximateDateForIsoWeek(int isoYear, int isoWeek) {
  final jan4 = DateTime.utc(isoYear, 1, 4);
  final jan4IsoWeekday = jan4.weekday;
  final mondayOfWeek1 = jan4.subtract(Duration(days: jan4IsoWeekday - 1));
  return mondayOfWeek1.add(Duration(days: (isoWeek - 1) * 7));
}

DateTime _thursdayOfSameIsoWeek(DateTime date) {
  final utcDate = DateTime.utc(date.year, date.month, date.day);
  // DateTime.weekday: Monday = 1 ... Sunday = 7.
  final isoWeekday = utcDate.weekday;
  return utcDate.add(Duration(days: 4 - isoWeekday));
}
