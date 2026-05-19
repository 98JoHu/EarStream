import 'meditation_config.dart';

enum MeditationRuntimeValueSource {
  inApp,
  envFallback,
  missing,
}

class MeditationRuntimeValue {
  final String? value;
  final MeditationRuntimeValueSource source;

  const MeditationRuntimeValue({
    required this.value,
    required this.source,
  });

  bool get hasValue => value != null;

  String get sourceLabel {
    switch (source) {
      case MeditationRuntimeValueSource.inApp:
        return 'In-app';
      case MeditationRuntimeValueSource.envFallback:
        return '.env fallback';
      case MeditationRuntimeValueSource.missing:
        return 'Missing';
    }
  }
}

class MeditationRuntimeConfig {
  static MeditationRuntimeValue elevenLabsApiKey({String? localValue}) {
    return _resolve(
      localValue: localValue,
      envValue: MeditationConfig.elevenLabsApiKey,
      sanitizer: sanitizeLongSecret,
    );
  }

  static MeditationRuntimeValue microsoftGraphAccessToken({String? localValue}) {
    return _resolve(
      localValue: localValue,
      envValue: MeditationConfig.microsoftGraphAccessToken,
      sanitizer: sanitizeLongSecret,
    );
  }

  static MeditationRuntimeValue dashScopeApiKey({String? localValue}) {
    return _resolve(
      localValue: localValue,
      envValue: MeditationConfig.dashScopeApiKey,
      sanitizer: sanitizeLongSecret,
    );
  }

  static MeditationRuntimeValue dashScopeApiKeyCn({String? localValue}) {
    return _resolve(
      localValue: localValue,
      envValue: MeditationConfig.dashScopeApiKeyCn,
      sanitizer: sanitizeLongSecret,
    );
  }

  /// Resolves the active TTS provider. In-app value takes precedence over .env.
  static String resolveTtsProvider({String? localValue}) {
    if (localValue == 'dashscope' || localValue == 'elevenlabs') {
      return localValue!;
    }
    return MeditationConfig.ttsProvider;
  }

  static String resolveElevenLabsVoiceId({String? localValue}) {
    return sanitizeElevenLabsVoiceId(localValue) ??
        MeditationConfig.elevenLabsVoiceId;
  }

  static String? sanitizeLongSecret(String? value) {
    final secret = value?.trim() ?? '';
    if (secret.length > 20) {
      return secret;
    }
    return null;
  }

  static String? sanitizeElevenLabsVoiceId(String? value) {
    final voiceId = value?.trim() ?? '';
    if (voiceId.isEmpty ||
        voiceId == 'NONE' ||
        voiceId == 'YOUR_ELEVENLABS_VOICE_ID_HERE' ||
        voiceId.contains('YOUR_') ||
        voiceId.contains('your_')) {
      return null;
    }
    return voiceId;
  }

  static MeditationRuntimeValue _resolve({
    required String? localValue,
    required String envValue,
    required String? Function(String? value) sanitizer,
  }) {
    final inAppValue = sanitizer(localValue);
    if (inAppValue != null) {
      return MeditationRuntimeValue(
        value: inAppValue,
        source: MeditationRuntimeValueSource.inApp,
      );
    }

    final fallbackValue = sanitizer(envValue);
    if (fallbackValue != null) {
      return MeditationRuntimeValue(
        value: fallbackValue,
        source: MeditationRuntimeValueSource.envFallback,
      );
    }

    return const MeditationRuntimeValue(
      value: null,
      source: MeditationRuntimeValueSource.missing,
    );
  }
}
