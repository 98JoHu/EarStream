import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Mood rating after meditation
enum MoodRating {
  veryRelaxed, // 😌
  relaxed,     // 😊
  neutral,     // 😐
  stressed,    // 😟
}

/// Individual mood entry
class MoodEntry {
  final DateTime timestamp;
  final MoodRating mood;
  final double stressReduction; // Percentage
  final Duration sessionDuration;
  
  MoodEntry({
    required this.timestamp,
    required this.mood,
    required this.stressReduction,
    required this.sessionDuration,
  });
  
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'mood': mood.index,
    'stressReduction': stressReduction,
    'sessionDuration': sessionDuration.inSeconds,
  };
  
  factory MoodEntry.fromJson(Map<String, dynamic> json) => MoodEntry(
    timestamp: DateTime.parse(json['timestamp']),
    mood: MoodRating.values[json['mood']],
    stressReduction: json['stressReduction'],
    sessionDuration: Duration(seconds: json['sessionDuration']),
  );
  
  String get moodEmoji {
    switch (mood) {
      case MoodRating.veryRelaxed:
        return '😌';
      case MoodRating.relaxed:
        return '😊';
      case MoodRating.neutral:
        return '😐';
      case MoodRating.stressed:
        return '😟';
    }
  }
  
  String get moodText {
    switch (mood) {
      case MoodRating.veryRelaxed:
        return 'Very Relaxed';
      case MoodRating.relaxed:
        return 'Relaxed';
      case MoodRating.neutral:
        return 'Neutral';
      case MoodRating.stressed:
        return 'Still Stressed';
    }
  }
}

/// Manages mood history
class MoodHistory {
  static const String _storageKey = 'meditation_mood_history';
  static const int _maxEntries = 100;
  
  /// Save mood entry
  static Future<void> saveMood(MoodEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getAll();
    existing.add(entry);
    
    // Keep only last 100 entries
    if (existing.length > _maxEntries) {
      existing.removeRange(0, existing.length - _maxEntries);
    }
    
    final jsonList = existing.map((e) => e.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }
  
  /// Get all mood entries
  static Future<List<MoodEntry>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    
    if (jsonString == null) return [];
    
    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => MoodEntry.fromJson(json)).toList();
  }
  
  /// Get entries from last N days
  static Future<List<MoodEntry>> getLastDays(int days) async {
    final all = await getAll();
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return all.where((e) => e.timestamp.isAfter(cutoff)).toList();
  }
  
  /// Get weekly summary
  static Future<Map<String, dynamic>> getWeeklySummary() async {
    final entries = await getLastDays(7);
    
    if (entries.isEmpty) {
      return {
        'totalSessions': 0,
        'averageStressReduction': 0.0,
        'mostCommonMood': null,
        'averageDuration': Duration.zero,
      };
    }
    
    final avgReduction = entries.map((e) => e.stressReduction).reduce((a, b) => a + b) / entries.length;
    final avgDuration = Duration(
      seconds: entries.map((e) => e.sessionDuration.inSeconds).reduce((a, b) => a + b) ~/ entries.length
    );
    
    // Count mood occurrences
    final moodCounts = <MoodRating, int>{};
    for (var entry in entries) {
      moodCounts[entry.mood] = (moodCounts[entry.mood] ?? 0) + 1;
    }
    
    final mostCommon = moodCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    
    return {
      'totalSessions': entries.length,
      'averageStressReduction': avgReduction,
      'mostCommonMood': mostCommon,
      'averageDuration': avgDuration,
      'entries': entries,
    };
  }
  
  /// Clear all mood history (for testing)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}


