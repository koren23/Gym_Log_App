/// Local sqflite schema — the app's source of truth as of v3.0.0. Google
/// Sheets is a connected, optional backup; see `sheet_push_service.dart` and
/// `sheet_import_service.dart`. No incremental-sync cursors — this is a
/// single user's dataset (low thousands of rows at most), so a full
/// reconcile pass on import is simple and fast enough.
const int kSchemaVersion = 2;

const List<String> kSchemaStatements = [
  '''
  CREATE TABLE exercises (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    name_lower TEXT NOT NULL UNIQUE,
    muscle_group TEXT NOT NULL,
    muscle_group_known INTEGER NOT NULL DEFAULT 1,
    unit TEXT NOT NULL DEFAULT 'kg',
    custom_unit_label TEXT,
    secondary_muscle_groups TEXT NOT NULL DEFAULT '',
    notes TEXT,
    photo_asset_key TEXT,
    deleted_at TEXT
  )
  ''',
  '''
  CREATE TABLE workout_day_defs (
    id TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    muscle_groups TEXT NOT NULL,
    legacy_day TEXT,
    sheet_row_index INTEGER,
    deleted_at TEXT
  )
  ''',
  '''
  CREATE TABLE workout_visits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    visit_id TEXT NOT NULL UNIQUE,
    date TEXT NOT NULL,
    iso_week INTEGER NOT NULL,
    iso_year INTEGER NOT NULL,
    rating REAL,
    rating_relevance TEXT NOT NULL DEFAULT 'normal',
    note TEXT,
    workout_day_id TEXT,
    is_synthetic INTEGER NOT NULL DEFAULT 0,
    exact_date_known INTEGER NOT NULL DEFAULT 1,
    source_tab TEXT,
    sheet_meta_row_index INTEGER,
    needs_sheet_push INTEGER NOT NULL DEFAULT 0,
    deleted_at TEXT
  )
  ''',
  '''
  CREATE INDEX idx_workout_visits_date ON workout_visits (date)
  ''',
  '''
  CREATE TABLE exercise_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    visit_id INTEGER NOT NULL REFERENCES workout_visits (id) ON DELETE CASCADE,
    exercise_name TEXT NOT NULL,
    position INTEGER NOT NULL,
    target_rep_range_low INTEGER NOT NULL,
    target_rep_range_high INTEGER NOT NULL
  )
  ''',
  '''
  CREATE INDEX idx_exercise_entries_visit ON exercise_entries (visit_id)
  ''',
  '''
  CREATE TABLE exercise_sets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id INTEGER NOT NULL REFERENCES exercise_entries (id) ON DELETE CASCADE,
    set_index INTEGER NOT NULL,
    weight REAL NOT NULL,
    reps INTEGER NOT NULL,
    approx_reps INTEGER NOT NULL DEFAULT 0,
    feedback TEXT NOT NULL DEFAULT 'none',
    target_low INTEGER,
    target_high INTEGER,
    target_weight REAL
  )
  ''',
  '''
  CREATE INDEX idx_exercise_sets_entry ON exercise_sets (entry_id)
  ''',
  '''
  CREATE TABLE exercise_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    visit_id INTEGER NOT NULL REFERENCES workout_visits (id) ON DELETE CASCADE,
    exercise_name TEXT NOT NULL,
    set_index INTEGER,
    text TEXT NOT NULL,
    sheet_row_index INTEGER
  )
  ''',
  '''
  CREATE INDEX idx_exercise_notes_visit ON exercise_notes (visit_id)
  ''',
  '''
  CREATE TABLE body_weight_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL UNIQUE,
    weight_kg REAL NOT NULL,
    sheet_row_index INTEGER
  )
  ''',
  '''
  CREATE TABLE sync_meta (
    key TEXT PRIMARY KEY,
    value TEXT
  )
  ''',
];

/// Upgrade statements keyed by the version being upgraded *to*. Applied in
/// order for every version between the database's current version and
/// [kSchemaVersion] — see `AppDatabase._openNew`'s `onUpgrade`. A fresh
/// install never runs these; it gets the current shape straight from
/// [kSchemaStatements].
const Map<int, List<String>> kSchemaUpgrades = {
  2: [
    'ALTER TABLE exercises ADD COLUMN notes TEXT',
    'ALTER TABLE exercises ADD COLUMN photo_asset_key TEXT',
  ],
};
