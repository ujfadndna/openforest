import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/coin_service.dart';
import '../../core/timer_service.dart';
import '../../data/database.dart';
import '../../data/models/tag_model.dart';
import '../../data/repositories/coin_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/tag_repository.dart';
import '../settings/settings_screen.dart';

/// 数据库单例 Provider
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.instance;
  // App 生命周期结束时关闭数据库（忽略 Future）
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

final tagsStreamProvider = StreamProvider<List<TagModel>>((ref) async* {
  final repo = ref.watch(tagRepositoryProvider);
  // 先推送一次当前值
  yield await repo.getTags();
  yield* repo.watchTags();
});

final coinRepositoryProvider = Provider<CoinRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final repo = CoinRepository(db);
  ref.onDispose(repo.dispose);
  return repo;
});

final coinServiceProvider = Provider<CoinService>((ref) {
  final repo = ref.watch(coinRepositoryProvider);
  return CoinService(repo);
});

/// 监听总金币（用于 UI 顶部展示）
final totalCoinsProvider = StreamProvider<int>((ref) {
  return ref.watch(coinServiceProvider).watchTotalCoins();
});

/// 监听总专注分钟（设置/统计可用）
final totalFocusMinutesProvider = StreamProvider<int>((ref) {
  return ref.watch(coinServiceProvider).watchTotalFocusMinutes();
});

/// 解锁树集合（商店 UI 使用）
final unlockedTreeIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(coinRepositoryProvider).watchUnlockedTreeIds();
});

/// 计时器 Service Provider（ChangeNotifier）
final timerServiceProvider = ChangeNotifierProvider<TimerService>((ref) {
  final timer = TimerService();

  final coinService = ref.read(coinServiceProvider);
  final sessionRepo = ref.read(sessionRepositoryProvider);

  timer.onComplete = (coinsEarned) async {
    // 番茄钟休息阶段不计入专注记录
    if (timer.mode == TimerMode.pomodoro && timer.isPomodoroBreak) return;

    final start = timer.startTime ?? DateTime.now();
    final end = timer.endTime ?? DateTime.now();
    final durationMinutes = timer.targetDuration.inMinutes;

    await sessionRepo.addSession(
      startTime: start,
      endTime: end,
      durationMinutes: durationMinutes,
      completed: true,
      coinsEarned: coinsEarned,
      treeSpecies: 'oak',
      tag: timer.currentTag?.name,
    );

    // 只有完成才累加专注分钟与金币
    await coinService.addFocusReward(
      coinsEarned: coinsEarned,
      focusMinutes: durationMinutes,
    );

    // 主动刷新，确保 Stream 立即推送最新金币
    await ref.read(coinRepositoryProvider).refreshAll();
  };

  timer.onFailed = () async {
    // 番茄钟休息阶段失败不记入专注记录
    if (timer.mode == TimerMode.pomodoro && timer.isPomodoroBreak) return;

    final start = timer.startTime ?? DateTime.now();
    final end = timer.endTime ?? DateTime.now();
    final durationMinutes = timer.elapsed.inMinutes;

    await sessionRepo.addSession(
      startTime: start,
      endTime: end,
      durationMinutes: durationMinutes,
      completed: false,
      coinsEarned: 0,
      treeSpecies: 'oak',
      tag: timer.currentTag?.name,
    );
  };

  // 提前触发一次 refresh（确保 StreamProvider 初始有值）
  unawaited(ref.read(coinRepositoryProvider).refreshAll());

  // 读取设置，确保 SharedPreferences 初始化（懒加载）
  unawaited(ref.read(settingsControllerProvider.notifier).ensureLoaded());

  return timer;
});
