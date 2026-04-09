import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:logger/logger.dart';

final _logger = Logger();

/// Cache manager for meditation audio and content
/// 
/// Caches:
/// - TTS audio files (separate caches for premium vs free voices)
/// 
/// Does NOT cache:
/// - LLM meditation segments (disabled for uniqueness)
/// - Welcome/completion messages
class MeditationCache {
  static const int _cacheDurationDays = 7;
  
  /// EMERGENCY: Clear ALL cached audio (use if cache is corrupted)
  static Future<void> clearAllCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/tts_cache');
      
      if (await cacheDir.exists()) {
        _logger.w('CLEARING ALL TTS CACHE (emergency fix)');
        await cacheDir.delete(recursive: true);
        _logger.i('Cache cleared successfully');
      } else {
        _logger.i('No cache to clear');
      }
    } catch (e) {
      _logger.e('Failed to clear cache: $e');
    }
  }
  
  /// Clear old cached audio files (older than _cacheDurationDays)
  static Future<void> clearOldCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/tts_cache');
      
      if (!await cacheDir.exists()) return;
      
      final now = DateTime.now();
      final files = await cacheDir.list().toList();
      int deletedCount = 0;
      
      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          final age = now.difference(stat.modified);
          
          if (age.inDays > _cacheDurationDays) {
            await file.delete();
            deletedCount++;
          }
        }
      }
      
      if (deletedCount > 0) {
        _logger.i('Cleared $deletedCount old cached files');
      }
    } catch (e) {
      _logger.e('Failed to clear old cache: $e');
    }
  }
  
  /// Get cache size in bytes
  static Future<int> getCacheSize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/tts_cache');
      
      if (!await cacheDir.exists()) return 0;
      
      int totalSize = 0;
      final files = await cacheDir.list().toList();
      
      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          totalSize += stat.size;
        }
      }
      
      return totalSize;
    } catch (e) {
      _logger.e('Failed to get cache size: $e');
      return 0;
    }
  }
  
  /// Get cached TTS audio file
  /// [isPremiumVoice] ensures premium and free TTS have separate caches
  static Future<File?> getCachedAudio(String text, {bool isPremiumVoice = false}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/tts_cache');
      
      if (!await cacheDir.exists()) {
        return null;
      }
      
      // Include voice type in cache key to separate premium/free audio
      final voiceTypeSuffix = isPremiumVoice ? 'premium' : 'free';
      final hash = '${text.hashCode.abs().toString()}_$voiceTypeSuffix';
      final file = File('${cacheDir.path}/$hash.mp3');
      
      if (await file.exists()) {
        // Check if file is not corrupted (has reasonable size)
        final stat = await file.stat();
        if (stat.size < 1000) {
          _logger.w('Corrupted cache file detected (too small): ${file.path}');
          await file.delete();
          return null;
        }
        
        // Check if file is not too old
        final age = DateTime.now().difference(stat.modified);
        if (age.inDays > _cacheDurationDays) {
          await file.delete();
          return null;
        }
        
        return file;
      }
      
      return null;
    } catch (e) {
      _logger.e('Failed to get cached audio: $e');
      return null;
    }
  }
  
  /// Cache TTS audio file
  /// [isPremiumVoice] ensures premium and free TTS have separate caches
  static Future<File?> cacheAudio(String text, List<int> audioBytes, {bool isPremiumVoice = false}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/tts_cache');
      
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      
      // Include voice type in cache key to separate premium/free audio
      final voiceTypeSuffix = isPremiumVoice ? 'premium' : 'free';
      final hash = '${text.hashCode.abs().toString()}_$voiceTypeSuffix';
      final file = File('${cacheDir.path}/$hash.mp3');
      
      await file.writeAsBytes(audioBytes);
      _logger.i('Cached TTS audio (${text.length} chars, ${audioBytes.length} bytes)');
      
      return file;
    } catch (e) {
      _logger.e('Failed to cache audio: $e');
      return null;
    }
  }
}
