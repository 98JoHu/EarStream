// ignore_for_file: require_trailing_commas

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

import 'meditation_cache.dart';
import 'meditation_config.dart';
import 'meditation_runtime_config.dart';

final _logger = Logger();

/// High-quality voice service with ElevenLabs TTS.
class MeditationVoiceService {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isInitialized = false;
  bool _isSpeaking = false;
  bool _usePremiumVoice = false;
  String _meditationStyle = 'calm and empathetic';
  String _elevenLabsApiKey = MeditationConfig.elevenLabsApiKey;
  String _elevenLabsVoiceId = MeditationConfig.elevenLabsVoiceId;

  static const Map<String, Map<String, double>> _styleSettings = {
    'calm and empathetic': {'stability': 0.62, 'similarityBoost': 0.82},
    'gentle and soothing': {'stability': 0.70, 'similarityBoost': 0.78},
    'warm and compassionate': {'stability': 0.58, 'similarityBoost': 0.86},
    'peaceful and mindful': {'stability': 0.68, 'similarityBoost': 0.80},
  };

  Future<void> initialize({
    String voiceGender = 'female',
    String? meditationStyle,
    bool usePremiumVoice = false,
    String? elevenLabsApiKey,
    String? elevenLabsVoiceId,
  }) async {
    _meditationStyle = meditationStyle ?? 'calm and empathetic';
    _usePremiumVoice = usePremiumVoice;
    _elevenLabsApiKey = MeditationRuntimeConfig.elevenLabsApiKey(
          localValue: elevenLabsApiKey,
        ).value ??
        MeditationConfig.elevenLabsApiKey;
    _elevenLabsVoiceId = MeditationRuntimeConfig.resolveElevenLabsVoiceId(
      localValue: elevenLabsVoiceId,
    );

    _logger.i(
      'Initializing voice (style: $_meditationStyle, premium: $_usePremiumVoice)',
    );

    await _initializeFlutterTts();
    _isInitialized = true;

    final willUsePremium = _usePremiumVoice && _hasValidPremiumVoiceConfig;
    _logger.i(
      'Voice ready (${willUsePremium ? "using PREMIUM ElevenLabs TTS (\$\$\$)" : "using FREE Flutter TTS"})',
    );
  }

  bool get _hasValidPremiumVoiceConfig =>
      _elevenLabsApiKey != 'NONE' && _elevenLabsApiKey.length > 20;

  Future<void> _initializeFlutterTts() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.42);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(0.90);

      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
      );

      final voices = await _flutterTts.getVoices;
      if (voices != null && voices.isNotEmpty) {
        final enVoices = voices
            .where(
                (voice) => voice['locale']?.toString().contains('en') ?? false)
            .toList();

        _logger.i('Available TTS voices: ${enVoices.length}');

        String? selectedVoice;
        for (final voice in enVoices) {
          final name = voice['name']?.toString().toLowerCase() ?? '';
          if (name.contains('female') &&
              (name.contains('enhanced') ||
                  name.contains('premium') ||
                  name.contains('neural'))) {
            selectedVoice = voice['name'].toString();
            await _flutterTts.setVoice({
              'name': voice['name'].toString(),
              'locale': voice['locale'].toString(),
            });
            _logger.i('Using enhanced voice: ${voice['name']}');
            break;
          }
        }

        if (selectedVoice == null) {
          for (final voice in enVoices) {
            final name = voice['name']?.toString().toLowerCase() ?? '';
            if (name.contains('female') || name.contains('woman')) {
              selectedVoice = voice['name'].toString();
              await _flutterTts.setVoice({
                'name': voice['name'].toString(),
                'locale': voice['locale'].toString(),
              });
              _logger.i('Using female voice: ${voice['name']}');
              break;
            }
          }
        }

        if (selectedVoice == null && enVoices.isNotEmpty) {
          final voice = enVoices.first;
          await _flutterTts.setVoice({
            'name': voice['name'].toString(),
            'locale': voice['locale'].toString(),
          });
          _logger.i('Using default voice: ${voice['name']}');
        }
      }
    } catch (e) {
      _logger.w('Error configuring Flutter TTS fallback: $e');
    }
  }

  /// Speak text with ElevenLabs TTS (high quality).
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isSpeaking) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isSpeaking) return;
    }

    _isSpeaking = true;
    final cleanedText = _cleanTextForTTS(text);

    try {
      if (_usePremiumVoice) {
        final success = await _tryElevenLabsTts(cleanedText);
        if (!success) {
          _logger.w('Premium voice failed, falling back to free voice');
          await _speakWithFlutterTts(cleanedText);
        }
      } else {
        await _speakWithFlutterTts(cleanedText);
      }
    } catch (e) {
      _logger.e('Error during speech: $e');
      await _speakWithFlutterTts(cleanedText);
    } finally {
      _isSpeaking = false;
    }
  }

  String _cleanTextForTTS(String text) {
    _logger.i(
      'Cleaning text: "${text.substring(0, text.length > 100 ? 100 : text.length)}..."',
    );

    final cleaned = text
        .replaceAllMapped(RegExp(r'(\d+)\s*BPM', caseSensitive: false),
            (match) {
          return '${match.group(1)} beats per minute';
        })
        .replaceAll(
            RegExp(r'\bBPM\b', caseSensitive: false), 'beats per minute')
        .replaceAll(RegExp(r'\bHR\b'), 'heart rate')
        .replaceAll(RegExp(r'\bHRV\b'), 'heart rate variability')
        .replaceAllMapped(RegExp(r'(\d+)\s*ms\b', caseSensitive: false),
            (match) {
          return '${match.group(1)} milliseconds';
        })
        .replaceAll(RegExp(r'\bms\b'), 'milliseconds')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned != text) {
      _logger.i(
        '✨ Cleaned text: "${cleaned.substring(0, cleaned.length > 100 ? 100 : cleaned.length)}..."',
      );
    }

    return cleaned;
  }

  Future<bool> _tryElevenLabsTts(String text) async {
    try {
      final cachedFile =
          await MeditationCache.getCachedAudio(text, isPremiumVoice: true);
      if (cachedFile != null) {
        _logger.i('Using cached premium TTS audio (saves 1 API request)');
        await _audioPlayer.setAudioContext(
          AudioContext(
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: {
                AVAudioSessionOptions.mixWithOthers,
                AVAudioSessionOptions.duckOthers,
              },
            ),
            android: AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: false,
              contentType: AndroidContentType.speech,
              usageType: AndroidUsageType.media,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
          ),
        );

        await _audioPlayer.play(DeviceFileSource(cachedFile.path));
        await _audioPlayer.onPlayerComplete.first;
        return true;
      }

      final styleSettings = _styleSettings[_meditationStyle] ??
          _styleSettings['calm and empathetic']!;
      final voiceId = _elevenLabsVoiceId;

      _logger.i('ElevenLabs TTS: $voiceId - API REQUEST');

      if (!_hasValidPremiumVoiceConfig) {
        _logger.i('No API key configured -> Using Flutter TTS fallback');
        return false;
      }

      final response = await http
          .post(
            Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$voiceId'),
            headers: {
              'xi-api-key': _elevenLabsApiKey,
              'Content-Type': 'application/json',
              'Accept': 'audio/mpeg',
            },
            body: jsonEncode({
              'text': text,
              'model_id': 'eleven_turbo_v2',
              'voice_settings': {
                'stability': styleSettings['stability']!,
                'similarity_boost': styleSettings['similarityBoost']!,
                'style': 0.35,
                'use_speaker_boost': true,
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _logger.w(
          'ElevenLabs TTS API error: ${response.statusCode} - ${response.body}',
        );
        return false;
      }

      if (response.bodyBytes.isEmpty) {
        _logger.w('No audio bytes in ElevenLabs response');
        return false;
      }

      final audioBytes = response.bodyBytes;
      final cachedAudioFile = await MeditationCache.cacheAudio(
        text,
        audioBytes,
        isPremiumVoice: true,
      );

      final playFile = cachedAudioFile ?? await _createTempFile(audioBytes);

      _logger.i('Playing high-quality ElevenLabs TTS audio');

      await _audioPlayer.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.duckOthers,
            },
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );

      await _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(DeviceFileSource(playFile.path));
      await _audioPlayer.onPlayerComplete.first;

      await Future.delayed(const Duration(milliseconds: 100));

      if (cachedAudioFile == null) {
        try {
          await playFile.delete();
        } catch (_) {
          // Ignore cleanup errors.
        }
      }

      _logger.i('ElevenLabs TTS playback complete');
      return true;
    } catch (e) {
      _logger.w('ElevenLabs TTS error: $e - Using fallback');
      return false;
    }
  }

  Future<File> _createTempFile(List<int> audioBytes) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/meditation_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await tempFile.writeAsBytes(audioBytes);
    return tempFile;
  }

  Future<void> _speakWithFlutterTts(String text) async {
    _logger.i('Using Flutter TTS fallback');

    try {
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
      );

      final completer = Completer<void>();

      _flutterTts.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
      });

      _flutterTts.setCancelHandler(() {
        if (!completer.isCompleted) completer.complete();
      });

      _flutterTts.setErrorHandler((msg) {
        _logger.e('Flutter TTS error: $msg');
        if (!completer.isCompleted) completer.complete();
      });

      final cleanText = text
          .replaceAll('...', ', ')
          .replaceAll('..', ', ')
          .replaceAll('*', '')
          .replaceAll('#', '')
          .replaceAll('"', '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      await _flutterTts.speak(cleanText);

      try {
        await completer.future.timeout(const Duration(seconds: 45));
      } catch (e) {
        _logger.w('TTS timed out (likely interruption): $e. Continuing...');
        await _flutterTts.stop();
      }
    } catch (e) {
      _logger.e('Flutter TTS error: $e');
    }
  }

  Future<void> stop() async {
    _isSpeaking = false;
    await _flutterTts.stop();
    try {
      await _audioPlayer.release();
    } catch (_) {
      await _audioPlayer.stop();
    }
  }

  Future<void> pause() async {
    await _flutterTts.pause();
    await _audioPlayer.pause();
  }

  Future<void> resume() async {
    await _audioPlayer.resume();
  }

  void setVoiceGender(String gender) {
    _isInitialized = false;
  }

  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
  }

  bool get isSpeaking => _isSpeaking;

  Future<void> testVoice() async {
    await speak(
      'Welcome to your meditation session. I am here to guide you towards a state of calm and relaxation.',
    );
  }
}
