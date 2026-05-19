import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A single saved meditation session transcript (text only).
class SavedMeditationTranscript {
  final String id;
  final DateTime timestamp;
  final List<String> segments;

  SavedMeditationTranscript({
    required this.id,
    required this.timestamp,
    required this.segments,
  });

  String get fullText => segments.join('\n\n');

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'segments': segments,
      };

  factory SavedMeditationTranscript.fromJson(Map<String, dynamic> json) {
    return SavedMeditationTranscript(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      segments: List<String>.from(json['segments'] as List),
    );
  }
}

/// Persistent store for saved meditation transcripts.
///
/// Uses [SharedPreferences] so no extra packages are needed.
class SavedMeditationTranscripts {
  static final SavedMeditationTranscripts instance =
      SavedMeditationTranscripts._();
  SavedMeditationTranscripts._();

  static const String _storageKey = 'saved_meditation_transcripts_v1';
  static const int _maxSaved = 50;

  List<SavedMeditationTranscript> _transcripts = [];
  List<SavedMeditationTranscript> get transcripts =>
      List.unmodifiable(_transcripts);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _transcripts = list
          .map((e) =>
              SavedMeditationTranscript.fromJson(e as Map<String, dynamic>))
          .toList();
      _transcripts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (_) {
      _transcripts = [];
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_transcripts.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> addTranscript(SavedMeditationTranscript transcript) async {
    _transcripts.insert(0, transcript);
    if (_transcripts.length > _maxSaved) {
      _transcripts = _transcripts.sublist(0, _maxSaved);
    }
    await _persist();
  }

  Future<void> deleteTranscript(String id) async {
    _transcripts.removeWhere((t) => t.id == id);
    await _persist();
  }

  Future<void> clearAll() async {
    _transcripts = [];
    await _persist();
  }
}
