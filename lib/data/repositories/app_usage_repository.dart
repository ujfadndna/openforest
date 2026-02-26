import '../database.dart';
import '../models/app_usage_model.dart';

class AppUsageRepository {
  AppUsageRepository(this._db);

  final AppDatabase _db;

  Future<void> addUsage(AppUsageModel usage) async {
    await _db.insert(
      'INSERT INTO app_usages (session_id, app_name, window_title, duration_seconds, recorded_at) VALUES (?, ?, ?, ?, ?);',
      [
        usage.sessionId,
        usage.appName,
        usage.windowTitle,
        usage.durationSeconds,
        usage.recordedAt.millisecondsSinceEpoch,
      ],
    );
  }

  Future<List<AppUsageModel>> getUsagesBySession(int sessionId) async {
    final rows = await _db.select(
      'SELECT * FROM app_usages WHERE session_id = ? ORDER BY recorded_at ASC;',
      [sessionId],
    );
    return rows.map(_map).toList(growable: false);
  }

  Future<List<AppUsageModel>> getUsagesBetween(DateTime start, DateTime end) async {
    final rows = await _db.select(
      'SELECT * FROM app_usages WHERE recorded_at >= ? AND recorded_at < ? ORDER BY recorded_at ASC;',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return rows.map(_map).toList(growable: false);
  }

  AppUsageModel _map(Map<String, Object?> row) {
    return AppUsageModel(
      id: row['id'] as int?,
      sessionId: row['session_id'] as int?,
      appName: row['app_name'] as String,
      windowTitle: row['window_title'] as String?,
      durationSeconds: row['duration_seconds'] as int,
      recordedAt: DateTime.fromMillisecondsSinceEpoch(row['recorded_at'] as int),
    );
  }
}
