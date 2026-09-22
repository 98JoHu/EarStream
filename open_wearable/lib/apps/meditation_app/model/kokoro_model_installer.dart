import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../configs/overall_config.dart';

/// Where the bundled Kokoro model lives once it is usable from the filesystem.
///
/// The model is shipped as a native Android asset directory rather than a
/// Flutter asset, because it is a tree of several hundred files (espeak-ng's
/// phoneme data) totalling about 340 MB. Flutter's `assets:` declarations do
/// not recurse into sub-directories, and `rootBundle.load` would pull the whole
/// 330 MB ONNX graph into memory as a single `ByteData`. Android's own
/// `AssetManager` can walk the tree and stream each file out in chunks, so the
/// copy runs in constant memory.
///
/// ONNX Runtime needs real filesystem paths, so the one-time copy out of the
/// APK is unavoidable. It costs roughly 340 MB of app storage on top of the
/// APK itself.
///
/// Everything here degrades quietly: on a platform without the channel, or in
/// a build where the asset directory was left out, [ensureInstalled] reports
/// that there is no model and the app falls back exactly as it does for an
/// unverified cloud key.
abstract final class KokoroModelInstaller {
  static const MethodChannel _channel =
      MethodChannel('edu.kit.teco.open_wearable/kokoro_model');

  @visibleForTesting
  static MethodChannel get channel => _channel;

  /// Overridable so tests can exercise the callers without a platform channel.
  @visibleForTesting
  static Future<Map<String, Object?>> Function(String method)? invokeOverride;

  @visibleForTesting
  static void resetForTesting() => invokeOverride = null;

  static bool get isSupported {
    if (invokeOverride != null) return true;
    try {
      return Platform.isAndroid;
    } on UnsupportedError {
      return false; // web
    }
  }

  /// Whether the model is bundled in this build, without copying anything.
  ///
  /// Cheap enough to run when the in-app opens, so selecting Kokoro does not
  /// require a visit to the API Keys page first.
  static Future<bool> isBundled() async {
    final status = await _invoke('status');
    return status['bundled'] == true;
  }

  /// Copies the model out of the APK if it is not already in app storage and
  /// returns the directory holding it, or null when there is no model to use.
  ///
  /// Files already present with the expected size are skipped, so this is
  /// cheap on every run after the first.
  static Future<String?> ensureInstalled() async {
    final result = await _invoke('install')
        .timeout(OverallMeditationConfig.kokoroModelInstallTimeout);
    final directory = result['directory'] as String?;
    if (directory == null || directory.isEmpty) return null;
    return directory;
  }

  static Future<Map<String, Object?>> _invoke(String method) async {
    final override = invokeOverride;
    if (override != null) return override(method);
    if (!isSupported) return const {};
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(method);
      return result ?? const {};
    } on TimeoutException {
      rethrow;
    } catch (error) {
      // A missing or broken local model must never be worse than not having
      // configured it: the caller treats this as "no local voice".
      debugPrint('Kokoro model $method failed: $error');
      return const {};
    }
  }
}
