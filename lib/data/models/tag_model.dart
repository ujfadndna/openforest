import 'package:flutter/material.dart';

class TagModel {
  const TagModel({
    this.id,
    required this.name,
    required this.colorValue,
  });

  final int? id;
  final String name;
  final int colorValue; // Color.value (ARGB int)

  Color get color => Color(colorValue);

  TagModel copyWith({int? id, String? name, int? colorValue}) {
    return TagModel(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
    );
  }
}
