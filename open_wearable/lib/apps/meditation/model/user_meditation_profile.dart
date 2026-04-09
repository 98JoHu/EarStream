import 'package:shared_preferences/shared_preferences.dart';

/// User meditation profile with personalization preferences
class UserMeditationProfile {
  String userName;
  String voiceGender; // 'male' or 'female'
  String meditationStyle; // 'calm', 'energetic', 'mindful', etc.
  String preferredEnvironment; // 'nature', 'ocean', 'mountain', 'forest'
  String favoriteActivity; // For personalized imagery
  List<String> stressTriggers; // What causes stress for this user
  List<String> relaxationTechniques; // Preferred techniques
  
  UserMeditationProfile({
    this.userName = '',
    this.voiceGender = 'female',
    this.meditationStyle = 'calm and empathetic',
    this.preferredEnvironment = 'peaceful nature',
    this.favoriteActivity = '',
    this.stressTriggers = const [],
    this.relaxationTechniques = const ['deep breathing', 'progressive relaxation'],
  });
  
  /// Save profile to local storage
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('meditation_userName', userName);
    await prefs.setString('meditation_voiceGender', voiceGender);
    await prefs.setString('meditation_style', meditationStyle);
    await prefs.setString('meditation_environment', preferredEnvironment);
    await prefs.setString('meditation_favoriteActivity', favoriteActivity);
    await prefs.setStringList('meditation_stressTriggers', stressTriggers);
    await prefs.setStringList('meditation_relaxationTechniques', relaxationTechniques);
  }
  
  /// Load profile from local storage
  static Future<UserMeditationProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    return UserMeditationProfile(
      userName: prefs.getString('meditation_userName') ?? '',
      voiceGender: prefs.getString('meditation_voiceGender') ?? 'female',
      meditationStyle: prefs.getString('meditation_style') ?? 'calm and empathetic',
      preferredEnvironment: prefs.getString('meditation_environment') ?? 'peaceful nature',
      favoriteActivity: prefs.getString('meditation_favoriteActivity') ?? '',
      stressTriggers: prefs.getStringList('meditation_stressTriggers') ?? [],
      relaxationTechniques: prefs.getStringList('meditation_relaxationTechniques') ?? ['deep breathing', 'progressive relaxation'],
    );
  }
  
  /// Get personalized greeting
  String getGreeting() {
    if (userName.isNotEmpty) {
      return 'Hello $userName';
    }
    return 'Hello';
  }
  
  /// Convert to map for LLM context
  Map<String, dynamic> toPromptContext() {
    return {
      'name': userName.isNotEmpty ? userName : 'friend',
      'style': meditationStyle,
      'environment': preferredEnvironment,
      'favoriteActivity': favoriteActivity,
      'stressTriggers': stressTriggers.join(', '),
      'relaxationTechniques': relaxationTechniques.join(', '),
    };
  }
}
