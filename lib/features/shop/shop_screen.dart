import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../timer/timer_provider.dart';
import '../timer/tree_painter.dart';
import 'shop_provider.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treesAsync = ref.watch(treeSpeciesListProvider);
    final selectedId = ref.watch(selectedSpeciesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('树种', style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(
          child: treesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载树种失败：$e')),
            data: (trees) {
              if (trees.isEmpty) return const Center(child: Text('暂无树种数据'));
              return Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.9,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: trees.length,
                  itemBuilder: (context, index) {
                    final t = trees[index];
                    return _TreeCard(
                      speciesId: t.id,
                      name: t.name,
                      description: t.description,
                      milestoneMinutes: t.milestoneMinutes,
                      selected: t.id == selectedId,
                      onTap: () {
                      ref.read(selectedSpeciesProvider.notifier).state = t.id;
                      SharedPreferences.getInstance().then(
                        (p) => p.setString('last_species', t.id),
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

class _TreeCard extends StatefulWidget {
  const _TreeCard({
    required this.speciesId,
    required this.name,
    required this.description,
    required this.milestoneMinutes,
    required this.selected,
    required this.onTap,
  });

  final String speciesId;
  final String name;
  final String description;
  final int milestoneMinutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TreeCard> createState() => _TreeCardState();
}

class _TreeCardState extends State<_TreeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.selected
                  ? colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
            color: widget.selected
                ? colorScheme.primaryContainer.withOpacity(0.3)
                : _hovered
                    ? colorScheme.surfaceContainerHigh
                    : colorScheme.surfaceContainer,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Center(
                        child: AnimatedTree(
                          progress: 0.85,
                          state: TreeVisualState.completed,
                          seed: widget.speciesId.hashCode,
                          speciesId: widget.speciesId,
                        ),
                      ),
                      if (widget.selected)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Icon(
                            Icons.check_circle,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: widget.selected ? colorScheme.primary : null,
                      ),
                ),
                // hover 时展开介绍和里程碑
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 150),
                  crossFadeState: _hovered
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(height: 4),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.timer_outlined,
                                size: 12,
                                color: colorScheme.outline),
                            const SizedBox(width: 4),
                            Text(
                              '里程碑：${widget.milestoneMinutes} 分钟',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colorScheme.outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
