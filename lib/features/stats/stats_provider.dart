import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/session.dart';
import '../timer/timer_provider.dart';
enum StatsPeriod { today, week, month }

/// 统计数据（用于图表 + 底部卡片）
class StatsData {
  const StatsData({
    required this.period,
    required this.buckets,
    required this.totalMinutes,
    required this.completedCount,
    required this.totalCoins,
    required this.rangeStart,
    required this.rangeEnd,
  });

  final StatsPeriod period;

  /// 柱状图数据：分钟数（长度取决于 period）
  final List<int> buckets;

  final int totalMinutes;
  final int completedCount;
  final int totalCoins;

  final DateTime rangeStart;
  final DateTime rangeEnd;
}

final statsDataProvider = FutureProvider.family<StatsData, StatsPeriod>((ref, period) async {
  // watch timerServiceProvider 使得每次专注完成后统计自动刷新
  ref.watch(timerServiceProvider);
  final repo = ref.read(sessionRepositoryProvider);

  final now = DateTime.now();

  final (start, end) = switch (period) {
    StatsPeriod.today => (_startOfDay(now), _startOfDay(now).add(const Duration(days: 1))),
    StatsPeriod.week => () {
        final start = _startOfWeek(now);
        return (start, start.add(const Duration(days: 7)));
      }(),
    StatsPeriod.month => () {
        final start = DateTime(now.year, now.month, 1);
        final nextMonth = now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1);
        return (start, nextMonth);
      }(),
  };

  final sessions = await repo.getSessionsBetween(start, end);
  final completed = sessions.where((s) => s.completed).toList(growable: false);

  final buckets = switch (period) {
    StatsPeriod.today => List<int>.filled(24, 0),
    StatsPeriod.week => List<int>.filled(7, 0),
    StatsPeriod.month => List<int>.filled(_daysInMonth(start.year, start.month), 0),
  };

  for (final s in completed) {
    final idx = _bucketIndex(period, s, start);
    if (idx == null) continue;
    if (idx < 0 || idx >= buckets.length) continue;
    buckets[idx] += s.durationMinutes;
  }

  final totalMinutes = completed.fold<int>(0, (sum, s) => sum + s.durationMinutes);
  final totalCoins = completed.fold<int>(0, (sum, s) => sum + s.coinsEarned);

  return StatsData(
    period: period,
    buckets: buckets,
    totalMinutes: totalMinutes,
    completedCount: completed.length,
    totalCoins: totalCoins,
    rangeStart: start,
    rangeEnd: end,
  );
});

int? _bucketIndex(StatsPeriod period, FocusSessionModel session, DateTime rangeStart) {
  return switch (period) {
    StatsPeriod.today => session.startTime.hour,
    StatsPeriod.week => session.startTime.difference(rangeStart).inDays,
    StatsPeriod.month => session.startTime.day - 1,
  };
}

DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

DateTime _startOfWeek(DateTime dt) {
  // 周一作为一周起点
  final dayStart = _startOfDay(dt);
  final diff = dayStart.weekday - DateTime.monday; // monday=1
  return dayStart.subtract(Duration(days: diff));
}

int _daysInMonth(int year, int month) {
  final firstDayThisMonth = DateTime(year, month, 1);
  final firstDayNextMonth = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
  return firstDayNextMonth.difference(firstDayThisMonth).inDays;
}

// ─── 应用使用统计 ──────────────────────────────────────────────────────────────

class AppUsageStat {
  const AppUsageStat({required this.appName, required this.totalSeconds});
  final String appName;
  final int totalSeconds;
}

final appUsageStatsProvider =
    FutureProvider.family<List<AppUsageStat>, StatsPeriod>((ref, period) async {
  ref.watch(timerServiceProvider);
  final repo = ref.read(appUsageRepositoryProvider);

  final now = DateTime.now();
  final (start, end) = switch (period) {
    StatsPeriod.today => (_startOfDay(now), _startOfDay(now).add(const Duration(days: 1))),
    StatsPeriod.week => () {
        final s = _startOfWeek(now);
        return (s, s.add(const Duration(days: 7)));
      }(),
    StatsPeriod.month => () {
        final s = DateTime(now.year, now.month, 1);
        final e = now.month == 12
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, now.month + 1, 1);
        return (s, e);
      }(),
  };

  final usages = await repo.getUsagesBetween(start, end);

  final map = <String, int>{};
  for (final u in usages) {
    map[u.appName] = (map[u.appName] ?? 0) + u.durationSeconds;
  }

  return map.entries
      .map((e) => AppUsageStat(appName: e.key, totalSeconds: e.value))
      .toList()
    ..sort((a, b) => b.totalSeconds.compareTo(a.totalSeconds));
});

class TagStat {
  const TagStat({required this.tagName, required this.totalMinutes});
  final String tagName; // '未分类' for null tag
  final int totalMinutes;
}

final tagStatsProvider = FutureProvider.family<List<TagStat>, StatsPeriod>((ref, period) async {
  ref.watch(timerServiceProvider);
  final repo = ref.read(sessionRepositoryProvider);

  final now = DateTime.now();
  final (start, end) = switch (period) {
    StatsPeriod.today => (_startOfDay(now), _startOfDay(now).add(const Duration(days: 1))),
    StatsPeriod.week => () {
        final s = _startOfWeek(now);
        return (s, s.add(const Duration(days: 7)));
      }(),
    StatsPeriod.month => () {
        final s = DateTime(now.year, now.month, 1);
        final e = now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1);
        return (s, e);
      }(),
  };

  final sessions = await repo.getSessionsBetween(start, end);
  final completed = sessions.where((s) => s.completed);

  final map = <String, int>{};
  for (final s in completed) {
    final key = (s.tag?.isNotEmpty == true) ? s.tag! : '未分类';
    map[key] = (map[key] ?? 0) + s.durationMinutes;
  }

  final result = map.entries
      .map((e) => TagStat(tagName: e.key, totalMinutes: e.value))
      .toList()
    ..sort((a, b) => b.totalMinutes.compareTo(a.totalMinutes));

  return result;
});
