/// 树种数据（来自 assets/trees/trees.json）
class TreeSpecies {
  const TreeSpecies({
    required this.id,
    required this.name,
    required this.price,
    required this.unlockedByDefault,
    required this.description,
    required this.milestoneMinutes,
  });

  final String id;
  final String name;
  final int price;
  final bool unlockedByDefault;
  final String description;

  /// 正计时模式下，每隔多少分钟种一棵树
  final int milestoneMinutes;

  factory TreeSpecies.fromJson(Map<String, dynamic> json) {
    return TreeSpecies(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      price: (json['price'] as num?)?.toInt() ?? 0,
      unlockedByDefault: (json['unlocked'] as bool?) ?? false,
      description: (json['description'] as String?) ?? '',
      milestoneMinutes: (json['milestone_minutes'] as num?)?.toInt() ?? 90,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'unlocked': unlockedByDefault,
        'description': description,
        'milestone_minutes': milestoneMinutes,
      };
}
