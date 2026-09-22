import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../configs/overall_config.dart';
import 'kokoro_model_installer.dart';

/// Renders text to 16-bit PCM WAV bytes on the phone.
///
/// [KokoroTtsEngine] is the only implementation in the app; the interface
/// exists so callers depend on the synthesis capability rather than on the
/// isolate and native library behind it.
abstract interface class KokoroSynthesizer {
  Future<Uint8List> synthesize({
    required String text,
    required int speakerId,
    required double speed,
  });

  /// Releases the model and whatever is holding it.
  Future<void> shutdown();
}

/// Local narration with Kokoro-82M, run on the phone through sherpa-onnx.
///
/// Synthesis is a blocking native call that takes seconds to tens of seconds
/// for a meditation segment, so it runs in a worker isolate: the native engine
/// handle never leaves that isolate and only the finished audio comes back.
/// The model also costs seconds to load and several hundred MB of memory, so
/// one engine is shared for as long as the in-app is open rather than being
/// built per session.
///
/// Nothing here throws at import time or on a platform without the native
/// library. [shared] returns null when the local voice cannot be used, and the
/// caller then behaves exactly as it does for an unconfigured cloud provider.
class KokoroTtsEngine implements KokoroSynthesizer {
  final SendPort _commands;
  final ReceivePort _exit;
  bool _isRunning = true;

  KokoroTtsEngine._(this._commands, this._exit);

  static KokoroSynthesizer? _shared;
  static Future<KokoroSynthesizer?>? _starting;

  /// Overridable so callers can be tested without the native library.
  @visibleForTesting
  static Future<KokoroSynthesizer?> Function()? startOverride;

  @visibleForTesting
  static void resetForTesting() {
    startOverride = null;
    _shared = null;
    _starting = null;
  }

  /// The engine for this app session, started on first use.
  ///
  /// Returns null when there is no bundled model or the native library is
  /// unavailable. Concurrent callers share one start.
  static Future<KokoroSynthesizer?> shared() {
    final running = _shared;
    if (running != null && _isUsable(running)) return Future.value(running);
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  /// A worker whose isolate has gone away is replaced on the next request.
  /// Anything else — only a test double — is taken at face value.
  static bool _isUsable(KokoroSynthesizer synthesizer) =>
      synthesizer is! KokoroTtsEngine || synthesizer._isRunning;

  static Future<KokoroSynthesizer?> _start() async {
    final override = startOverride;
    if (override != null) return _shared = await override();

    final directory = await KokoroModelInstaller.ensureInstalled();
    if (directory == null) return null;

    final boot = ReceivePort();
    final exit = ReceivePort();
    try {
      await Isolate.spawn(
        _workerMain,
        boot.sendPort,
        onExit: exit.sendPort,
        errorsAreFatal: true,
        debugName: 'kokoro-tts',
      );
    } catch (error) {
      boot.close();
      exit.close();
      debugPrint('Kokoro worker could not be started: $error');
      return null;
    }

    final handshake = await boot.first;
    boot.close();
    if (handshake is! SendPort) {
      exit.close();
      debugPrint('Kokoro worker refused to start: $handshake');
      return null;
    }

    final engine = KokoroTtsEngine._(handshake, exit);
    exit.listen((_) => engine._isRunning = false);

    final created = await engine._send(
      (reply) => _CreateCommand(reply: reply, directory: directory),
      OverallMeditationConfig.kokoroEngineStartTimeout,
    );
    if (created is! _CreatedReply) {
      debugPrint('Kokoro model could not be loaded: $created');
      await engine.shutdown();
      return null;
    }

    return _shared = engine;
  }

  /// Releases the shared engine and the memory its model occupies.
  static Future<void> shutdownShared() async {
    // Let a start that is already in flight finish first: it assigns _shared
    // on completion, so clearing the field before awaiting it would leave a
    // loaded model with nothing referencing it.
    await _starting;
    final running = _shared;
    _shared = null;
    await running?.shutdown();
  }

  bool get isRunning => _isRunning;

  /// Renders [text] as 16-bit PCM WAV bytes.
  @override
  Future<Uint8List> synthesize({
    required String text,
    required int speakerId,
    required double speed,
  }) async {
    if (!_isRunning) {
      throw StateError('The local voice engine is no longer running.');
    }
    final reply = await _send(
      (port) => _SynthesizeCommand(
        reply: port,
        text: text,
        speakerId: speakerId,
        speed: speed,
      ),
      OverallMeditationConfig.kokoroSynthesisTimeout,
    );
    if (reply is _AudioReply) return reply.wav;
    throw KokoroTtsException('$reply');
  }

  @override
  Future<void> shutdown() async {
    if (!_isRunning) {
      _exit.close();
      return;
    }
    _isRunning = false;
    try {
      // Best effort: the isolate is torn down either way when this returns.
      await _send(
        _ShutdownCommand.new,
        OverallMeditationConfig.kokoroEngineStartTimeout,
      );
    } catch (error) {
      debugPrint('Kokoro worker did not shut down cleanly: $error');
    }
    _exit.close();
  }

  Future<Object?> _send(
    Object Function(SendPort reply) build,
    Duration timeout,
  ) async {
    final reply = ReceivePort();
    try {
      _commands.send(build(reply.sendPort));
      return await reply.first.timeout(timeout);
    } finally {
      reply.close();
    }
  }
}

class KokoroTtsException implements Exception {
  final String message;

  const KokoroTtsException(this.message);

  @override
  String toString() => 'Local Kokoro voice failed: $message';
}

// --- Worker isolate -------------------------------------------------------

class _CreateCommand {
  final SendPort reply;
  final String directory;

  const _CreateCommand({required this.reply, required this.directory});
}

class _SynthesizeCommand {
  final SendPort reply;
  final String text;
  final int speakerId;
  final double speed;

  const _SynthesizeCommand({
    required this.reply,
    required this.text,
    required this.speakerId,
    required this.speed,
  });
}

class _ShutdownCommand {
  final SendPort reply;

  const _ShutdownCommand(this.reply);
}

class _CreatedReply {
  final int sampleRate;
  final int speakerCount;

  const _CreatedReply({required this.sampleRate, required this.speakerCount});
}

class _ShutdownReply {
  const _ShutdownReply();
}

class _AudioReply {
  final Uint8List wav;

  const _AudioReply(this.wav);
}

class _FailureReply {
  final String message;

  const _FailureReply(this.message);

  @override
  String toString() => message;
}

void _workerMain(SendPort boot) {
  // sherpa-onnx binds its native library per isolate, so this has to happen
  // here as well as wherever the app first touched the package.
  try {
    sherpa.initBindings();
  } catch (error) {
    boot.send(_FailureReply('native library unavailable: $error'));
    return;
  }

  final commands = ReceivePort();
  boot.send(commands.sendPort);

  sherpa.OfflineTts? tts;
  commands.listen((Object? message) {
    switch (message) {
      case _CreateCommand(:final reply, :final directory):
        try {
          tts?.free();
          tts = sherpa.OfflineTts(_configFor(directory));
          reply.send(
            _CreatedReply(
              sampleRate: tts!.sampleRate,
              speakerCount: tts!.numSpeakers,
            ),
          );
        } catch (error) {
          tts = null;
          reply.send(_FailureReply('$error'));
        }
      case _SynthesizeCommand(
          :final reply,
          :final text,
          :final speakerId,
          :final speed
        ):
        final engine = tts;
        if (engine == null) {
          reply.send(const _FailureReply('no model is loaded'));
          return;
        }
        try {
          final audio = engine.generate(
            text: text,
            sid: speakerId,
            speed: speed,
          );
          reply.send(_AudioReply(encodeWav(audio.samples, audio.sampleRate)));
        } catch (error) {
          reply.send(_FailureReply('$error'));
        }
      case _ShutdownCommand(:final reply):
        tts?.free();
        tts = null;
        reply.send(const _ShutdownReply());
        commands.close();
    }
  });
}

sherpa.OfflineTtsConfig _configFor(String directory) {
  String at(String name) => '$directory/$name';
  return sherpa.OfflineTtsConfig(
    model: sherpa.OfflineTtsModelConfig(
      kokoro: sherpa.OfflineTtsKokoroModelConfig(
        model: at(OverallMeditationConfig.kokoroModelFileName),
        voices: at(OverallMeditationConfig.kokoroVoicesFileName),
        tokens: at(OverallMeditationConfig.kokoroTokensFileName),
        dataDir: at(OverallMeditationConfig.kokoroEspeakDataDirectoryName),
      ),
      numThreads: OverallMeditationConfig.kokoroThreadCount,
      debug: false,
    ),
    maxNumSenetences: OverallMeditationConfig.kokoroMaxSentencesPerBatch,
  );
}

/// Wraps float samples as a 16-bit PCM WAV, the form audioplayers can play
/// from memory without a temporary file.
@visibleForTesting
Uint8List encodeWav(Float32List samples, int sampleRate) {
  const channels = 1;
  const bitsPerSample = 16;
  final dataLength = samples.length * 2;
  final bytes = ByteData(44 + dataLength);

  void writeTag(int offset, String tag) {
    for (var i = 0; i < tag.length; i++) {
      bytes.setUint8(offset + i, tag.codeUnitAt(i));
    }
  }

  writeTag(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  writeTag(8, 'WAVE');
  writeTag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // PCM header size
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(
    28,
    sampleRate * channels * bitsPerSample ~/ 8,
    Endian.little,
  );
  bytes.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
  bytes.setUint16(34, bitsPerSample, Endian.little);
  writeTag(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    // Clamp before scaling: the vocoder can overshoot slightly, and wrapping
    // that into the next sample would be an audible click.
    final sample = samples[i].clamp(-1.0, 1.0);
    bytes.setInt16(44 + i * 2, (sample * 32767).round(), Endian.little);
  }

  return bytes.buffer.asUint8List();
}
