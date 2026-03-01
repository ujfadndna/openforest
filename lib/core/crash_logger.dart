import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { info, warning, error, fatal }

class CrashLogger {
  static final instance = CrashLogger._();
  CrashLogger._();

  IOSink? _sink;
  Directory? _logsDirectory;
  bool _lastSessionCrashed = false;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      final appSupportDirectory = await getApplicationSupportDirectory();
      final logsDirectory = Directory(
        '${appSupportDirectory.path}${Platform.pathSeparator}logs',
      );
      if (!await logsDirectory.exists()) {
        await logsDirectory.create(recursive: true);
      }
      _logsDirectory = logsDirectory;

      await _cleanupOldLogs(logsDirectory);
      _lastSessionCrashed = await _detectLastSessionCrash(logsDirectory);

      final logFile = File(
        '${logsDirectory.path}${Platform.pathSeparator}${_todayLogFileName()}',
      );
      _sink = logFile.openWrite(mode: FileMode.append);
      _sink?.write('=== SESSION_START ${DateTime.now().toIso8601String()} ===\n');
      if (_sink != null) {
        await _sink!.flush();
      }

      _initialized = true;
    } catch (error, stack) {
      debugPrint('[CrashLogger] init failed: $error');
      debugPrint(stack.toString());
    }
  }

  void log(String message, {LogLevel level = LogLevel.info}) {
    try {
      final line = _formatLogLine(level, message);
      debugPrint(line.trimRight());

      final sink = _sink;
      if (sink == null) return;

      sink.write(line);
      unawaited(sink.flush().catchError((_) {}));
    } catch (_) {}
  }

  void error(String message, [Object? error, StackTrace? stack]) {
    _logWithDetails(LogLevel.error, message, error, stack);
  }

  void fatal(String message, [Object? error, StackTrace? stack]) {
    _logWithDetails(LogLevel.fatal, message, error, stack);
  }

  void markSessionEnd() {
    try {
      final sink = _sink;
      if (sink == null) return;

      sink.write('=== SESSION_END ${DateTime.now().toIso8601String()} ===\n');
      unawaited(sink.flush().catchError((_) {}));
    } catch (_) {}
  }

  bool get lastSessionCrashed => _lastSessionCrashed;

  String get logDir => _logsDirectory?.path ?? '';

  void _logWithDetails(
    LogLevel level,
    String message,
    Object? error,
    StackTrace? stack,
  ) {
    try {
      final buffer = StringBuffer(_formatLogLine(level, message));
      if (error != null) {
        buffer.writeln('  Error: $error');
      }
      if (stack != null) {
        for (final line in stack.toString().split('\n')) {
          if (line.trim().isEmpty) continue;
          buffer.writeln('  $line');
        }
      }
      buffer.writeln('---');

      final payload = buffer.toString();
      debugPrint(payload.trimRight());

      final sink = _sink;
      if (sink == null) return;

      sink.write(payload);
      unawaited(sink.flush().catchError((_) {}));
    } catch (_) {}
  }

  Future<void> _cleanupOldLogs(Directory logsDirectory) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));

    try {
      await for (final entity in logsDirectory.list(followLinks: false)) {
        if (entity is! File || !_isCrashLogFile(entity.path)) continue;

        final logDate = _parseLogDate(entity.path);
        if (logDate != null) {
          if (logDate.isBefore(cutoff)) {
            await entity.delete();
          }
          continue;
        }

        final modified = await entity.lastModified();
        if (modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  Future<bool> _detectLastSessionCrash(Directory logsDirectory) async {
    try {
      final latest = await _latestLogFile(logsDirectory);
      if (latest == null) return false;

      final lines = await latest.readAsLines();
      var lastStartIndex = -1;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('=== SESSION_START ')) {
          lastStartIndex = i;
        }
      }

      if (lastStartIndex == -1) return false;

      for (var i = lastStartIndex + 1; i < lines.length; i++) {
        if (lines[i].contains('=== SESSION_END ')) {
          return false;
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<File?> _latestLogFile(Directory logsDirectory) async {
    final files = <File>[];

    try {
      await for (final entity in logsDirectory.list(followLinks: false)) {
        if (entity is File && _isCrashLogFile(entity.path)) {
          files.add(entity);
        }
      }
    } catch (_) {
      return null;
    }

    if (files.isEmpty) return null;

    files.sort((a, b) {
      final aDate = _parseLogDate(a.path);
      final bDate = _parseLogDate(b.path);

      if (aDate != null && bDate != null) {
        return bDate.compareTo(aDate);
      }
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return b.path.compareTo(a.path);
    });

    return files.first;
  }

  String _todayLogFileName() {
    final now = DateTime.now();
    return 'crash_${_pad(now.year, 4)}${_pad(now.month, 2)}${_pad(now.day, 2)}.log';
  }

  String _formatLogLine(LogLevel level, String message) {
    final now = DateTime.now();
    final time =
        '${_pad(now.hour, 2)}:${_pad(now.minute, 2)}:${_pad(now.second, 2)}.${_pad(now.millisecond, 3)}';
    return '[$time] [${level.name.toUpperCase()}] $message\n';
  }

  bool _isCrashLogFile(String path) {
    final name = _fileName(path);
    return RegExp(r'^crash_\d{8}\.log$').hasMatch(name);
  }

  DateTime? _parseLogDate(String path) {
    final name = _fileName(path);
    final match = RegExp(r'^crash_(\d{4})(\d{2})(\d{2})\.log$').firstMatch(name);
    if (match == null) return null;

    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    if (year == null || month == null || day == null) return null;

    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  String _fileName(String path) {
    final separatorIndex = path.lastIndexOf(Platform.pathSeparator);
    if (separatorIndex < 0) return path;
    return path.substring(separatorIndex + 1);
  }

  String _pad(int value, int width) => value.toString().padLeft(width, '0');
}
