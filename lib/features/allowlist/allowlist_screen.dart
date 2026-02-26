import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_monitor.dart';
import '../settings/settings_screen.dart';

class AllowlistScreen extends ConsumerStatefulWidget {
  const AllowlistScreen({super.key});

  @override
  ConsumerState<AllowlistScreen> createState() => _AllowlistScreenState();
}

class _AllowlistScreenState extends ConsumerState<AllowlistScreen> {
  List<String> _processes = [];
  bool _loadingProcesses = false;

  Future<void> _loadProcesses() async {
    setState(() => _loadingProcesses = true);
    final list = await Future.microtask(getRunningProcesses);
    if (mounted) setState(() { _processes = list; _loadingProcesses = false; });
  }

  void _showProcessPicker(BuildContext context, SettingsController controller) {
    final existing = ref.read(settingsControllerProvider).focusBlacklist;
    showDialog<void>(
      context: context,
      builder: (ctx) => _ProcessPickerDialog(
        processes: _processes,
        existing: existing,
        onAdd: (name) => unawaited(controller.addToBlacklist(name)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final list = settings.focusBlacklist;
    final color = Theme.of(context).colorScheme.errorContainer;
    final onColor = Theme.of(context).colorScheme.onErrorContainer;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('黑名单', style: Theme.of(context).textTheme.titleLarge),
          ),
          Text(
            '专注期间切换到黑名单应用，树会枯萎。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: _loadingProcesses
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add, size: 18),
            label: const Text('从运行中的进程添加'),
            onPressed: _loadingProcesses
                ? null
                : () async {
                    await _loadProcesses();
                    if (mounted) _showProcessPicker(context, controller);
                  },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      '黑名单为空。\n添加后，专注期间切换到这些应用树会枯萎。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final app = list[i];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: color,
                          child: Text(
                            app.isNotEmpty ? app[0].toUpperCase() : '?',
                            style: TextStyle(fontSize: 12, color: onColor),
                          ),
                        ),
                        title: Text(app),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => unawaited(controller.removeFromBlacklist(app)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProcessPickerDialog extends StatefulWidget {
  const _ProcessPickerDialog({
    required this.processes,
    required this.existing,
    required this.onAdd,
  });

  final List<String> processes;
  final List<String> existing;
  final void Function(String) onAdd;

  @override
  State<_ProcessPickerDialog> createState() => _ProcessPickerDialogState();
}

class _ProcessPickerDialogState extends State<_ProcessPickerDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.processes
        .where((p) => _filter.isEmpty || p.contains(_filter.toLowerCase()))
        .toList();

    return AlertDialog(
      title: const Text('添加到黑名单'),
      content: SizedBox(
        width: 320,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: '搜索进程名…',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('没有匹配的进程'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final name = filtered[i];
                        final already = widget.existing.contains(name);
                        return ListTile(
                          dense: true,
                          title: Text(name),
                          trailing: already ? const Icon(Icons.check, size: 16) : null,
                          enabled: !already,
                          onTap: already
                              ? null
                              : () {
                                  widget.onAdd(name);
                                  Navigator.of(context).pop();
                                },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
