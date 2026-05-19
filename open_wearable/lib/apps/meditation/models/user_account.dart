// ignore_for_file: require_trailing_commas

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// User account with demographic information for personalized stress detection
class UserAccount {
  String userId; // Unique identifier
  String name;
  int age;
  String gender; // 'male', 'female', 'other'
  String fitnessLevel; // 'sedentary', 'moderate', 'active', 'athlete'
  double? restingHr; // Measured resting heart rate
  double? baselineHrv; // Measured baseline HRV

  // Meditation preferences
  String voiceGender; // 'male' or 'female'
  String meditationType; // 'visualization_journey', 'mindfulness', 'body_scan', 'breathing'
  String meditationEnvironment; // Nature, ocean, mountain, etc.
  String speakingSpeed; // 'very_slow', 'slow', 'medium', 'fast'
  String additionalPreferences; // Free-form user preferences
  double stressThreshold; // Threshold for stress detection (default 0.10 = 10%)
  bool usePremiumVoice; // Toggle for ElevenLabs TTS ($$$)
  String ttsProvider; // 'elevenlabs' (default, global) or 'dashscope' (China)
  String geminiApiKey;
  String elevenLabsApiKey;
  String elevenLabsVoiceId;
  String dashScopeApiKey; // In-app DashScope International key override
  String dashScopeApiKeyCn; // In-app DashScope Chinese Mainland key override
  String microsoftGraphAccessToken;
  List<String> stressTriggers;
  List<String> relaxationTechniques;
  String favoriteActivity;

  // Account metadata
  DateTime createdAt;
  DateTime lastUpdated;

  UserAccount({
    required this.userId,
    this.name = '',
    this.age = 30,
    this.gender = 'other',
    this.fitnessLevel = 'moderate',
    this.restingHr,
    this.baselineHrv,
    this.voiceGender = 'female',
    this.meditationType = 'mindfulness',
    this.meditationEnvironment = 'peaceful nature',
    this.speakingSpeed = 'slow',
    this.additionalPreferences = '',
    this.stressThreshold = 0.10, // 10% threshold by default
    this.usePremiumVoice = false, // Default to FREE voice
    this.ttsProvider = 'elevenlabs',
    this.geminiApiKey = '',
    this.elevenLabsApiKey = '',
    this.elevenLabsVoiceId = '',
    this.dashScopeApiKey = '',
    this.dashScopeApiKeyCn = '',
    this.microsoftGraphAccessToken = '',
    this.stressTriggers = const [],
    this.relaxationTechniques = const [
      'deep breathing',
      'progressive relaxation'
    ],
    this.favoriteActivity = '',
    DateTime? createdAt,
    DateTime? lastUpdated,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastUpdated = lastUpdated ?? DateTime.now();

  /// Get expected max heart rate for age
  double get maxHeartRate => 220 - age.toDouble();

  /// Get target heart rate zone for exercise (60-80% of max)
  Map<String, double> get targetHeartRateZone => {
        'lower': maxHeartRate * 0.6,
        'upper': maxHeartRate * 0.8,
      };

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'age': age,
        'gender': gender,
        'fitnessLevel': fitnessLevel,
        'restingHr': restingHr,
        'baselineHrv': baselineHrv,
        'voiceGender': voiceGender,
        'meditationType': meditationType,
        'meditationEnvironment': meditationEnvironment,
        'speakingSpeed': speakingSpeed,
        'additionalPreferences': additionalPreferences,
        'stressThreshold': stressThreshold,
        'usePremiumVoice': usePremiumVoice,
        'ttsProvider': ttsProvider,
        'geminiApiKey': geminiApiKey,
        'elevenLabsApiKey': elevenLabsApiKey,
        'elevenLabsVoiceId': elevenLabsVoiceId,
        'dashScopeApiKey': dashScopeApiKey,
        'dashScopeApiKeyCn': dashScopeApiKeyCn,
        'microsoftGraphAccessToken': microsoftGraphAccessToken,
        'stressTriggers': stressTriggers,
        'relaxationTechniques': relaxationTechniques,
        'favoriteActivity': favoriteActivity,
        'createdAt': createdAt.toIso8601String(),
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  /// Create from JSON
  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      userId: json['userId'] ?? '',
      name: json['name'] ?? '',
      age: json['age'] ?? 30,
      gender: json['gender'] ?? 'other',
      fitnessLevel: json['fitnessLevel'] ?? 'moderate',
      restingHr: json['restingHr']?.toDouble(),
      baselineHrv: json['baselineHrv']?.toDouble(),
      voiceGender: json['voiceGender'] ?? 'female',
      meditationType: json['meditationType'] ?? 'mindfulness',
      meditationEnvironment: json['meditationEnvironment'] ?? 'peaceful nature',
      speakingSpeed: json['speakingSpeed'] ?? 'slow',
      additionalPreferences: json['additionalPreferences'] ?? '',
      stressThreshold: (json['stressThreshold'] ?? 0.10).toDouble(),
      usePremiumVoice: json['usePremiumVoice'] ?? false, // Default to FREE
      ttsProvider: json['ttsProvider'] ?? 'elevenlabs',
      geminiApiKey: json['geminiApiKey'] ?? '',
      elevenLabsApiKey: json['elevenLabsApiKey'] ?? '',
      elevenLabsVoiceId: json['elevenLabsVoiceId'] ?? '',
      dashScopeApiKey: json['dashScopeApiKey'] ?? '',
      dashScopeApiKeyCn: json['dashScopeApiKeyCn'] ?? '',
      microsoftGraphAccessToken: json['microsoftGraphAccessToken'] ?? '',
      stressTriggers: List<String>.from(json['stressTriggers'] ?? []),
      relaxationTechniques: List<String>.from(json['relaxationTechniques'] ??
          ['deep breathing', 'progressive relaxation']),
      favoriteActivity: json['favoriteActivity'] ?? '',
      createdAt:
          DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      lastUpdated: DateTime.parse(
          json['lastUpdated'] ?? DateTime.now().toIso8601String()),
    );
  }

  /// Save account to local storage
  Future<void> save() async {
    lastUpdated = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final jsonData = toJson();
    print(
        'SAVING ACCOUNT: voiceGender=${jsonData['voiceGender']}, meditationType=${jsonData['meditationType']}');
    await prefs.setString('user_account', jsonEncode(jsonData));
    print('Account saved successfully');
  }

  /// Load account from local storage
  static Future<UserAccount> load() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString('user_account');

    if (jsonString != null) {
      try {
        return UserAccount.fromJson(jsonDecode(jsonString));
      } catch (e) {
        print('Error loading user account: $e');
      }
    }

    // Return default account
    return UserAccount(
      userId: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// Check if account is set up (has basic info)
  bool get isSetup => name.isNotEmpty && age > 0;

  /// Get greeting text
  String get greeting => name.isNotEmpty ? 'Hello $name' : 'Hello';

  /// Get description for LLM context
  String getLLMContext() {
    return '''User Profile:
- Name: ${name.isNotEmpty ? name : "the person you are guiding"}
- Age: $age years old
- Gender: $gender
- Fitness Level: $fitnessLevel
- Meditation Type: $meditationType
- Meditation Environment: $meditationEnvironment
${additionalPreferences.isNotEmpty ? '- Additional Preferences: $additionalPreferences' : ''}
${favoriteActivity.isNotEmpty ? '- Favorite Activity: $favoriteActivity' : ''}
${stressTriggers.isNotEmpty ? '- Stress Triggers: ${stressTriggers.join(", ")}' : ''}
${relaxationTechniques.isNotEmpty ? '- What helps them relax: ${relaxationTechniques.join(", ")}' : ''}
${restingHr != null ? '- Resting Heart Rate: ${restingHr!.toStringAsFixed(0)} BPM' : ''}
${baselineHrv != null ? '- Baseline HRV: ${baselineHrv!.toStringAsFixed(0)} ms' : ''}''';
  }
}
