import '../data/repositories/coin_repository.dart';

/// 金币系统（业务层）
///
/// 数据持久化交给 [CoinRepository]，这里负责：
/// - 统一对外 API（添加奖励 / 消费金币）
/// - 未来可扩展：成就、倍率、惩罚规则等
class CoinService {
  CoinService(this._repo);

  final CoinRepository _repo;

  Stream<int> watchTotalCoins() => _repo.watchTotalCoins();

  Future<int> getTotalCoins() => _repo.getTotalCoins();

  Future<int> getTotalFocusMinutes() => _repo.getTotalFocusMinutes();

  Stream<int> watchTotalFocusMinutes() => _repo.watchTotalFocusMinutes();

  /// 添加一次专注奖励（金币 + 专注分钟）
  Future<void> addFocusReward({
    required int coinsEarned,
    required int focusMinutes,
  }) async {
    await _repo.addCoinsAndMinutes(
      coins: coinsEarned,
      focusMinutes: focusMinutes,
    );
  }

  /// 消费金币（用于购买树种等）
  ///
  /// 返回：是否消费成功（金币不足则 false）
  Future<bool> spendCoins(int amount) => _repo.spendCoins(amount);
}

