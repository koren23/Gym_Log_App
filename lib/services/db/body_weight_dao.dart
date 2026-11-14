import 'package:sqflite/sqflite.dart';

import '../../models/body_weight_entry.dart';
import 'app_database.dart';
import 'body_weight_mappers.dart';

class BodyWeightDao {
  BodyWeightDao(this._db);

  final AppDatabase _db;

  Future<List<BodyWeightEntry>> getAll() async {
    final rows = await _db.db.query('body_weight_entries', orderBy: 'date ASC');
    return rows.map(bodyWeightEntryFromRow).toList();
  }

  /// One entry per day — a new entry on an existing date overwrites it.
  Future<void> upsert(BodyWeightEntry entry) async {
    await _db.db.insert(
      'body_weight_entries',
      bodyWeightEntryToRow(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteByDate(DateTime date) async {
    await _db.db.delete(
      'body_weight_entries',
      where: 'date = ?',
      whereArgs: [date.toIso8601String().split('T').first],
    );
  }
}
