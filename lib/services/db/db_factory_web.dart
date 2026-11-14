import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web build target — there's no native SQLite to call into, so this swaps
/// in the IndexedDB-backed factory from `sqflite_common_ffi_web` (see
/// `web/sqlite3.wasm` + `web/sqflite_sw.js`, installed via
/// `dart run sqflite_common_ffi_web:setup`).
DatabaseFactory resolveDatabaseFactory() => databaseFactoryFfiWeb;
