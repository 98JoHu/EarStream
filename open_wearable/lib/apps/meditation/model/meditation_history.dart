import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Individual meditation session record
class MeditationSession {
  final String sessionId;
  final String userId;
  final DateTime timestamp;
  final double startHr;
  final double startHrv;
  final double endHr;
  final double endHrv;
  final int durationSeconds;
  final int iterationCount;
  final double peakStressLevel;
  
  MeditationSession({
    required this.sessionId,
    required this.userId,
    required this.timestamp,
    required this.startHr,
    required this.startHrv,
    required this.endHr,
    required this.endHrv,
    required this.durationSeconds,
    required this.iterationCount,
    required this.peakStressLevel,
  });
  
  double get hrImprovement => startHr > 0 ? ((startHr - endHr) / startHr * 100) : 0;
  double get hrvImprovement => startHrv > 0 ? ((endHrv - startHrv) / startHrv * 100) : 0;
  bool get wasSuccessful => hrImprovement > 5 || hrvImprovement > 5;
  
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'userId': userId,
    'timestamp': timestamp.toIso8601String(),
    'startHr': startHr,
    'startHrv': startHrv,
    'endHr': endHr,
    'endHrv': endHrv,
    'durationSeconds': durationSeconds,
    'iterationCount': iterationCount,
    'peakStressLevel': peakStressLevel,
  };
  
  factory MeditationSession.fromJson(Map<String, dynamic> json) {
    return MeditationSession(
      sessionId: json['sessionId'],
      userId: json['userId'],
      timestamp: DateTime.parse(json['timestamp']),
      startHr: json['startHr'],
      startHrv: json['startHrv'],
      endHr: json['endHr'],
      endHrv: json['endHrv'],
      durationSeconds: json['durationSeconds'],
      iterationCount: json['iterationCount'],
      peakStressLevel: json['peakStressLevel'],
    );
  }
}

/// Meditation history manager
class MeditationHistory {
  static final MeditationHistory instance = MeditationHistory._();
  MeditationHistory._();
  
  static const String _storageKey = 'meditation_history_v2';
  static const int _maxSessions = 100;
  
  List<MeditationSession> _sessions = [];
  List<MeditationSession> get sessions => List.unmodifiable(_sessions);
  
  /// Load history
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    
    if (jsonString != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _sessions = jsonList.map((json) => MeditationSession.fromJson(json)).toList();
        _sessions.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Newest first
      } catch (e) {
        print('Error loading history: $e');
        _sessions = [];
      }
    }
  }
  
  /// Save history
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_sessions.map((s) => s.toJson()).toList());
    await prefs.setString(_storageKey, jsonString);
  }
  
  /// Add new session
  Future<void> addSession({
    required String userId,
    required double startHr,
    required double startHrv,
    required double endHr,
    required double endHrv,
    required int durationSeconds,
    required int iterationCount,
    required double peakStressLevel,
  }) async {
    final session = MeditationSession(
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: userId,
      timestamp: DateTime.now(),
      startHr: startHr,
      startHrv: startHrv,
      endHr: endHr,
      endHrv: endHrv,
      durationSeconds: durationSeconds,
      iterationCount: iterationCount,
      peakStressLevel: peakStressLevel,
    );
    
    _sessions.insert(0, session);
    
    if (_sessions.length > _maxSessions) {
      _sessions = _sessions.sublist(0, _maxSessions);
    }
    
    await save();
  }
  
  /// Get sessions for specific user
  List<MeditationSession> getSessionsForUser(String userId) {
    return _sessions.where((s) => s.userId == userId).toList();
  }
  
  /// Get recent sessions (last N days)
  List<MeditationSession> getRecentSessions(String userId, int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return _sessions
        .where((s) => s.userId == userId && s.timestamp.isAfter(cutoff))
        .toList();
  }
  
  /// Get statistics for user
  Map<String, dynamic> getStatistics(String userId) {
    final userSessions = getSessionsForUser(userId);
    
    if (userSessions.isEmpty) {
      return {
        'totalSessions': 0,
        'totalMinutes': 0,
        'averageHrImprovement': 0.0,
        'averageHrvImprovement': 0.0,
        'successRate': 0.0,
        'averageDuration': 0,
        'averageIterations': 0.0,
      };
    }
    
    final totalMinutes = userSessions.fold(0, (sum, s) => sum + s.durationSeconds) ~/ 60;
    final avgHrImprovement = userSessions.fold(0.0, (sum, s) => sum + s.hrImprovement) / userSessions.length;
    final avgHrvImprovement = userSessions.fold(0.0, (sum, s) => sum + s.hrvImprovement) / userSessions.length;
    final successCount = userSessions.where((s) => s.wasSuccessful).length;
    final avgDuration = userSessions.fold(0, (sum, s) => sum + s.durationSeconds) / userSessions.length;
    final avgIterations = userSessions.fold(0.0, (sum, s) => sum + s.iterationCount) / userSessions.length;
    
    return {
      'totalSessions': userSessions.length,
      'totalMinutes': totalMinutes,
      'averageHrImprovement': avgHrImprovement,
      'averageHrvImprovement': avgHrvImprovement,
      'successRate': (successCount / userSessions.length * 100),
      'averageDuration': avgDuration.round(),
      'averageIterations': avgIterations,
    };
  }
  
  /// Clear history for user
  Future<void> clearHistory(String userId) async {
    _sessions.removeWhere((s) => s.userId == userId);
    await save();
  }
}


