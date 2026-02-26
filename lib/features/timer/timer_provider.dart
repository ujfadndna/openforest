import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import '../../core/app_monitor.dart';
import '../../core/timer_service.dart';
import '../../data/database.dart';
import '../../data/models/tag_model.dart';
import '../../data/repositories/app_usage_repository.dart';
import '../../data/repositories/coin_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/tag_repository.dart';
import '../settings/settings_screen.dart';

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

/// 当前选中的树种（商店选择，计时器使用）
final selectedSpeciesProvider = StateProvider<String>((ref) => 'oak');

/// 计时器 Service Provider（ChangeNotifier）
final timerServiceProvider = ChangeNotifierProvider<TimerService>((ref) {
  final timer = TimerService();
  final sessionRepo = ref.read(sessionRepositoryProvider);
  final appMonitor = ref.read(appMonitorProvider);

  timer.onComplete = (coinsEarned) async {
    if (timer.mode == TimerMode.pomodoro && timer.isPomodoroBreak) return;

    await appMonitor.stop();

    final start = timer.startTime ?? DateTime.now();
    final end = timer.endTime ?? DateTime.now();
    final durationMinutes = timer.targetDuration.inMinutes;

    final sessionId = await sessionRepo.addSession(
      startTime: start,
      endTime: end,
      durationMinutes: durationMinutes,
      completed: true,
      coinsEarned: 0,
      treeSpecies: timer.currentSpecies,
      tag: timer.currentTag?.name,
    );

    appMonitor.updateSessionId(sessionId);
  };

  timer.onFailed = () async {
    if (timer.mode == TimerMode.pomodoro && timer.isPomodoroBreak) return;

    await appMonitor.stop();

    final start = timer.startTime ?? DateTime.now();
    final end = timer.endTime ?? DateTime.now();
    final durationMinutes = timer.elapsed.inMinutes;

    await sessionRepo.addSession(
      startTime: start,
      endTime: end,
      durationMinutes: durationMinutes,
      completed: false,
      coinsEarned: 0,
      treeSpecies: timer.currentSpecies,
      tag: timer.currentTag?.name,
    );
  };

  timer.onMilestoneReached = () async {
    final now = DateTime.now();
    final milestoneMs = timer.milestoneMinutes * 60 * 1000;
    final start = now.subtract(Duration(milliseconds: milestoneMs));

    await sessionRepo.addSession(
      startTime: start,
      endTime: now,
      durationMinutes: timer.milestoneMinutes,
      completed: true,
      coinsEarned: 0,
      treeSpecies: timer.currentSpecies,
      tag: timer.currentTag?.name,
    );

    // 仅在设置开启时发送通知
    final settings = ref.read(settingsControllerProvider);
    if (settings.treeNotification) {
      final notification = LocalNotification(
        title: 'OpenForest',
        body: '一棵${_speciesName(timer.currentSpecies)}种下了，继续专注吧',
      );
      await notification.show();
    }
  };

  unawaited(ref.read(settingsControllerProvider.notifier).ensureLoaded());

  return timer;
});

String _speciesName(String id) => switch (id) {
  'oak' => '橡树',
  'pine' => '松树',
  'cherry' => '樱花树',
  'bamboo' => '竹子',
  'maple' => '枫树',
  _ => '树',
};
