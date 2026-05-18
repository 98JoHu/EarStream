// ignore_for_file: require_trailing_commas

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

import '../storage/meditation_cache.dart';
import '../../config/meditation_config.dart';

final _logger = Logger();

/// High-quality voice service with Qwen3-TTS (Alibaba DashScope).
class MeditationVoiceService {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isInitialized = false;
  bool _isSpeaking = false;
  bool _usePremiumVoice = false;
  String _speakingSpeed = 'slow'; // 'very_slow', 'slow', 'medium', 'fast'
  String _dashScopeApiKey = MeditationConfig.dashScopeApiKey;
  String _qwenVoice = 'Seren'; // Qwen3-TTS voice name; updated in initialize()

  // Map speaking speed to TTS rate values
  static const Map<String, double> _speedToRate = {
    'very_slow': 0.25,
    'slow': 0.4,
    'medium': 0.6,
    'fast': 0.8,
  };

  Future<void> initialize({
    String voiceGender = 'female',
    String speakingSpeed = 'slow',
    bool usePremiumVoice = false,
    String? elevenLabsApiKey,
    String? elevenLabsVoiceId,
  }) async {
    _speakingSpeed = speakingSpeed;
    // DashScope API key is read from .env (not per-user account)
    _dashScopeApiKey = MeditationConfig.dashScopeApiKey;
    // Map voiceGender to Qwen3-TTS voice name
    // Kai = "soothing audio spa for your ears" (male)
    // Seren = "gentle, soothing voice to help you fall asleep faster" (female)
    _qwenVoice = voiceGender == 'male' ? 'Kai' : 'Seren';
    _usePremiumVoice = usePremiumVoice || _hasValidPremiumVoiceConfig;

    _logger.i(
      'Initializing voice (speed: $_speakingSpeed, premium: $_usePremiumVoice, qwenVoice: $_qwenVoice)',
    );

    await _initializeFlutterTts();
    _isInitialized = true;

    final willUsePremium = _usePremiumVoice && _hasValidPremiumVoiceConfig;
    _logger.i(
      'Voice ready (${willUsePremium ? "using PREMIUM Qwen3-TTS" : "using FREE Flutter TTS"})',
    );
  }

  bool get _hasValidPremiumVoiceConfig =>
      _dashScopeApiKey != 'NONE' && _dashScopeApiKey.length > 10;

  Future<void> _initializeFlutterTts() async {
    try {
      await _flutterTts.setLanguage('en-US');
      final rate = _speedToRate[_speakingSpeed] ?? 0.4; // Default to 'slow'
      await _flutterTts.setSpeechRate(rate);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(0.90);
    } catch (e) {
      _logger.w('Error configuring Flutter TTS base settings: $e');
    }
    try {
      if (!kIsWeb && Platform.isIOS) {
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ],
        );
      }
    } catch (e) {
      _logger.w('iOS audio category setup failed (non-iOS?): $e');
    }
    try {
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

  /// Speak text using Qwen3-TTS (high quality) with Flutter TTS fallback.
  Future<void> speak(String text) async {
    print(
        '[EARSTREAM TTS] speak() called — initialized=$_isInitialized, speaking=$_isSpeaking, premium=$_usePremiumVoice');
    if (!_isInitialized) {
      print('[EARSTREAM TTS] Not yet initialized — calling initialize()');
      await initialize();
    }

    if (_isSpeaking) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isSpeaking) {
        print('[EARSTREAM TTS] speak() skipped — still speaking');
        return;
      }
    }

    _isSpeaking = true;
    final cleanedText = _cleanTextForTTS(text);
    final usePremiumVoiceNow = _hasValidPremiumVoiceConfig;

    try {
      if (usePremiumVoiceNow) {
        final success = await _tryQwenTts(cleanedText);
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
      print('[EARSTREAM TTS] speak() finished');
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

  Future<bool> _tryQwenTts(String text) async {
    try {
      final cachedFile =
          await MeditationCache.getCachedAudio(text, isPremiumVoice: true);
      if (cachedFile != null) {
        _logger.i('Using cached Qwen3-TTS audio (saves 1 API request)');
        await _playAudioFile(cachedFile);
        return true;
      }

      if (!_hasValidPremiumVoiceConfig) {
        _logger.i('No DashScope API key configured -> Flutter TTS fallback');
        return false;
      }

      _logger.i('Qwen3-TTS: voice=$_qwenVoice — API REQUEST');

      // Step 1: Request audio generation from DashScope
      final ttsResponse = await http
          .post(
            Uri.parse(
              // International (Singapore) region endpoint
              'https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',
            ),
            headers: {
              'Authorization': 'Bearer $_dashScopeApiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'qwen3-tts-flash', // stable alias
              'input': {
                'messages': [
                  {
                    'role': 'user',
                    'content': [
                      {'type': 'text', 'text': text}
                    ]
                  }
                ]
              },
              'parameters': {
                'voice': _qwenVoice,
                'language_type': 'English',
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (ttsResponse.statusCode != 200) {
        _logger.w(
          'Qwen3-TTS API error: ${ttsResponse.statusCode} — ${ttsResponse.body}',
        );
        return false;
      }

      final responseJson =
          jsonDecode(ttsResponse.body) as Map<String, dynamic>;
      final audioUrl =
          ((responseJson['output'] as Map<String, dynamic>?)?['audio']
                  as Map<String, dynamic>?)?['url'] as String?;

      if (audioUrl == null || audioUrl.isEmpty) {
        _logger.w(
            'Qwen3-TTS: no audio URL in response: ${ttsResponse.body}');
        return false;
      }

      // Step 2: Download the audio from the returned URL
      _logger.i('Qwen3-TTS: downloading audio...');
      final audioResponse = await http
          .get(Uri.parse(audioUrl))
          .timeout(const Duration(seconds: 30));

      if (audioResponse.statusCode != 200) {
        _logger.w(
          'Qwen3-TTS audio download failed: ${audioResponse.statusCode}',
        );
        return false;
      }

      if (audioResponse.bodyBytes.isEmpty) {
        _logger.w('Qwen3-TTS: empty audio bytes in download');
        return false;
      }

      final audioBytes = audioResponse.bodyBytes;
      final cachedAudioFile = await MeditationCache.cacheAudio(
        text,
        audioBytes,
        isPremiumVoice: true,
      );

      final playFile = cachedAudioFile ?? await _createTempFile(audioBytes);
      _logger.i('Playing Qwen3-TTS audio');
      await _playAudioFile(playFile);
      await Future.delayed(const Duration(milliseconds: 100));

      if (cachedAudioFile == null) {
        try {
          await playFile.delete();
        } catch (_) {
          // Ignore cleanup errors.
        }
      }

      _logger.i('Qwen3-TTS playback complete');
      return true;
    } catch (e) {
      _logger.w('Qwen3-TTS error: $e — Using Flutter TTS fallback');
      return false;
    }
  }

  Future<void> _playAudioFile(File file) async {
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
    await _audioPlayer.play(DeviceFileSource(file.path));
    await _audioPlayer.onPlayerComplete.first;
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
    print(
        '[EARSTREAM TTS] _speakWithFlutterTts() — text length=${text.length}');

    try {
      if (!kIsWeb && Platform.isIOS) {
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ],
        );
      }
    } catch (e) {
      _logger.w('iOS audio category setup failed: $e');
    }

    try {
      final completer = Completer<void>();

      _flutterTts.setCompletionHandler(() {
        print('[EARSTREAM TTS] ✓ CompletionHandler fired');
        if (!completer.isCompleted) completer.complete();
      });

      _flutterTts.setCancelHandler(() {
        print('[EARSTREAM TTS] ⚠ CancelHandler fired');
        if (!completer.isCompleted) completer.complete();
      });

      _flutterTts.setErrorHandler((msg) {
        print('[EARSTREAM TTS] ✗ ErrorHandler fired: $msg');
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

      print(
          '[EARSTREAM TTS] Calling flutterTts.speak() with ${cleanText.length} chars, focus=true');
      final result = await _flutterTts.speak(cleanText, focus: true);
      print(
          '[EARSTREAM TTS] flutterTts.speak() returned: $result (1=queued, 0=already speaking)');

      try {
        await completer.future.timeout(const Duration(seconds: 45));
        print('[EARSTREAM TTS] Completer resolved normally');
      } catch (e) {
        print('[EARSTREAM TTS] ⏰ Timeout after 45s — stopping TTS');
        _logger.w('TTS timed out (likely interruption): $e. Continuing...');
        await _flutterTts.stop();
      }
    } catch (e) {
      print('[EARSTREAM TTS] Exception in _speakWithFlutterTts: $e');
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
