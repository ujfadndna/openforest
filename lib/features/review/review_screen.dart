import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/review_repository.dart';
import 'review_provider.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  void _refreshList() {
    ref.read(reviewRefreshSignal.notifier).state++;
  }

  Future<void> _addItem() async {
    final result = await _showItemDialog();
    if (result == null) return;
    await ref.read(reviewRepositoryProvider).addItem(
          result.title,
          result.intervalDays,
        );
    _refreshList();
  }

  Future<void> _editItem(ReviewItem item) async {
    final result = await _showItemDialog(editing: item);
    if (result == null || item.id == null) return;
    await ref.read(reviewRepositoryProvider).updateItem(
          item.id!,
          title: result.title,
          intervalDays: result.intervalDays,
        );
    _refreshList();
  }

  Future<void> _markReviewed(ReviewItem item) async {
    if (item.id == null) return;
    await ref.read(reviewRepositoryProvider).markReviewed(item.id!);
    _refreshList();
  }

  Future<void> _archiveItem(ReviewItem item) async {
    if (item.id == null) return;
    await ref.read(reviewRepositoryProvider).archiveItem(item.id!);
    _refreshList();
  }

  Future<void> _deleteItem(ReviewItem item) async {
    if (item.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除回顾计划'),
          content: Text('确定删除“${item.title}”吗？此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await ref.read(reviewRepositoryProvider).deleteItem(item.id!);
    _refreshList();
  }

  Future<void> _showItemMenu(
    BuildContext itemContext,
    ReviewItem item, {
    Offset? position,
  }) async {
    final overlay =
        Overlay.of(itemContext).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final box = itemContext.findRenderObject() as RenderBox?;
    final anchor = position ??
        (box == null
            ? Offset(overlay.size.width / 2, overlay.size.height / 2)
            : box.localToGlobal(box.size.center(Offset.zero)));

    final action = await showMenu<_ReviewMenuAction>(
      context: itemContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(anchor, anchor),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: _ReviewMenuAction.edit,
          child: Text('编辑'),
        ),
        PopupMenuItem(
          value: _ReviewMenuAction.archive,
          child: Text('归档'),
        ),
        PopupMenuItem(
          value: _ReviewMenuAction.delete,
          child: Text('删除'),
        ),
      ],
    );

    if (action == null) return;
    switch (action) {
      case _ReviewMenuAction.edit:
        await _editItem(item);
        break;
      case _ReviewMenuAction.archive:
        await _archiveItem(item);
        break;
      case _ReviewMenuAction.delete:
        await _deleteItem(item);
        break;
    }
  }

  Future<_ReviewFormResult?> _showItemDialog({ReviewItem? editing}) async {
    final titleController = TextEditingController(text: editing?.title ?? '');
    final intervalController = TextEditingController(
      text: '${editing?.intervalDays ?? 15}',
    );
    String? errorText;

    final result = await showDialog<_ReviewFormResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(editing == null ? '添加回顾计划' : '编辑回顾计划'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: '章节名'),
                      onChanged: (_) => setDialogState(() => errorText = null),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '回顾间隔（天）'),
                      onChanged: (_) => setDialogState(() => errorText = null),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    final intervalDays =
                        int.tryParse(intervalController.text.trim());
                    if (title.isEmpty) {
                      setDialogState(() => errorText = '章节名不能为空');
                      return;
                    }
                    if (intervalDays == null || intervalDays <= 0) {
                      setDialogState(() => errorText = '请输入大于 0 的天数');
                      return;
                    }
                    Navigator.of(context).pop(
                      _ReviewFormResult(
                        title: title,
                        intervalDays: intervalDays,
                      ),
                    );
                  },
                  child: Text(editing == null ? '添加' : '保存'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    intervalController.dispose();
    return result;
  }

  _ReviewStatus _buildStatus(ReviewItem item, ColorScheme colorScheme) {
    const reviewedColor = Color(0xFF2E7D32);
    if (item.daysSinceLastReview == 0 && !item.isDue) {
      return const _ReviewStatus(
        text: '已完成本轮',
        textColor: reviewedColor,
        indicatorColor: reviewedColor,
      );
    }
    if (item.isDue) {
      return _ReviewStatus(
        text: '已到期',
        textColor: colorScheme.error,
        indicatorColor: colorScheme.error,
      );
    }
    if (item.daysUntilDue == 0) {
      return _ReviewStatus(
        text: '今日到期',
        textColor: colorScheme.error,
        indicatorColor: colorScheme.error,
      );
    }
    return _ReviewStatus(
      text: '${item.daysUntilDue} 天后到期',
      textColor: colorScheme.outline,
      indicatorColor: colorScheme.outline,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeItems = ref.watch(activeReviewItemsProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('回顾计划', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: activeItems.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('加载失败：$error')),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(
                    child: Text('暂无回顾计划，点击右上角添加'),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final status = _buildStatus(
                      item,
                      Theme.of(context).colorScheme,
                    );
                    return Builder(
                      builder: (itemContext) {
                        return GestureDetector(
                          onSecondaryTapDown: (details) {
                            _showItemMenu(
                              itemContext,
                              item,
                              position: details.globalPosition,
                            );
                          },
                          child: Card(
                            child: ListTile(
                              isThreeLine: true,
                              onLongPress: () {
                                final box = itemContext.findRenderObject()
                                    as RenderBox?;
                                final position = box?.localToGlobal(
                                  Offset(box.size.width - 16, 28),
                                );
                                _showItemMenu(
                                  itemContext,
                                  item,
                                  position: position,
                                );
                              },
                              leading: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: status.indicatorColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              title: Text(item.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('每 ${item.intervalDays} 天'),
                                  Text(
                                    status.text,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: status.textColor),
                                  ),
                                ],
                              ),
                              trailing: TextButton(
                                onPressed: () => _markReviewed(item),
                                child: const Text('完成回顾'),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewFormResult {
  const _ReviewFormResult({
    required this.title,
    required this.intervalDays,
  });

  final String title;
  final int intervalDays;
}

class _ReviewStatus {
  const _ReviewStatus({
    required this.text,
    required this.textColor,
    required this.indicatorColor,
  });

  final String text;
  final Color textColor;
  final Color indicatorColor;
}

enum _ReviewMenuAction {
  edit,
  archive,
  delete,
}
