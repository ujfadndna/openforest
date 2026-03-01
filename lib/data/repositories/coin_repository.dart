import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database.dart';

/// 金币/解锁数据仓库（持久化层）
///
/// - 负责 user_coins 与 unlocked_trees 表的读写
/// - 提供简单的 Stream（通过手动 refresh 推送），便于 Riverpod/Widget 实时刷新
class CoinRepository {
  CoinRepository(this._db) {
    // 初次创建时拉取一次最新值，避免 UI 初始为空
    unawaited(refreshAll().catchError((e) {
      debugPrint('CoinRepository init error: $e');
    }));
  }

  final AppDatabase _db;

  final _coinsController = StreamController<int>.broadcast();
  final _minutesController = StreamController<int>.broadcast();
  final _unlockedTreesController = StreamController<Set<String>>.broadcast();

  Stream<int> watchTotalCoins() => _coinsController.stream;

  Stream<int> watchTotalFocusMinutes() => _minutesController.stream;

  Stream<Set<String>> watchUnlockedTreeIds() => _unlockedTreesController.stream;

  Future<int> getTotalCoins() async {
    final row = await _getUserCoinsRow();
    return row.totalCoins;
  }

  Future<int> getTotalFocusMinutes() async {
    final row = await _getUserCoinsRow();
    return row.totalFocusMinutes;
  }

  Future<Set<String>> getUnlockedTreeIds() async {
    final rows = await _db.select('SELECT tree_id FROM unlocked_trees;', const []);
    return rows
        .map((e) => (e['tree_id'] as String?) ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// 增加金币与专注分钟（完成专注时调用）
  Future<void> addCoinsAndMinutes({
    required int coins,
    required int focusMinutes,
  }) async {
    await _db.update(
      'UPDATE user_coins SET total_coins = total_coins + ?, total_focus_minutes = total_focus_minutes + ? WHERE id = 1;',
      [coins, focusMinutes],
    );
    await refreshAll();
  }

  /// 消费金币（例如购买树种）
  ///
  /// 使用 SQL 条件更新，避免并发时出现负数。
  Future<bool> spendCoins(int amount) async {
    if (amount <= 0) return true;
    final changed = await _db.update(
      'UPDATE user_coins SET total_coins = total_coins - ? WHERE id = 1 AND total_coins >= ?;',
      [amount, amount],
    );
    await refreshAll();
    return changed > 0;
  }

  /// 解锁树种（写入 unlocked_trees 表）
  Future<void> unlockTree(String treeId) async {
    if (treeId.isEmpty) return;
    await _db.insert(
      'INSERT OR IGNORE INTO unlocked_trees (tree_id, unlocked_at) VALUES (?, ?);',
      [treeId, DateTime.now().millisecondsSinceEpoch],
    );
    await refreshAll();
  }

  /// 刷新所有缓存流（金币/分钟/解锁树）
  Future<void> refreshAll() async {
    final row = await _getUserCoinsRow();
    if (!_coinsController.isClosed) _coinsController.add(row.totalCoins);
    if (!_minutesController.isClosed) _minutesController.add(row.totalFocusMinutes);
    final unlocked = await getUnlockedTreeIds();
    if (!_unlockedTreesController.isClosed) _unlockedTreesController.add(unlocked);
  }

  Future<_UserCoinsRow> _getUserCoinsRow() async {
    final rows = await _db.select(
      'SELECT total_coins, total_focus_minutes FROM user_coins WHERE id = 1;',
      const [],
    );
    if (rows.isEmpty) {
      // 理论上不会发生（ensureInitialized 会插入），但这里做一次兜底。
      await _db.insert(
        'INSERT OR IGNORE INTO user_coins (id, total_coins, total_focus_minutes) VALUES (1, 0, 0);',
        const [],
      );
      return const _UserCoinsRow(totalCoins: 0, totalFocusMinutes: 0);
    }

    final r = rows.first;
    final coins = (r['total_coins'] as int?) ?? 0;
    final minutes = (r['total_focus_minutes'] as int?) ?? 0;
    return _UserCoinsRow(totalCoins: coins, totalFocusMinutes: minutes);
  }

  @mustCallSuper
  void dispose() {
    _coinsController.close();
    _minutesController.close();
    _unlockedTreesController.close();
  }
}

class _UserCoinsRow {
  const _UserCoinsRow({required this.totalCoins, required this.totalFocusMinutes});

  final int totalCoins;
  final int totalFocusMinutes;
}

