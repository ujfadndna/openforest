import '../database.dart';
import '../models/session.dart';

/// 专注记录仓库
class SessionRepository {
  SessionRepository(this._db);

  final AppDatabase _db;

  Future<void> addSession({
    required DateTime startTime,
    required DateTime endTime,
    required int durationMinutes,
    required bool completed,
    required int coinsEarned,
    required String treeSpecies,
    String? tag,
  }) async {
    await _db.insert(
      '''
INSERT INTO focus_sessions (
  start_time, end_time, duration_minutes, completed, coins_earned, tree_species, tag
) VALUES (?, ?, ?, ?, ?, ?, ?);
''',
      [
        startTime.millisecondsSinceEpoch,
        endTime.millisecondsSinceEpoch,
        durationMinutes,
        completed ? 1 : 0,
        coinsEarned,
        treeSpecies,
        tag,
      ],
    );
  }

  /// 查询时间范围内的记录（按开始时间排序）
  Future<List<FocusSessionModel>> getSessionsBetween(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _db.select(
      '''
SELECT
  id, start_time, end_time, duration_minutes, completed, coins_earned, tree_species, tag
FROM focus_sessions
WHERE start_time >= ? AND start_time < ?
ORDER BY start_time ASC;
''',
      [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );

    return rows.map(_mapRowToModel).toList(growable: false);
  }

  FocusSessionModel _mapRowToModel(Map<String, Object?> row) {
    final id = row['id'] as int?;
    final startMs = (row['start_time'] as int?) ?? 0;
    final endMs = (row['end_time'] as int?) ?? 0;
    final duration = (row['duration_minutes'] as int?) ?? 0;
    final completedInt = (row['completed'] as int?) ?? 0;
    final coins = (row['coins_earned'] as int?) ?? 0;
    final tree = (row['tree_species'] as String?) ?? 'oak';
    final tag = row['tag'] as String?;

    return FocusSessionModel(
      id: id,
      startTime: DateTime.fromMillisecondsSinceEpoch(startMs),
      endTime: DateTime.fromMillisecondsSinceEpoch(endMs),
      durationMinutes: duration,
      completed: completedInt == 1,
      coinsEarned: coins,
      treeSpecies: tree,
      tag: tag,
    );
  }
}

