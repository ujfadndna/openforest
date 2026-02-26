import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import '../../core/app_monitor.dart';
import '../../core/timer_service.dart';
import '../../data/database.dart';
import '../../data/models/tag_model.dart';
import '../../data/models/tree_species.dart';
import '../../data/repositories/accumulated_progress_repository.dart';
import '../../data/repositories/app_usage_repository.dart';
import '../../data/repositories/coin_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/tag_repository.dart';
import '../settings/settings_screen.dart';
import '../shop/shop_provider.dart';

/// 数据库单例 Provider
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.instance;
  ref.onDispose(() => unawaited(db.close()));
  return db;
});

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SessionRepository(db);
});

final tagRepositoryProvider = Provider<TagRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final repo = TagRepository(db);
  ref.onDispose(repo.dispose);
  return repo;
});

final appUsageRepositoryProvider = Provider<AppUsageRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AppUsageRepository(db);
});

final appMonitorProvider = Provider<AppMonitor>((ref) {
  final repo = ref.watch(appUsageRepositoryProvider);
  return AppMonitor(repo);
});

final tagsStreamProvider = StreamProvider<List<TagModel>>((ref) async* {
  final repo = ref.watch(tagRepositoryProvider);
  yield await repo.getTags();
  yield* repo.watchTags();
});

final coinRepositoryProvider = Provider<CoinRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final repo = CoinRepository(db);
  ref.onDispose(repo.dispose);
  return repo;
});

final accumulatedProgressProvider = Provider<AccumulatedProgressRepository>((ref) {
  return AccumulatedProgressRepository();
});

/// 累计进度状态（秒数），用于进度条显示
final accumulatedSecondsProvider = StateProvider<int>((ref) => 0);

/// 当前选中的树种（商店选择，计时器使用）
final selectedSpeciesProvider = StateProvider<String>((ref) => 'oak');

/// 计时器 Service Provider（ChangeNotifier）
final timerServiceProvider = ChangeNotifierProvider<TimerService>((ref) {
  final timer = TimerService();
  final sessionRepo = ref.read(sessionRepositoryProvider);
  final appMonitor = ref.read(appMonitorProvider);
  final accRepo = ref.read(accumulatedProgressProvider);

  // 启动时从持久化恢复累计秒数
  unawaited(() async {
    final saved = await accRepo.getSeconds();
    ref.read(accumulatedSecondsProvider.notifier).state = saved;
  }());

  // 完成一段专注（非休息）→ 累加秒数，够了就种树
  timer.onComplete = (coinsEarned) async {
    if (timer.mode == TimerMode.pomodoro && timer.isPomodoroBreak) return;

    await appMonitor.stop();

    final addedSeconds = timer.targetDuration.inSeconds;
    final species = timer.currentSpecies;

    // 取树种要求时长
    final trees = ref.read(treeSpeciesListProvider).asData?.value ?? [];
    final treeData = trees.firstWhere(
      (t) => t.id == species,
      orElse: () => trees.isNotEmpty
          ? trees.first
          : const TreeSpecies(id: 'oak', name: '橡树', price: 0, unlockedByDefault: true, description: '', milestoneMinutes: 45),
    );
    final requiredSeconds = treeData.milestoneMinutes * 60;

    var accumulated = ref.read(accumulatedSecondsProvider) + addedSeconds;

    // 可能一次完成多棵（时长很长时）
    while (requiredSeconds > 0 && accumulated >= requiredSeconds) {
      accumulated -= requiredSeconds;

      final end = timer.endTime ?? DateTime.now();
      final start = end.subtract(Duration(seconds: treeData.milestoneMinutes * 60));

      final sessionId = await sessionRepo.addSession(
        startTime: start,
        endTime: end,
        durationMinutes: treeData.milestoneMinutes,
        completed: true,
        coinsEarned: 0,
        treeSpecies: species,
        tag: timer.currentTag?.name,
      );
      appMonitor.updateSessionId(sessionId);

      final settings = ref.read(settingsControllerProvider);
      if (settings.treeNotification) {
        final notification = LocalNotification(
          title: 'OpenForest',
          body: '一棵${treeData.name}种下了，继续专注吧',
        );
        await notification.show();
      }
    }

    ref.read(accumulatedSecondsProvider.notifier).state = accumulated;
    await accRepo.save(accumulated, species);
  };

  // 中止 → 清零累计
  timer.onFailed = () async {
    if (timer.mode == TimerMode.pomodoro && timer.isPomodoroBreak) return;

    await appMonitor.stop();

    ref.read(accumulatedSecondsProvider.notifier).state = 0;
    await accRepo.clear();
  };

  // 正计时里程碑回调不再使用（统一由 onComplete 处理）
  timer.onMilestoneReached = null;

  unawaited(ref.read(settingsControllerProvider.notifier).ensureLoaded());

  return timer;
});
