import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../timer/timer_provider.dart';
import 'stats_provider.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text(
                  '统计',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const TabBar(
            tabs: [
              Tab(text: '今日'),
              Tab(text: '本周'),
              Tab(text: '本月'),
              Tab(text: '标签'),
              Tab(text: '应用'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _StatsTab(period: StatsPeriod.today),
                _StatsTab(period: StatsPeriod.week),
                _StatsTab(period: StatsPeriod.month),
                const _TagStatsTab(),
                const _AppUsageTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsTab extends ConsumerWidget {
  const _StatsTab({required this.period});

  final StatsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(statsDataProvider(period));

    return dataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (data) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;

              final chart = Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _BarChart(period: period, buckets: data.buckets),
                ),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isWide)
                    SizedBox(height: 360, child: chart)
                  else
                    Expanded(child: chart),
                  const SizedBox(height: 12),
                  _SummaryCards(
                    totalMinutes: data.totalMinutes,
                    completedCount: data.completedCount,
                    totalCoins: data.totalCoins,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.period,
    required this.buckets,
  });

  final StatsPeriod period;
  final List<int> buckets;

  @override
  Widget build(BuildContext context) {
    final maxY = (buckets.isEmpty ? 0 : buckets.reduce((a, b) => a > b ? a : b)).toDouble();
    final safeMaxY = (maxY <= 0) ? 60.0 : (maxY * 1.2).clamp(10.0, 24 * 60.0);

    final groups = <BarChartGroupData>[
      for (var i = 0; i < buckets.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: buckets[i].toDouble(),
              width: period == StatsPeriod.today ? 6 : 10,
              borderRadius: BorderRadius.circular(4),
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
    ];

    return BarChart(
      BarChartData(
        maxY: safeMaxY,
        minY: 0,
        barGroups: groups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: safeMaxY / 4,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Theme.of(context).dividerColor.withOpacity(0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: safeMaxY / 4,
              getTitlesWidget: (value, meta) {
                // 显示分钟数
                return Text(
                  value.toInt().toString(),
                  style: Theme.of(context).textTheme.labelSmall,
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: period == StatsPeriod.today ? 6 : 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                final label = _bottomLabel(period, i, buckets.length);
                if (label == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final x = group.x;
              final minutes = rod.toY.toInt();
              final title = switch (period) {
                StatsPeriod.today => '$x 点',
                StatsPeriod.week => _weekLabel(x) ?? '',
                StatsPeriod.month => '${x + 1} 日',
              };
              return BarTooltipItem(
                '$title\n$minutes 分钟',
                Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
              );
            },
          ),
        ),
      ),
    );
  }

  String? _bottomLabel(StatsPeriod period, int index, int length) {
    return switch (period) {
      StatsPeriod.today => (index % 6 == 0) ? index.toString() : null,
      StatsPeriod.week => _weekLabel(index),
      StatsPeriod.month => () {
          // 月视图标签太密，隔 5 天显示一次
          final day = index + 1;
          if (day == 1 || day == length || day % 5 == 0) return day.toString();
          return null;
        }(),
    };
  }

  String? _weekLabel(int index) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    if (index < 0 || index >= labels.length) return null;
    return labels[index];
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.totalMinutes,
    required this.completedCount,
    required this.totalCoins,
  });

  final int totalMinutes;
  final int completedCount;
  final int totalCoins;

  @override
  Widget build(BuildContext context) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    final timeText = hours > 0 ? '$hours 小时 $minutes 分钟' : '$minutes 分钟';

    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Icon(Icons.schedule),
                  const SizedBox(height: 6),
                  Text('总专注时长', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text(timeText, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_outline),
                  const SizedBox(height: 6),
                  Text('完成次数', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text('$completedCount 次', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Icon(Icons.monetization_on_outlined),
                  const SizedBox(height: 6),
                  Text('获得金币', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text('$totalCoins', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── 应用使用统计 Tab ──────────────────────────────────────────────────────────

class _AppUsageTab extends ConsumerStatefulWidget {
  const _AppUsageTab();

  @override
  ConsumerState<_AppUsageTab> createState() => _AppUsageTabState();
}

class _AppUsageTabState extends ConsumerState<_AppUsageTab> {
  StatsPeriod _period = StatsPeriod.today;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(appUsageStatsProvider(_period));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<StatsPeriod>(
            segments: const [
              ButtonSegment(value: StatsPeriod.today, label: Text('今日')),
              ButtonSegment(value: StatsPeriod.week, label: Text('本周')),
              ButtonSegment(value: StatsPeriod.month, label: Text('本月')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: statsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (stats) {
                if (stats.isEmpty) {
                  return const Center(child: Text('暂无数据\n专注期间切换应用后会记录在这里'));
                }
                final totalSeconds = stats.fold<int>(0, (s, e) => s + e.totalSeconds);
                return ListView.separated(
                  itemCount: stats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = stats[i];
                    final ratio = totalSeconds > 0 ? s.totalSeconds / totalSeconds : 0.0;
                    final mins = s.totalSeconds ~/ 60;
                    final secs = s.totalSeconds % 60;
                    final timeText = mins > 0 ? '$mins 分 $secs 秒' : '$secs 秒';
                    final initial = s.appName.isNotEmpty
                        ? s.appName[0].toUpperCase()
                        : '?';

                    return Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            initial,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          child: Text(
                            s.appName,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 10,
                              backgroundColor:
                                  Theme.of(context).colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 72,
                          child: Text(
                            timeText,
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${(ratio * 100).round()}%',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
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


class _TagStatsTab extends ConsumerWidget {
  const _TagStatsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 使用本月范围作为标签统计的默认范围，同时提供 period 切换
    return _TagStatsPeriodView();
  }
}

class _TagStatsPeriodView extends ConsumerStatefulWidget {
  @override
  ConsumerState<_TagStatsPeriodView> createState() => _TagStatsPeriodViewState();
}

class _TagStatsPeriodViewState extends ConsumerState<_TagStatsPeriodView> {
  StatsPeriod _period = StatsPeriod.month;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(tagStatsProvider(_period));
    final tagsAsync = ref.watch(tagsStreamProvider);
    final tagColorMap = {
      for (final t in (tagsAsync.valueOrNull ?? [])) t.name: t.colorValue,
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<StatsPeriod>(
            segments: const [
              ButtonSegment(value: StatsPeriod.today, label: Text('今日')),
              ButtonSegment(value: StatsPeriod.week, label: Text('本周')),
              ButtonSegment(value: StatsPeriod.month, label: Text('本月')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: statsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (stats) {
                if (stats.isEmpty) {
                  return const Center(child: Text('暂无数据'));
                }
                final total = stats.fold<int>(0, (s, e) => s + e.totalMinutes);
                return ListView.separated(
                  itemCount: stats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = stats[i];
                    final ratio = total > 0 ? s.totalMinutes / total : 0.0;
                    final colorValue = tagColorMap[s.tagName];
                    final color = colorValue != null ? Color(colorValue) : Colors.grey;
                    final hours = s.totalMinutes ~/ 60;
                    final mins = s.totalMinutes % 60;
                    final timeText = hours > 0 ? '$hours 小时 $mins 分钟' : '$mins 分钟';

                    return Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(width: 72, child: Text(s.tagName, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 10,
                              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: Text(
                            timeText,
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${(ratio * 100).round()}%',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
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
