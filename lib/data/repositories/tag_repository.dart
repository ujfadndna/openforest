import 'dart:async';

import '../database.dart';
import '../models/tag_model.dart';

class TagRepository {
  TagRepository(this._db);

  final AppDatabase _db;

  final _controller = StreamController<List<TagModel>>.broadcast();

  Stream<List<TagModel>> watchTags() => _controller.stream;

  Future<List<TagModel>> getTags() async {
    final rows = await _db.select('SELECT id, name, color FROM tags ORDER BY id ASC;');
    return rows.map(_map).toList(growable: false);
  }

  Future<void> addTag(String name, int colorValue) async {
    await _assertUnique(name: name, colorValue: colorValue);
    await _db.insert(
      'INSERT INTO tags (name, color) VALUES (?, ?);',
      [name, colorValue],
    );
    await _notify();
  }

  Future<void> updateTag(int id, String name, int colorValue) async {
    await _assertUnique(name: name, colorValue: colorValue, excludeId: id);
    await _db.update(
      'UPDATE tags SET name = ?, color = ? WHERE id = ?;',
      [name, colorValue, id],
    );
    await _notify();
  }

  Future<void> deleteTag(int id) async {
    await _db.delete('DELETE FROM tags WHERE id = ?;', [id]);
    await _notify();
  }

  Future<void> _assertUnique({
    required String name,
    required int colorValue,
    int? excludeId,
  }) async {
    final existing = await getTags();
    for (final t in existing) {
      if (excludeId != null && t.id == excludeId) continue;
      if (t.name == name) throw TagException('标签名"$name"已存在');
      if (t.colorValue == colorValue) throw TagException('该颜色已被标签"${t.name}"使用');
    }
  }

  Future<void> _notify() async {
    final tags = await getTags();
    if (!_controller.isClosed) _controller.add(tags);
  }

  void dispose() {
    _controller.close();
  }

  TagModel _map(Map<String, Object?> row) {
    return TagModel(
      id: row['id'] as int?,
      name: row['name'] as String,
      colorValue: row['color'] as int,
    );
  }
}

class TagException implements Exception {
  TagException(this.message);
  final String message;
  @override
  String toString() => message;
}
