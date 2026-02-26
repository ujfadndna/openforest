import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/coin_service.dart';
import '../../data/models/tree_species.dart';
import '../../data/repositories/coin_repository.dart';
import '../timer/timer_provider.dart';

/// 读取 assets/trees/trees.json
final treeSpeciesListProvider = FutureProvider<List<TreeSpecies>>((ref) async {
  final jsonStr = await rootBundle.loadString('assets/trees/trees.json');
  final raw = json.decode(jsonStr);
  if (raw is! List) return const <TreeSpecies>[];

  final list = raw
      .whereType<Map<String, dynamic>>()
      .map(TreeSpecies.fromJson)
      .toList(growable: false);

  // 确保默认解锁树写入数据库（INSERT OR IGNORE，安全可重复）
  final coinRepo = ref.read(coinRepositoryProvider);
  for (final s in list) {
    if (s.unlockedByDefault) {
      await coinRepo.unlockTree(s.id);
    }
  }

  return list;
});

final shopControllerProvider = Provider<ShopController>((ref) {
  final coinRepo = ref.read(coinRepositoryProvider);
  final coinService = ref.read(coinServiceProvider);
  return ShopController(coinService: coinService, coinRepo: coinRepo);
});

class ShopController {
  ShopController({
    required this.coinService,
    required this.coinRepo,
  });

  final CoinService coinService;
  final CoinRepository coinRepo;

  /// 购买并解锁树种
  Future<bool> buy(TreeSpecies species) async {
    if (species.price <= 0) {
      await coinRepo.unlockTree(species.id);
      return true;
    }

    final ok = await coinService.spendCoins(species.price);
    if (!ok) return false;

    await coinRepo.unlockTree(species.id);
    return true;
  }
}
