import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/tree_species.dart';

/// 读取 assets/trees/trees.json，返回所有树种
final treeSpeciesListProvider = FutureProvider<List<TreeSpecies>>((ref) async {
  final jsonStr = await rootBundle.loadString('assets/trees/trees.json');
  final raw = json.decode(jsonStr);
  if (raw is! List) return const <TreeSpecies>[];

  return raw
      .whereType<Map<String, dynamic>>()
      .map(TreeSpecies.fromJson)
      .toList(growable: false);
});
