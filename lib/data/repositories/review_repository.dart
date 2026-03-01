import '../database.dart';

class ReviewItem {
  const ReviewItem({
    this.id,
    required this.title,
    required this.intervalDays,
    this.lastReviewedAt,
    required this.createdAt,
    required this.archived,
  });

  final int? id;
  final String title;
  final int intervalDays;
  final DateTime? lastReviewedAt;
  final DateTime createdAt;
  final bool archived;

  DateTime get _baseline => lastReviewedAt ?? createdAt;

  bool get isDue {
    return DateTime.now().difference(_baseline).inDays >= intervalDays;
  }

  int get daysUntilDue {
    final next = _baseline.add(Duration(days: intervalDays));
    final diff = next.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  int get daysSinceLastReview {
    if (lastReviewedAt == null) return -1;
    return DateTime.now().difference(lastReviewedAt!).inDays;
  }
}

class ReviewRepository {
  ReviewRepository(this._db);

  final AppDatabase _db;

  Future<List<ReviewItem>> getActiveItems() async {
    final rows = await _db.select(
      '''
SELECT id, title, interval_days, last_reviewed_at, created_at, archived
FROM review_items
WHERE archived = 0
ORDER BY created_at DESC;
''',
    );
    return rows.map(_mapRowToModel).toList(growable: false);
  }

  Future<List<ReviewItem>> getDueItems() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db.select(
      '''
SELECT id, title, interval_days, last_reviewed_at, created_at, archived
FROM review_items
WHERE archived = 0
  AND COALESCE(last_reviewed_at, created_at) + interval_days * 86400000 <= ?
ORDER BY created_at DESC;
''',
      [nowMs],
    );
    return rows.map(_mapRowToModel).toList(growable: false);
  }

  Future<int> addItem(String title, int intervalDays) async {
    return _db.insert(
      '''
INSERT INTO review_items (
  title, interval_days, created_at, archived
) VALUES (?, ?, ?, 0);
''',
      [
        title,
        intervalDays,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> markReviewed(int id) async {
    await _db.update(
      'UPDATE review_items SET last_reviewed_at = ? WHERE id = ?;',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<void> updateItem(
    int id, {
    String? title,
    int? intervalDays,
  }) async {
    if (title == null && intervalDays == null) return;
    final sets = <String>[];
    final args = <Object?>[];
    if (title != null) {
      sets.add('title = ?');
      args.add(title);
    }
    if (intervalDays != null) {
      sets.add('interval_days = ?');
      args.add(intervalDays);
    }
    args.add(id);
    await _db.update(
      'UPDATE review_items SET ${sets.join(', ')} WHERE id = ?;',
      args,
    );
  }

  Future<void> archiveItem(int id) async {
    await _db.update(
      'UPDATE review_items SET archived = 1 WHERE id = ?;',
      [id],
    );
  }

  Future<void> deleteItem(int id) async {
    await _db.delete(
      'DELETE FROM review_items WHERE id = ?;',
      [id],
    );
  }

  ReviewItem _mapRowToModel(Map<String, Object?> row) {
    final id = row['id'] as int?;
    final title = (row['title'] as String?) ?? '';
    final intervalDays = (row['interval_days'] as int?) ?? 15;
    final lastReviewedMs = row['last_reviewed_at'] as int?;
    final createdMs = (row['created_at'] as int?) ?? 0;
    final archivedInt = (row['archived'] as int?) ?? 0;

    return ReviewItem(
      id: id,
      title: title,
      intervalDays: intervalDays,
      lastReviewedAt: lastReviewedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastReviewedMs),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
      archived: archivedInt == 1,
    );
  }
}
