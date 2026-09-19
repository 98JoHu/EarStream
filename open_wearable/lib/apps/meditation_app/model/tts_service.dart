import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../configs/overall_config.dart';
import 'elevenlabs_api.dart';
import 'tencent_tts_client.dart';
import 'user_account.dart';

abstract interface class TtsProvider {
  bool get isAvailable;
  Future<List<Source>> synthesize(String text);

  void dispose();
}

class TencentTtsProvider implements TtsProvider {
  final String? _secretId;
  final String? _secretKey;
  final bool _isAvailable;
  final TencentTtsRegion _region;
  final int _voiceType;
  final double _speed;
  final TencentTtsClient _client;

  TencentTtsProvider(UserAccount account, {TencentTtsClient? client})
      : _secretId = account.tencentSecretId,
        _secretKey = account.tencentSecretKey,
        _isAvailable = account.hasValidTencentKey,
        _region = account.tencentTtsRegion,
        _voiceType = account.voiceGender == Gender.male
            ? OverallMeditationConfig.tencentPremiumMaleVoiceType
            : OverallMeditationConfig.tencentPremiumFemaleVoiceType,
        _speed = _tencentSpeed(account.speakingSpeed),
        _client = client ?? TencentTtsClient();

  @override
  bool get isAvailable =>
      _isAvailable &&
      _secretId?.trim().isNotEmpty == true &&
      _secretKey?.trim().isNotEmpty == true;

  @override
  Future<List<Source>> synthesize(String text) async {
    final chunks = splitTencentTtsText(text);
    final sources = <Source>[];
    for (final chunk in chunks) {
      final bytes = await _client.synthesize(
        text: chunk,
        secretId: _secretId!,
        secretKey: _secretKey!,
        region: _region,
        voiceType: _voiceType,
        speed: _speed,
      );
      sources.add(BytesSource(bytes, mimeType: 'audio/mpeg'));
    }
    return sources;
  }

  static double _tencentSpeed(SpeakingSpeed? speed) {
    return switch (speed ?? SpeakingSpeed.slow) {
      SpeakingSpeed.verySlow =>
        OverallMeditationConfig.tencentVerySlowSpeechRate,
      SpeakingSpeed.slow => OverallMeditationConfig.tencentSlowSpeechRate,
      SpeakingSpeed.medium => OverallMeditationConfig.tencentMediumSpeechRate,
      SpeakingSpeed.fast => OverallMeditationConfig.tencentFastSpeechRate,
    };
  }

  @override
  void dispose() => _client.dispose();
}

class ElevenLabsTtsProvider implements TtsProvider {
  static const maleVoiceId = OverallMeditationConfig.elevenLabsMaleVoiceId;
  static const femaleVoiceId = OverallMeditationConfig.elevenLabsFemaleVoiceId;

  final String? _apiKey;
  final bool _isAvailable;
  final String voiceId;

  ElevenLabsTtsProvider(UserAccount account)
      : _apiKey = account.elevenLabsApiKey,
        _isAvailable = account.hasValidElevenLabsKey,
        voiceId = resolveVoiceId(account);

  static String resolveVoiceId(UserAccount account) {
    final selected = account.elevenLabsVoiceId?.trim();
    if (selected?.isNotEmpty == true) return selected!;
    return account.voiceGender == Gender.male ? maleVoiceId : femaleVoiceId;
  }

  @override
  bool get isAvailable => _isAvailable && _apiKey?.trim().isNotEmpty == true;

  @override
  Future<List<Source>> synthesize(String text) async {
    final endpoint = Uri.parse(
      '${OverallMeditationConfig.elevenLabsApiBaseUrl}'
      '/v1/text-to-speech/$voiceId',
    );
    final response = await http
        .post(
          endpoint,
          headers: {
            'xi-api-key': _apiKey!,
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
          },
          body: jsonEncode({
            'text': text,
            'model_id': OverallMeditationConfig.elevenLabsModel,
          }),
        )
        .timeout(OverallMeditationConfig.elevenLabsRequestTimeout);
    if (response.statusCode != 200) {
      throw ElevenLabsApiException.fromResponse(response);
    }
    return [BytesSource(response.bodyBytes, mimeType: 'audio/mpeg')];
  }

  @override
  void dispose() {}
}

class TtsSessionException implements Exception {
  final String providerName;
  final Object cause;

  const TtsSessionException({
    required this.providerName,
    required this.cause,
  });

  @override
  String toString() => '$providerName failed after retries: $cause';
}

/// Owns the narration route and keeps it stable for one meditation session.
class TtsService {
  final UserAccount _userAccount;
  final TtsProvider _provider;
  final FlutterTts _fallbackTts;
  final AudioPlayer _player = AudioPlayer();
  late final bool _usesDeviceFallback;
  Future<void>? _fallbackInitialization;
  int _playbackGeneration = 0;
  bool _isDisposed = false;

  TtsService({required UserAccount userAccount})
      : _userAccount = userAccount,
        _provider = switch (userAccount.ttsProvider) {
          TtsProviderOption.elevenLabs => ElevenLabsTtsProvider(userAccount),
          TtsProviderOption.tencent => TencentTtsProvider(userAccount),
        },
        _fallbackTts = FlutterTts() {
    // A cloud outage must not silently change the voice mid-meditation.
    _usesDeviceFallback = !_provider.isAvailable;
  }

  static const _femaleVoice = OverallMeditationConfig.fallbackFemaleVoice;
  static const _maleVoice = OverallMeditationConfig.fallbackMaleVoice;

  Future<void> _initializeFallbackTts(UserAccount userAccount) async {
    await _fallbackTts.awaitSpeakCompletion(true);
    await _fallbackTts.setLanguage(OverallMeditationConfig.fallbackLanguage);
    await _fallbackTts.setSpeechRate(
      userAccount.speakingSpeed?.speed ??
          OverallMeditationConfig.fallbackSpeechRate,
    );
    await _fallbackTts.setVolume(OverallMeditationConfig.fallbackVolume);

    if (userAccount.voiceGender == Gender.male) {
      await _fallbackTts.setVoice(_maleVoice);
    } else if (userAccount.voiceGender == Gender.female) {
      await _fallbackTts.setVoice(_femaleVoice);
    }
  }

  static final _premiumTtsAudioContext = AudioContext(
    android: AudioContextAndroid(
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  Future<void> speak(String text) async {
    if (_isDisposed) return;
    final playbackGeneration = ++_playbackGeneration;
    if (_usesDeviceFallback) {
      try {
        await (_fallbackInitialization ??=
            _initializeFallbackTts(_userAccount));
        if (playbackGeneration != _playbackGeneration || _isDisposed) return;
        await _fallbackTts.speak(text);
        return;
      } catch (error) {
        throw TtsSessionException(
          providerName: 'DeviceTtsProvider',
          cause: error,
        );
      }
    }

    Object? lastError;
    const retryDelays = OverallMeditationConfig.cloudTtsRetryDelays;
    for (var attempt = 0; attempt < retryDelays.length; attempt++) {
      if (playbackGeneration != _playbackGeneration || _isDisposed) return;
      final delay = retryDelays[attempt];
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (playbackGeneration != _playbackGeneration || _isDisposed) return;

      try {
        await _speakWithProvider(text, playbackGeneration);
        return;
      } catch (error) {
        lastError = error;
        debugPrint(
          'Error using ${_provider.runtimeType} '
          '(attempt ${attempt + 1}/${retryDelays.length}): $error',
        );
        await _player.stop();
      }
    }

    throw TtsSessionException(
      providerName: _provider.runtimeType.toString(),
      cause: lastError ?? StateError('Unknown voice service error'),
    );
  }

  Future<void> _speakWithProvider(
    String text,
    int playbackGeneration,
  ) async {
    final sources = await _provider.synthesize(text);
    if (sources.isEmpty) {
      throw StateError('The voice service returned no audio.');
    }
    if (playbackGeneration != _playbackGeneration || _isDisposed) return;

    await _player.setAudioContext(_premiumTtsAudioContext);
    for (final source in sources) {
      if (playbackGeneration != _playbackGeneration || _isDisposed) return;
      final playbackEnded = Future.any([
        _player.onPlayerComplete.first,
        _player.onPlayerStateChanged
            .firstWhere((state) => state == PlayerState.stopped),
      ]);
      await _player.play(source);
      await playbackEnded;
      if (playbackGeneration != _playbackGeneration || _isDisposed) return;
    }
  }

  Future<void> stop() async {
    _playbackGeneration++;
    if (_isDisposed) return;
    await _player.stop();
    if (_fallbackInitialization != null) {
      await _fallbackTts.stop();
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _playbackGeneration++;
    _provider.dispose();
    unawaited(_player.dispose().catchError(_logDisposeError));
    if (_fallbackInitialization != null) {
      unawaited(_fallbackTts.stop().catchError(_logDisposeError));
    }
  }

  static void _logDisposeError(Object error, StackTrace stackTrace) {
    debugPrint('Error disposing TTS playback: $error');
    debugPrint('$stackTrace');
  }
}
