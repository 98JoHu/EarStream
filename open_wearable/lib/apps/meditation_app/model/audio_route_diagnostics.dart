import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'hr_hrv_diagnostics.dart';

/// Reads which output device Android is actually using for playback.
///
/// PPG delivery collapses from 200 Hz to roughly 67 Hz in some sessions a few
/// seconds after audio starts, and not at all in others, with the same build
/// and the same earbud. The collapse lands *before* the first narration, so it
/// is not narration; and one session played ambience and all three narration
/// segments with no degradation at all, so it is not simply ambience either.
/// Nothing in Dart can see which device Android chose, which is why this
/// crosses into the platform layer.
///
/// Read-only: it never changes routing, volume, focus or any Bluetooth
/// profile. It reports nothing unless the biosignal trace is enabled, so a
/// normal build never invokes the platform channel at all.
abstract final class AudioRouteDiagnostics {
  static const MethodChannel _channel =
      MethodChannel('edu.kit.teco.open_wearable/audio_route');

  @visibleForTesting
  static MethodChannel get channel => _channel;

  /// Whether a route snapshot is worth taking at all.
  static bool get isAvailable {
    if (!HrHrvDiagnosticSettings.enabled) return false;
    try {
      return Platform.isAndroid;
    } on UnsupportedError {
      return false; // web
    }
  }

  /// A snapshot of the current audio route, or an empty map when unavailable.
  /// Never throws: a diagnostic must not be able to disturb a meditation.
  static Future<Map<String, Object?>> describe() async {
    if (!isAvailable) return const {};
    return readRoute();
  }

  /// Invokes the platform channel regardless of gating. Separated from
  /// [describe] so the failure handling can be tested without a device and
  /// without the trace flag set.
  @visibleForTesting
  static Future<Map<String, Object?>> readRoute() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, Object?>('describe');
      return result ?? const {};
    } catch (error) {
      return {'audio_route_error': error.runtimeType.toString()};
    }
  }
}
