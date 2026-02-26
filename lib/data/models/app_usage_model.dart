class AppUsageModel {
  const AppUsageModel({
    this.id,
    this.sessionId,
    required this.appName,
    this.windowTitle,
    required this.durationSeconds,
    required this.recordedAt,
  });

  final int? id;
  final int? sessionId;
  final String appName;
  final String? windowTitle;
  final int durationSeconds;
  final DateTime recordedAt;
}
