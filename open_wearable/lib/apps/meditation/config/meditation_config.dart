import 'package:flutter_dotenv/flutter_dotenv.dart';

class MeditationConfig {
  static String _readEnv(String key) {
    try {
      return dotenv.env[key] ?? 'NONE';
    } catch (_) {
      return 'NONE';
    }
  }

  // API Configuration - loaded from .env
  static String get geminiApiKey {
    final key = _readEnv('GEMINI_API_KEY');
    // Validate that it's not a placeholder
    if (key == 'NONE' ||
        key == 'YOUR_GEMINI_API_KEY_HERE' ||
        key.contains('YOUR_') ||
        key.contains('your_')) {
      return 'NONE';
    }
    return key;
  }

  static String get elevenLabsApiKey {
    final key = _readEnv('ELEVENLABS_API_KEY') != 'NONE'
        ? _readEnv('ELEVENLABS_API_KEY')
        : _readEnv('ELEVEN_LABS_API_KEY');
    // Validate that it's not a placeholder
    if (key == 'NONE' ||
        key == 'YOUR_ELEVENLABS_API_KEY_HERE' ||
        key.contains('YOUR_') ||
        key.contains('your_')) {
      return 'NONE';
    }
    return key;
  }

  static String get elevenLabsVoiceId {
    final voiceId = _readEnv('ELEVENLABS_VOICE_ID');
    if (voiceId == 'NONE' ||
        voiceId == 'YOUR_ELEVENLABS_VOICE_ID_HERE' ||
        voiceId.contains('YOUR_') ||
        voiceId.contains('your_')) {
      // Bella (female) default voice ID
      return 'EXAVITQu4vr4xnSDxMaL';
    }
    return voiceId;
  }

  // Backward-compatible alias to avoid touching all callsites at once.
  static String get googleCloudTtsApiKey => elevenLabsApiKey;

  static String get microsoftGraphAccessToken {
    final token = _readEnv('MICROSOFT_GRAPH_ACCESS_TOKEN') != 'NONE'
        ? _readEnv('MICROSOFT_GRAPH_ACCESS_TOKEN')
        : _readEnv('MICROSOFT_OUTLOOK_ACCESS_TOKEN');
    if (token == 'NONE' ||
        token == 'YOUR_MICROSOFT_GRAPH_ACCESS_TOKEN_HERE' ||
        token.contains('YOUR_') ||
        token.contains('your_')) {
      return 'NONE';
    }
    return token;
  }

  // Debug helper to check if APIs are configured
  static bool get hasValidGeminiKey =>
      geminiApiKey != 'NONE' && geminiApiKey.startsWith('AIza');
  static bool get hasValidTtsKey =>
      elevenLabsApiKey != 'NONE' && elevenLabsApiKey.length > 20;
  static bool get hasValidMicrosoftGraphToken =>
      microsoftGraphAccessToken != 'NONE' &&
      microsoftGraphAccessToken.length > 20;

  // Meditation Settings
  static const int targetWordCount = 280;

  // Audio Settings
  static const String backgroundMusicPath =
      'meditation_sound.mp3'; // Asset path from assets/
  static const double backgroundMusicVolume =
      0.04; // Lowered for better TTS clarity
  static const double speechVolume = 1.0;
  static const double speechRate = 0.35; // Slow and calming speed
  static const double speechPitch =
      0.8; // Slightly lower pitch for soothing voice

  // Baseline Measurement
  static const int baselineDurationSeconds = 60; // 1 minute baseline

  // Stress Detection
  static const double relaxationThreshold =
      0.10; // 10% improvement to end session (OR condition)

  // Meditation Texts
  static const String stressAlertText =
      "You seem pretty stressed. Please pause your current task and take a moment for yourself.";

  static const String welcomeText =
      "Welcome to your stress-adaptive and personalized meditation. Let's begin by finding a comfortable position and focusing on your breath.";

  static const String completionText =
      "Your body has calmed down. Well done. The session is now complete.";

  // User Preferences (can be extended)
  static String meditationStyle = 'calm and empathetic';
  static String preferredEnvironment = 'nature sounds';
  static String voiceGender = 'female'; // 'male' or 'female'
  static String personalNotes = '';
}
