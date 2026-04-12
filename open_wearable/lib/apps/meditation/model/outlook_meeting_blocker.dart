import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import 'meditation_config.dart';

final _logger = Logger();

class OutlookMeetingStatus {
  final bool isInMeeting;
  final String? subject;
  final DateTime? endsAt;

  const OutlookMeetingStatus({
    required this.isInMeeting,
    this.subject,
    this.endsAt,
  });
}

/// Checks Microsoft Outlook calendar events through Microsoft Graph and
/// suppresses meditation prompts while a meeting is in progress.
class OutlookMeetingBlocker {
  OutlookMeetingBlocker({
    http.Client? client,
    String? accessToken,
    this.pollInterval = const Duration(minutes: 2),
  })  : _client = client ?? http.Client(),
        _accessToken = accessToken;

  final http.Client _client;
  final Duration pollInterval;
  final String? _accessToken;

  Timer? _pollTimer;
  OutlookMeetingStatus _status = const OutlookMeetingStatus(isInMeeting: false);
  DateTime? _lastRefreshAt;

  bool get hasValidConfiguration => _effectiveAccessToken != 'NONE';
  bool get isInMeeting => _status.isInMeeting;
  OutlookMeetingStatus get status => _status;
  DateTime? get lastRefreshAt => _lastRefreshAt;

  String get _effectiveAccessToken {
    final token = _sanitizeAccessToken(_accessToken);
    return token ?? MeditationConfig.microsoftGraphAccessToken;
  }

  String? _sanitizeAccessToken(String? token) {
    final value = token?.trim();
    if (value == null || value.isEmpty) return null;
    if (value == 'NONE' ||
        value == 'YOUR_MICROSOFT_GRAPH_ACCESS_TOKEN_HERE' ||
        value.contains('YOUR_') ||
        value.contains('your_')) {
      return null;
    }
    return value;
  }

  void startMonitoring() {
    if (!hasValidConfiguration) {
      _logger.i(
          'Outlook meeting suppression disabled - no Graph token configured');
      return;
    }

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) {
      unawaited(refreshNow());
    });
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<OutlookMeetingStatus> refreshNow() async {
    _lastRefreshAt = DateTime.now();

    if (!hasValidConfiguration) {
      _status = const OutlookMeetingStatus(isInMeeting: false);
      return _status;
    }

    try {
      final now = DateTime.now();
      final windowStart = now.subtract(const Duration(minutes: 5));
      final windowEnd = now.add(const Duration(hours: 8));

      final response = await _client.get(
        Uri.https('graph.microsoft.com', '/v1.0/me/calendarView', {
          'startDateTime': windowStart.toUtc().toIso8601String(),
          'endDateTime': windowEnd.toUtc().toIso8601String(),
          r'$select': 'subject,start,end,showAs,isOnlineMeeting,location',
          r'$orderby': 'start/dateTime',
          r'$top': '25',
        }),
        headers: {
          'Authorization': 'Bearer $_effectiveAccessToken',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _logger.w(
            'Outlook meeting check failed: ${response.statusCode} ${response.body}');
        _status = const OutlookMeetingStatus(isInMeeting: false);
        return _status;
      }

      final decoded = jsonDecode(response.body);
      final items = (decoded['value'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>();

      final currentMeeting = _findCurrentMeeting(items, now);
      _status =
          currentMeeting ?? const OutlookMeetingStatus(isInMeeting: false);
      return _status;
    } catch (e) {
      _logger.w('Outlook meeting check error: $e');
      _status = const OutlookMeetingStatus(isInMeeting: false);
      return _status;
    }
  }

  OutlookMeetingStatus? _findCurrentMeeting(
      List<Map<String, dynamic>> events, DateTime now) {
    for (final event in events) {
      final start = _parseGraphDateTime(event['start']);
      final end = _parseGraphDateTime(event['end']);
      if (start == null || end == null) {
        continue;
      }

      final overlapsNow = start.isBefore(now) && end.isAfter(now);
      if (!overlapsNow) {
        continue;
      }

      if (!_shouldSuppressEvent(event)) {
        continue;
      }

      return OutlookMeetingStatus(
        isInMeeting: true,
        subject: event['subject']?.toString(),
        endsAt: end,
      );
    }

    return null;
  }

  bool _shouldSuppressEvent(Map<String, dynamic> event) {
    final subject = event['subject']?.toString().toLowerCase() ?? '';
    final location = _extractLocation(event).toLowerCase();
    final showAs = event['showAs']?.toString().toLowerCase() ?? '';
    final isOnlineMeeting = event['isOnlineMeeting'] == true;

    const meetingKeywords = [
      'meeting',
      'call',
      'standup',
      'sync',
      'review',
      '1:1',
      'one on one',
      'check-in',
      'check in',
      'briefing',
      'interview',
      'demo',
      'planning',
      'teams',
      'zoom',
      'webex',
      'webinar',
    ];

    final hasMeetingKeyword = meetingKeywords.any(
      (keyword) => subject.contains(keyword) || location.contains(keyword),
    );

    final isBusyState = const {
      'busy',
      'oof',
      'workingelsewhere',
      'tentative',
    }.contains(showAs);

    return isOnlineMeeting || hasMeetingKeyword || isBusyState;
  }

  String _extractLocation(Map<String, dynamic> event) {
    final location = event['location'];
    if (location is Map<String, dynamic>) {
      return location['displayName']?.toString() ?? '';
    }
    return location?.toString() ?? '';
  }

  DateTime? _parseGraphDateTime(dynamic field) {
    if (field is Map<String, dynamic>) {
      final value = field['dateTime']?.toString();
      if (value == null || value.isEmpty) {
        return null;
      }
      return DateTime.tryParse(value);
    }
    return null;
  }

  void dispose() {
    stopMonitoring();
    _client.close();
  }
}
