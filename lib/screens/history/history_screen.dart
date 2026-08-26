import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/muscle_groups.dart';
import '../../core/utils/text.dart';
import '../../models/history_entry.dart';
import '../../models/year_sheet_data.dart';
import '../../providers/analysis_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';
import 'edit_visit_screen.dart';

/// A month calendar: days with a logged workout are marked, tapping a day
/// expands that day's workout(s) below the grid.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  DateTime? _focusedMonth;
  DateTime? _selectedDate;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final snapshotState = ref.watch(snapshotProvider).value;
    final yearsAscending = snapshotState?.snapshot.yearData.values.toList()
      ?..sort((a, b) => a.year.compareTo(b.year));

    if (yearsAscending == null || yearsAscending.isEmpty) {
      return const Center(child: Text('No logged workouts yet.'));
    }

    final entries = buildHistoryEntries(
      yearsAscending,
      workoutDays: ref.watch(workoutDayDefsProvider),
    ); // most-recent first
    final byDate = <DateTime, List<HistoryEntry>>{};
    for (final e in entries) {
      byDate.putIfAbsent(_dateOnly(e.date), () => []).add(e);
    }

    final mostRecentDate = entries.isNotEmpty
        ? _dateOnly(entries.first.date)
        : null;
    _focusedMonth ??= mostRecentDate != null
        ? DateTime(mostRecentDate.year, mostRecentDate.month)
        : DateTime.now();
    _selectedDate ??= mostRecentDate;

    final selectedEntries = _selectedDate == null
        ? const <HistoryEntry>[]
        : (byDate[_selectedDate] ?? const []);
    final yearDataByYear = {for (final y in yearsAscending) y.year: y};
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          _MonthHeader(
            month: _focusedMonth!,
            onPrevious: () => setState(
              () => _focusedMonth = DateTime(
                _focusedMonth!.year,
                _focusedMonth!.month - 1,
              ),
            ),
            onNext: () => setState(
              () => _focusedMonth = DateTime(
                _focusedMonth!.year,
                _focusedMonth!.month + 1,
              ),
            ),
          ),
          _CalendarGrid(
            month: _focusedMonth!,
            markedDates: byDate.keys.toSet(),
            selectedDate: _selectedDate,
            onSelect: (date) => setState(() => _selectedDate = date),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: _selectedDate == null
                  ? Text(
                      'No workouts logged yet.',
                      style: theme.textTheme.bodyMedium,
                    )
                  : _DayDetail(
                      date: _selectedDate!,
                      entries: selectedEntries,
                      yearDataByYear: yearDataByYear,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrevious),
        Text(
          DateFormat('MMMM yyyy').format(month),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.markedDates,
    required this.selectedDate,
    required this.onSelect,
  });

  final DateTime month;
  final Set<DateTime> markedDates;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelect;

  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstOfMonth = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks =
        firstOfMonth.weekday % 7; // Sunday(7)->0 ... Saturday(6)->6

    return GridView.count(
      crossAxisCount: 7,
      childAspectRatio: 1.5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final label in _weekdayLabels)
          Center(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
        for (var day = 1; day <= daysInMonth; day++)
          _DayCell(
            date: DateTime(month.year, month.month, day),
            marked: markedDates.contains(
              DateTime(month.year, month.month, day),
            ),
            selected:
                selectedDate != null &&
                selectedDate!.year == month.year &&
                selectedDate!.month == month.month &&
                selectedDate!.day == day,
            onTap: () => onSelect(DateTime(month.year, month.month, day)),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.marked,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final bool marked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? theme.colorScheme.primary : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  color: selected ? Colors.white : theme.colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              if (marked && !selected)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayDetail extends StatelessWidget {
  const _DayDetail({
    required this.date,
    required this.entries,
    required this.yearDataByYear,
  });

  final DateTime date;
  final List<HistoryEntry> entries;
  final Map<int, YearSheetData> yearDataByYear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, MMM d, yyyy').format(date),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text(
              'No workout logged this day.',
              style: theme.textTheme.bodyMedium,
            )
          else
            for (final entry in entries) ...[
              _EntryDetail(
                entry: entry,
                yearData: yearDataByYear[entry.isoYear],
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _EntryDetail extends StatelessWidget {
  const _EntryDetail({required this.entry, required this.yearData});

  final HistoryEntry entry;
  final YearSheetData? yearData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = workoutDayForGroupLabels(entry.muscleGroups);
    final note =
        entry.metaRow?.note ?? yearData?.weekNotes[entry.isoWeek];
    final dayLabel = day?.label ??
        (entry.muscleGroups.isEmpty
            ? null
            : entry.muscleGroups.map(titleCase).join(', '));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (dayLabel != null)
              Flexible(
                child: Text(
                  dayLabel,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            if (entry.metaRow?.rating != null) ...[
              const Icon(Icons.star, size: 14, color: Colors.amber),
              const SizedBox(width: 2),
              Text(
                entry.metaRow!.rating!.toStringAsFixed(1),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (entry.isSynthetic) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.table_chart_outlined,
                size: 14,
                color: theme.colorScheme.outline,
              ),
            ],
            if (entry.metaRow != null) ...[
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit or delete this workout',
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditVisitScreen(
                      metaRow: entry.metaRow!,
                      initialNote:
                          entry.metaRow!.note ??
                          (day == null
                              ? null
                              : yearData?.weekNotesByGroup[primaryGroupForDay(
                                  day,
                                )]?[entry.isoWeek]),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        for (final name in entry.exerciseNames)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(name, style: theme.textTheme.bodyMedium),
          ),
        if (note != null && note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '📝 $note',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        if (entry.isSynthetic)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Typed directly into the sheet — exact date approximated.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }
}
