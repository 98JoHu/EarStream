import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'meditation_config.dart';
import 'meditation_cache.dart';

final _logger = Logger();

/// High-quality voice service with Google Cloud TTS
class MeditationVoiceService {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isInitialized = false;
  bool _isSpeaking = false;
  bool _usePremiumVoice = false; // User preference for premium voice
  
  // Google Cloud TTS - high quality female voice
  static const Map<String, String> _femaleVoice = {
    'name': 'en-US-Standard-C',
    'description': 'Warm, empathetic female voice'
  };
  
  // Style affects pitch and speaking rate
  static const Map<String, Map<String, double>> _styleSettings = {
    'calm and empathetic': {
      'pitch': -2.0,
      'speakingRate': 1.0, // Increased from 0.8 for more natural pace
    },
    'gentle and soothing': {
      'pitch': -3.0,
      'speakingRate': 0.95, // Increased from 0.75
    },
    'warm and compassionate': {
      'pitch': -1.5,
      'speakingRate': 1.0, // Increased from 0.8
    },
    'peaceful and mindful': {
      'pitch': -2.5,
      'speakingRate': 0.9, // Increased from 0.7
    },
  };
  
  String _meditationStyle = 'calm and empathetic';
  
  Future<void> initialize({
    String voiceGender = 'female', 
    String? meditationStyle,
    bool usePremiumVoice = false,
  }) async {
    _meditationStyle = meditationStyle ?? 'calm and empathetic';
    _usePremiumVoice = usePremiumVoice;
    
    _logger.i('Initializing voice (style: $_meditationStyle, premium: $_usePremiumVoice)');
    
    await _initializeFlutterTts();
    
    _isInitialized = true;
    // Check if premium voice is actually available
    final willUsePremium = _usePremiumVoice && MeditationConfig.hasValidTtsKey;
    _logger.i('Voice ready (${willUsePremium ? "using PREMIUM Google Cloud TTS (\$\$\$)" : "using FREE Flutter TTS"})');
  }
  
  Future<void> _initializeFlutterTts() async {
    try {
      await _flutterTts.setLanguage('en-US');
      
      // Optimized settings for calming meditation voice
      await _flutterTts.setSpeechRate(0.42); // Slow and calming (was 0.5)
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(0.90); // Slightly higher for more natural sound (was 0.85)
      
      // CRITICAL: Configure audio session to NOT stop background music
      // Use 'playback' category with 'mixWithOthers' and 'duckOthers' options
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers
        ],
      );
      
      final voices = await _flutterTts.getVoices;
      if (voices != null && voices.isNotEmpty) {
        final enVoices = voices.where((v) => 
          v['locale']?.toString().contains('en') ?? false
        ).toList();
        
        _logger.i('Available TTS voices: ${enVoices.length}');
        
        // Priority order for best free voice:
        // 1. Enhanced/Premium female voices
        // 2. Any female voice
        // 3. Natural-sounding voices
        // 4. Default voice
        
        String? selectedVoice;
        
        // Try to find enhanced/premium female voice
        for (var voice in enVoices) {
          final name = voice['name']?.toString().toLowerCase() ?? '';
          if (name.contains('female') && (name.contains('enhanced') || name.contains('premium') || name.contains('neural'))) {
            selectedVoice = voice['name'].toString();
            await _flutterTts.setVoice({
              'name': voice['name'].toString(),
              'locale': voice['locale'].toString(),
            });
            _logger.i('Using enhanced voice: ${voice['name']}');
            break;
          }
        }
        
        // Fallback to any female voice
        if (selectedVoice == null) {
          for (var voice in enVoices) {
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
        
        // Fallback to first available voice
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
  
  /// Speak text with Google Cloud TTS (high quality)
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    if (_isSpeaking) {
      await Future.delayed(Duration(milliseconds: 500));
      if (_isSpeaking) return;
    }
    
    _isSpeaking = true;
    
    // Clean text for better TTS pronunciation
    String cleanedText = _cleanTextForTTS(text);
    
    try {
      // Only try Google Cloud TTS if user has premium voice enabled
      if (_usePremiumVoice) {
        final success = await _tryGoogleCloudTts(cleanedText);
        if (!success) {
          // Fallback to Flutter TTS if premium fails
          _logger.w('Premium voice failed, falling back to free voice');
          await _speakWithFlutterTts(cleanedText);
        }
      } else {
        // Use free Flutter TTS
        await _speakWithFlutterTts(cleanedText);
      }
    } catch (e) {
      _logger.e('Error during speech: $e');
      await _speakWithFlutterTts(cleanedText);
    } finally {
      _isSpeaking = false;
    }
  }
  
  /// Clean text for better TTS pronunciation
  String _cleanTextForTTS(String text) {
    _logger.i('Cleaning text: "${text.substring(0, text.length > 100 ? 100 : text.length)}..."');
    
    // Replace abbreviations with full words for smoother speech
    String cleaned = text
        // Replace BPM (case-insensitive, any position)
        .replaceAllMapped(RegExp(r'(\d+)\s*BPM', caseSensitive: false), (match) {
          return '${match.group(1)} beats per minute';
        })
        .replaceAll(RegExp(r'\bBPM\b', caseSensitive: false), 'beats per minute')
        // Replace other abbreviations
        .replaceAll(RegExp(r'\bHR\b'), 'heart rate')
        .replaceAll(RegExp(r'\bHRV\b'), 'heart rate variability')
        // Replace milliseconds with spelled-out version
        .replaceAllMapped(RegExp(r'(\d+)\s*ms\b', caseSensitive: false), (match) {
          return '${match.group(1)} milliseconds';
        })
        .replaceAll(RegExp(r'\bms\b'), 'milliseconds')
        // Remove extra whitespace and normalize
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    if (cleaned != text) {
      _logger.i('✨ Cleaned text: "${cleaned.substring(0, cleaned.length > 100 ? 100 : cleaned.length)}..."');
    }
    
    return cleaned;
  }
  
  Future<bool> _tryGoogleCloudTts(String text) async {
    try {
      // Check cache first (separate cache for premium vs free)
      final cachedFile = await MeditationCache.getCachedAudio(text, isPremiumVoice: true);
      if (cachedFile != null) {
        _logger.i('Using cached premium TTS audio (saves 1 API request)');
        
        // Configure audio context to mix with background music
        await _audioPlayer.setAudioContext(AudioContext(
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
        ));
        
        await _audioPlayer.play(DeviceFileSource(cachedFile.path));
        await _audioPlayer.onPlayerComplete.first;
        return true;
      }
      
      final voiceConfig = _femaleVoice;
      final styleSettings = _styleSettings[_meditationStyle] ?? _styleSettings['calm and empathetic']!;
      
      _logger.i('Google Cloud TTS: ${voiceConfig['name']} - API REQUEST');
      
      if (MeditationConfig.googleCloudTtsApiKey == 'NONE' || 
          MeditationConfig.googleCloudTtsApiKey == 'YOUR_TTS_API_KEY_HERE') {
        _logger.i('No API key configured → Using Flutter TTS fallback');
        return false;
      }
      
      final response = await http.post(
        Uri.parse('https://texttospeech.googleapis.com/v1/text:synthesize?key=${MeditationConfig.googleCloudTtsApiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'input': {'text': text},
          'voice': {
            'languageCode': 'en-US',
            'name': voiceConfig['name'],
          },
          'audioConfig': {
            'audioEncoding': 'MP3',
            'pitch': styleSettings['pitch']!,
            'speakingRate': styleSettings['speakingRate']!,
            'volumeGainDb': 0.0,
            'effectsProfileId': ['headphone-class-device'],
          },
        }),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode != 200) {
        _logger.w('Google TTS API error: ${response.statusCode} - Using fallback');
        return false;
      }
      
      final jsonResponse = jsonDecode(response.body);
      final audioContent = jsonResponse['audioContent'];
      
      if (audioContent == null) {
        _logger.w('No audio content in response');
        return false;
      }
      
      final audioBytes = base64Decode(audioContent);
      
      // Cache the audio for future use (mark as premium)
      final cachedAudioFile = await MeditationCache.cacheAudio(text, audioBytes, isPremiumVoice: true);
      
      // Play from cache if successfully cached, otherwise use temp file
      final playFile = cachedAudioFile ?? await _createTempFile(audioBytes);
      
      _logger.i('Playing high-quality Google Cloud TTS audio');
      
      // CRITICAL: Configure audio context to mix with background music
      // This allows TTS voice to play while background ambience continues
      await _audioPlayer.setAudioContext(AudioContext(
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
          audioFocus: AndroidAudioFocus.gainTransientMayDuck, // Duck background, don't stop it
        ),
      ));
      
      // Set release mode to automatically release resources after playback
      await _audioPlayer.setReleaseMode(ReleaseMode.release);
      
      await _audioPlayer.play(DeviceFileSource(playFile.path));
      await _audioPlayer.onPlayerComplete.first;
      
      // Small delay before next segment to prevent audio "pop"
      await Future.delayed(Duration(milliseconds: 100));
      
      // Only delete if it was a temp file (not cached)
      if (cachedAudioFile == null) {
        try {
          await playFile.delete();
        } catch (e) {
          // Ignore cleanup errors
        }
      }
      
      _logger.i('Google Cloud TTS playback complete');
      return true;
      
    } catch (e) {
      _logger.w('Google Cloud TTS error: $e - Using fallback');
      return false;
    }
  }
  
  Future<File> _createTempFile(List<int> audioBytes) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/meditation_${DateTime.now().millisecondsSinceEpoch}.mp3');
    await tempFile.writeAsBytes(audioBytes);
    return tempFile;
  }
  
  Future<void> _speakWithFlutterTts(String text) async {
    _logger.i('Using Flutter TTS fallback');
    
    try {
      // Ensure TTS also allows mixing and ducking
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers
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

      // Sanitize text: Remove markdown and "..." which TTS reads as "dot dot"
      String cleanText = text
          .replaceAll('...', ', ') // Replace ellipses with comma
          .replaceAll('..', ', ')  // Replace double dots
          .replaceAll('*', '')     // Remove bold/italic markers
          .replaceAll('#', '')     // Remove headers
          .replaceAll('"', '')     // Remove quotes if needed
          .replaceAll(RegExp(r'\s+'), ' ') // Collapse whitespace
          .trim();

      await _flutterTts.speak(cleanText);
      
      // Wait for completion with timeout
      try {
        await completer.future.timeout(const Duration(seconds: 45)); // Reduced to 45s
      } catch (e) {
        _logger.w('TTS timed out (likely interruption): $e. Continuing...');
        // If timeout occurs, forcing a stop might help reset state for next sentence
        await _flutterTts.stop(); 
      }
      
    } catch (e) {
      _logger.e('Flutter TTS error: $e');
    }
  }
  
  Future<void> stop() async {
    _isSpeaking = false;
    await _flutterTts.stop();
    // Use release() for smoother audio stop (prevents "pop" sound)
    try {
      await _audioPlayer.release();
    } catch (e) {
      // Fallback to stop if release fails
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
    // Always female - ignore parameter
    _isInitialized = false;
  }
  
  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
  }
  
  bool get isSpeaking => _isSpeaking;
  
  Future<void> testVoice() async {
    await speak('Welcome to your meditation session. I am here to guide you towards a state of calm and relaxation.');
  }
}
