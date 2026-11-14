import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'db_factory.dart';
import 'schema.dart';

/// Opens (once) and holds the app's local sqflite database — the source of
/// truth as of v3.0.0. Google Sheets is a connected, optional backup; see
/// `sheet_push_service.dart`/`sheet_import_service.dart`.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static Future<AppDatabase>? _opening;

  /// Safe to call repeatedly — returns the same instance once opened.
  static Future<AppDatabase> open() {
    return _opening ??= _openNew();
  }

  static Future<AppDatabase> _openNew() async {
    final factory = resolveDatabaseFactory();
    String path;
    if (kIsWeb) {
      path = 'gym_tracker.db';
    } else {
      final dir = await factory.getDatabasesPath();
      path = p.join(dir, 'gym_tracker.db');
    }

    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: kSchemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          for (final statement in kSchemaStatements) {
            await db.execute(statement);
          }
        },
      ),
    );
    return AppDatabase._(db);
  }
}
