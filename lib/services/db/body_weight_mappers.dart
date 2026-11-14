import '../../models/body_weight_entry.dart';

BodyWeightEntry bodyWeightEntryFromRow(Map<String, Object?> row) =>
    BodyWeightEntry(
      date: DateTime.parse(row['date'] as String),
      weightKg: (row['weight_kg'] as num).toDouble(),
      rowIndex: row['sheet_row_index'] as int? ?? -1,
    );

Map<String, Object?> bodyWeightEntryToRow(BodyWeightEntry entry) => {
  'date': entry.date.toIso8601String().split('T').first,
  'weight_kg': entry.weightKg,
  'sheet_row_index': entry.rowIndex < 0 ? null : entry.rowIndex,
};
