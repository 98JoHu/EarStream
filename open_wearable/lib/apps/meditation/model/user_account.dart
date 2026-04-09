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
  String meditationStyle; // Calm, energetic, etc.
  String preferredEnvironment; // Nature, ocean, etc.
  bool usePremiumVoice; // Toggle for Google Cloud TTS ($$$)
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
    this.voiceGender = 'female', // Fixed to female only
    this.meditationStyle = 'calm and empathetic',
    this.preferredEnvironment = 'peaceful nature',
    this.usePremiumVoice = false, // Default to FREE voice
    this.stressTriggers = const [],
    this.relaxationTechniques = const ['deep breathing', 'progressive relaxation'],
    this.favoriteActivity = '',
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) : 
    createdAt = createdAt ?? DateTime.now(),
    lastUpdated = lastUpdated ?? DateTime.now();
  
  /// Get personalized stress thresholds based on demographics
  Map<String, double> getPersonalizedThresholds() {
    // Base thresholds
    double stressHrThreshold = 95.0;
    double stressHrvThreshold = 20.0;
    double relaxHrThreshold = 75.0;
    double relaxHrvThreshold = 35.0;
    
    // Adjust for age (older = generally lower HR, lower HRV)
    if (age < 25) {
      stressHrThreshold = 100.0;
      relaxHrThreshold = 70.0;
      relaxHrvThreshold = 45.0;
    } else if (age < 35) {
      stressHrThreshold = 95.0;
      relaxHrThreshold = 72.0;
      relaxHrvThreshold = 40.0;
    } else if (age < 45) {
      stressHrThreshold = 90.0;
      relaxHrThreshold = 74.0;
      relaxHrvThreshold = 35.0;
    } else if (age < 55) {
      stressHrThreshold = 85.0;
      relaxHrThreshold = 76.0;
      relaxHrvThreshold = 30.0;
    } else {
      stressHrThreshold = 80.0;
      relaxHrThreshold = 78.0;
      relaxHrvThreshold = 25.0;
    }
    
    // Adjust for gender (males typically have lower resting HR)
    if (gender == 'male') {
      stressHrThreshold -= 5.0;
      relaxHrThreshold -= 3.0;
      relaxHrvThreshold += 5.0; // Males typically have slightly higher HRV
    } else if (gender == 'female') {
      stressHrThreshold += 5.0;
      relaxHrThreshold += 3.0;
      relaxHrvThreshold -= 5.0;
    }
    
    // Adjust for fitness level
    switch (fitnessLevel) {
      case 'sedentary':
        stressHrThreshold += 10.0;
        relaxHrThreshold += 5.0;
        stressHrvThreshold -= 5.0;
        relaxHrvThreshold -= 10.0;
        break;
      case 'moderate':
        // Already at moderate baseline
        break;
      case 'active':
        stressHrThreshold -= 5.0;
        relaxHrThreshold -= 5.0;
        stressHrvThreshold += 5.0;
        relaxHrvThreshold += 10.0;
        break;
      case 'athlete':
        stressHrThreshold -= 15.0;
        relaxHrThreshold -= 10.0;
        stressHrvThreshold += 10.0;
        relaxHrvThreshold += 20.0;
        break;
    }
    
    // Use measured baseline if available
    if (restingHr != null) {
      relaxHrThreshold = restingHr!;
      stressHrThreshold = restingHr! * 1.25; // 25% above resting
    }
    
    if (baselineHrv != null) {
      relaxHrvThreshold = baselineHrv!;
      stressHrvThreshold = baselineHrv! * 0.6; // 40% below baseline indicates stress
    }
    
    return {
      'stressHrThreshold': stressHrThreshold,
      'stressHrvThreshold': stressHrvThreshold,
      'relaxHrThreshold': relaxHrThreshold,
      'relaxHrvThreshold': relaxHrvThreshold,
    };
  }
  
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
    'meditationStyle': meditationStyle,
    'preferredEnvironment': preferredEnvironment,
    'usePremiumVoice': usePremiumVoice,
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
      meditationStyle: json['meditationStyle'] ?? 'calm and empathetic',
      preferredEnvironment: json['preferredEnvironment'] ?? 'peaceful nature',
      usePremiumVoice: json['usePremiumVoice'] ?? false, // Default to FREE
      stressTriggers: List<String>.from(json['stressTriggers'] ?? []),
      relaxationTechniques: List<String>.from(json['relaxationTechniques'] ?? ['deep breathing', 'progressive relaxation']),
      favoriteActivity: json['favoriteActivity'] ?? '',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      lastUpdated: DateTime.parse(json['lastUpdated'] ?? DateTime.now().toIso8601String()),
    );
  }
  
  /// Save account to local storage
  Future<void> save() async {
    lastUpdated = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final jsonData = toJson();
    print('SAVING ACCOUNT: voiceGender=${jsonData['voiceGender']}, meditationStyle=${jsonData['meditationStyle']}');
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
- Meditation Style: $meditationStyle
- Preferred Environment: $preferredEnvironment
${favoriteActivity.isNotEmpty ? '- Favorite Activity: $favoriteActivity' : ''}
${stressTriggers.isNotEmpty ? '- Stress Triggers: ${stressTriggers.join(", ")}' : ''}
${relaxationTechniques.isNotEmpty ? '- What helps them relax: ${relaxationTechniques.join(", ")}' : ''}
${restingHr != null ? '- Resting Heart Rate: ${restingHr!.toStringAsFixed(0)} BPM' : ''}
${baselineHrv != null ? '- Baseline HRV: ${baselineHrv!.toStringAsFixed(0)} ms' : ''}''';
  }
}

