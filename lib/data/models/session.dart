/// 专注记录 Model（UI/统计层使用）
class FocusSessionModel {
  const FocusSessionModel({
    this.id,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.completed,
    required this.coinsEarned,
    required this.treeSpecies,
    this.tag,
  });

  final int? id;
  final DateTime startTime;
  final DateTime endTime;

  /// 专注时长（分钟）
  final int durationMinutes;

  final bool completed;
  final int coinsEarned;

  /// 树种 id（例如 oak/pine）
  final String treeSpecies;

  final String? tag;
}

