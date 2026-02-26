import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppDatabase {
  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();

  NativeDatabase? _db;
  bool _initialized = false;
  final _lock = Completer<void>();
  bool _lockStarted = false;

  Future<NativeDatabase> _getDb() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'openforest.sqlite'));
    _db = NativeDatabase(file);
    await _db!.ensureOpen(_DbUser());
    return _db!;
  }

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    if (_lockStarted) {
      await _lock.future;
      return;
    }
    _lockStarted = true;

    final db = await _getDb();

    await db.runCustom('PRAGMA foreign_keys = ON;');
    await db.runCustom('''
CREATE TABLE IF NOT EXISTS focus_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  start_time INTEGER NOT NULL,
  end_time INTEGER NOT NULL,
  duration_minutes INTEGER NOT NULL,
  completed INTEGER NOT NULL,
  coins_earned INTEGER NOT NULL,
  tree_species TEXT NOT NULL,
  tag TEXT
);
''');
    await db.runCustom('''
CREATE TABLE IF NOT EXISTS user_coins (
  id INTEGER PRIMARY KEY,
  total_coins INTEGER NOT NULL,
  total_focus_minutes INTEGER NOT NULL
);
''');
    await db.runCustom('''
CREATE TABLE IF NOT EXISTS unlocked_trees (
  tree_id TEXT PRIMARY KEY,
  unlocked_at INTEGER NOT NULL
);
''');
    await db.runCustom('''
CREATE TABLE IF NOT EXISTS tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  color INTEGER NOT NULL UNIQUE
);
''');
    await db.runCustom('''
CREATE TABLE IF NOT EXISTS app_usages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER,
  app_name TEXT NOT NULL,
  window_title TEXT,
  duration_seconds INTEGER NOT NULL,
  recorded_at INTEGER NOT NULL
);
''');
    await db.runInsert(
      'INSERT OR IGNORE INTO user_coins (id, total_coins, total_focus_minutes) VALUES (1, 0, 0);',
      const [],
    );
    await db.runInsert(
      'INSERT OR IGNORE INTO unlocked_trees (tree_id, unlocked_at) VALUES (?, ?);',
      ['oak', DateTime.now().millisecondsSinceEpoch],
    );

    _initialized = true;
    if (!_lock.isCompleted) _lock.complete();
  }

  Future<List<Map<String, Object?>>> select(String sql, [List<Object?> args = const []]) async {
    await ensureInitialized();
    return (await _getDb()).runSelect(sql, args);
  }

  Future<int> insert(String sql, [List<Object?> args = const []]) async {
    await ensureInitialized();
    return (await _getDb()).runInsert(sql, args);
  }

  Future<int> update(String sql, [List<Object?> args = const []]) async {
    await ensureInitialized();
    return (await _getDb()).runUpdate(sql, args);
  }

  Future<int> delete(String sql, [List<Object?> args = const []]) async {
    await ensureInitialized();
    return (await _getDb()).runDelete(sql, args);
  }

  Future<void> execute(String sql, [List<Object?>? args]) async {
    await ensureInitialized();
    return (await _getDb()).runCustom(sql, args);
  }

  Future<void> close() async {
    await _db?.close();
  }
}

class _DbUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}
