import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../timer/timer_provider.dart';
import '../timer/tree_painter.dart';
import 'shop_provider.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coinsAsync = ref.watch(totalCoinsProvider);
    final treesAsync = ref.watch(treeSpeciesListProvider);
    final unlockedAsync = ref.watch(unlockedTreeIdsProvider);

    final coins = coinsAsync.asData?.value ?? 0;
    final unlocked = unlockedAsync.asData?.value ?? const <String>{};

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                '商店',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              const Icon(Icons.monetization_on_outlined),
              const SizedBox(width: 6),
              Text('金币：$coins'),
            ],
          ),
        ),
        Expanded(
          child: treesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载树种失败：$e')),
            data: (trees) {
              if (trees.isEmpty) {
                return const Center(child: Text('暂无树种数据'));
              }

              return Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.86,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: trees.length,
                  itemBuilder: (context, index) {
                    final t = trees[index];
                    final isUnlocked = unlocked.contains(t.id) || t.unlockedByDefault;
                    final canBuy = coins >= t.price;
                    return _TreeCard(
                      speciesId: t.id,
                      name: t.name,
                      description: t.description,
                      price: t.price,
                      unlocked: isUnlocked,
                      canBuy: canBuy,
                      onBuy: isUnlocked
                          ? null
                          : () async {
                              final controller = ref.read(shopControllerProvider);
                              final ok = await controller.buy(t);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok ? '购买成功：已解锁 ${t.name}' : '金币不足，无法购买'),
                                ),
                              );
                            },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TreeCard extends StatelessWidget {
  const _TreeCard({
    required this.speciesId,
    required this.name,
    required this.description,
    required this.price,
    required this.unlocked,
    required this.canBuy,
    required this.onBuy,
  });

  final String speciesId;
  final String name;
  final String description;
  final int price;
  final bool unlocked;
  final bool canBuy;
  final Future<void> Function()? onBuy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 树预览
            Expanded(
              child: Center(
                child: ColorFiltered(
                  colorFilter: unlocked
                      ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                      : const ColorFilter.matrix([
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0,      0,      0,      1, 0,
                        ]),
                  child: AnimatedTree(
                    progress: 0.85,
                    state: unlocked ? TreeVisualState.completed : TreeVisualState.growing,
                    seed: speciesId.hashCode,
                    speciesId: speciesId,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (unlocked)
                  const Icon(Icons.check_circle, color: Colors.green, size: 18)
                else
                  const Icon(Icons.lock_outline, size: 18),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (unlocked)
              OutlinedButton(
                onPressed: null,
                child: const Text('已解锁'),
              )
            else
              FilledButton(
                onPressed: canBuy ? () => onBuy?.call() : null,
                child: Text('购买 $price'),
              ),
          ],
        ),
      ),
    );
  }
}

