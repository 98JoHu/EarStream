import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/log_file_manager.dart';
import '../../../widgets/sensors/sensor_page_spacing.dart';

class ApiDebugWidget extends StatefulWidget {
  const ApiDebugWidget({super.key});

  @override
  State<ApiDebugWidget> createState() => _ApiDebugWidgetState();
}

class _ApiDebugWidgetState extends State<ApiDebugWidget> {
  static const int _maxVisibleCharacters = 80000;

  final ScrollController _scrollController = ScrollController();

  LogFileManager? _logFileManager;
  Timer? _pollTimer;
  String _logContent = '';
  String _statusMessage = 'Loading logs...';
  String? _activeLogName;
  bool _shouldAutoScroll = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final manager = context.read<LogFileManager>();
    if (!identical(_logFileManager, manager)) {
      _logFileManager = manager;
      _pollTimer?.cancel();
      unawaited(_refreshLogs());
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_refreshLogs()),
      );
    }
  }

  Future<void> _refreshLogs() async {
    final manager = _logFileManager;
    if (manager == null) {
      return;
    }

    try {
      final files = await manager.logFiles;
      if (!mounted) {
        return;
      }

      if (files.isEmpty) {
        setState(() {
          _activeLogName = null;
          _logContent = '';
          _statusMessage = 'No log files available yet.';
        });
        return;
      }

      final newestFile = files.first;
      final rawContent = await newestFile.readAsString();
      if (!mounted) {
        return;
      }

      final trimmedContent = rawContent.length > _maxVisibleCharacters
          ? rawContent.substring(rawContent.length - _maxVisibleCharacters)
          : rawContent;

      final nextLogContent =
          trimmedContent.isEmpty ? '[Log file is currently empty]' : trimmedContent;

      if (_logContent == nextLogContent &&
          _activeLogName == newestFile.uri.pathSegments.last) {
        return;
      }

      setState(() {
        _activeLogName = newestFile.uri.pathSegments.last;
        _logContent = nextLogContent;
        _statusMessage = 'Auto-updating once per second.';
      });

      if (_shouldAutoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) {
            return;
          }
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Failed to load logs: $error';
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_scrollController.hasClients) {
      return false;
    }

    final remaining =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    _shouldAutoScroll = remaining < 96;
    return false;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Info'),
      ),
      body: Padding(
        padding: SensorPageSpacing.pagePaddingWithBottomInset(context),
        child: Container(
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF0A1118)
                : const Color(0xFF111A22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text(
                  _activeLogName == null
                      ? _statusMessage
                      : '$_activeLogName  |  $_statusMessage',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFA9B7C6),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0x22394A59)),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _logContent.isEmpty ? _statusMessage : _logContent,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.4,
                        color: Color(0xFFE6EDF3),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
