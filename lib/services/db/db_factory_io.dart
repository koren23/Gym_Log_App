import 'package:sqflite/sqflite.dart';

/// Native (Android/iOS/desktop) build target — sqflite's own default
/// factory already talks to the platform's real SQLite, so there's nothing
/// to override.
DatabaseFactory resolveDatabaseFactory() => databaseFactory;
