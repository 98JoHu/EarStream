// Covers the narration pipeline: a segment is generated and synthesized while
// the previous one is still speaking, instead of in the silence after it.
//
// These tests drive a real [Meditation] end to end, so they stand in for the
// Android audio stack. [_FakeAudioPlatform] answers the audioplayers method
// channel and pushes the `prepared` and `complete` events the plugin normally
// receives from the native player; the narration voice is a fake [TtsProvider]
// that records when each synthesis starts.

import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/apps/meditation_app/configs/overall_config.dart';
import 'package:open_wearable/apps/meditation_app/model/meditation.dart';
import 'package:open_wearable/apps/meditation_app/model/tts_service.dart';
import 'package:open_wearable/apps/meditation_app/model/user_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Installed for the whole file: an AudioPlayer disposes itself off the test's
  // own timeline, so tearing the channel down per test only produces noise.
  final audio = _FakeAudioPlatform();
  setUpAll(audio.install);
  tearDownAll(audio.uninstall);

  group('narration pipeline', () {
    test('a session speaks every segment and then finishes', () async {
      final provider = _RecordingTtsProvider();
      final meditation = _PipelineMeditation(
        provider: provider,
        maxSegments: 3,
      );
      addTearDown(meditation.dispose);

      await meditation.start().timeout(const Duration(seconds: 30));

      expect(meditation.phase.value, MeditationPhase.finished);
      // Welcome, three segments, completion.
      expect(provider.playedTexts, hasLength(5));
      expect(provider.playedTexts.first, contains('Welcome'));
      expect(provider.playedTexts.last, contains('Wonderful work'));
    });

    test('the next narration is synthesized while the current one plays',
        () async {
      final provider = _RecordingTtsProvider();
      final meditation = _PipelineMeditation(
        provider: provider,
        maxSegments: 3,
      );
      addTearDown(meditation.dispose);

      await meditation.start().timeout(const Duration(seconds: 30));

      final timeline = meditation.timeline;
      // The welcome is the one narration nothing can precede, so its synthesis
      // is awaited on its own. Everything after it overlaps playback.
      expect(timeline.take(2), ['synthesizing:1', 'synthesized:1']);

      // While the welcome plays, the first segment and the completion message
      // are already being produced.
      final welcomeFinished = timeline.indexOf('played:1');
      expect(timeline.indexOf('synthesizing:2'), lessThan(welcomeFinished));
      expect(timeline.indexOf('synthesizing:3'), lessThan(welcomeFinished));

      // And the later segments are produced while an earlier one is speaking,
      // not in the gap after it.
      final firstSegmentFinished = timeline.indexOf('played:2');
      expect(
        timeline.indexOf('synthesizing:4'),
        lessThan(firstSegmentFinished),
      );

      // Nothing was synthesized twice.
      expect(
        timeline.where((entry) => entry.startsWith('synthesizing:')),
        hasLength(5),
      );
    });

    test('a segment produced ahead of an early exit is never spoken', () async {
      final provider = _RecordingTtsProvider();
      final meditation = _PipelineMeditation(
        provider: provider,
        maxSegments: 5,
        exitAfterSegments: 1,
      );
      addTearDown(meditation.dispose);

      await meditation.start().timeout(const Duration(seconds: 30));

      expect(meditation.phase.value, MeditationPhase.finished);
      // Welcome, one segment, completion. The prefetched segments were
      // produced but discarded rather than played.
      expect(provider.playedTexts, hasLength(3));
      expect(provider.playedTexts.last, contains('Wonderful work'));
      expect(
        provider.synthesizedTexts.length,
        greaterThan(provider.playedTexts.length),
        reason: 'the producer should have run ahead of the exit decision',
      );
    });

    test('narration prepared before a voice outage is still played', () async {
      // Welcome, first segment and completion message synthesize; the second
      // segment is where the voice service goes away for good.
      final provider = _RecordingTtsProvider(failAfterSyntheses: 3);
      final meditation = _PipelineMeditation(
        provider: provider,
        maxSegments: 5,
      );
      addTearDown(meditation.dispose);

      await meditation.start().timeout(const Duration(seconds: 30));

      expect(meditation.phase.value, MeditationPhase.failed);
      expect(meditation.failureTitle, 'Voice service interrupted');
      // The segment that was already in hand was spoken rather than dropped.
      expect(provider.playedTexts, hasLength(2));
      expect(provider.playedTexts.first, contains('Welcome'));
    });

    test('a stopped session neither plays nor keeps producing', () async {
      final provider = _RecordingTtsProvider();
      final meditation = _PipelineMeditation(
        provider: provider,
        maxSegments: 5,
        stopAfterSegments: 1,
      );
      addTearDown(meditation.dispose);

      await meditation.start().timeout(const Duration(seconds: 30));

      expect(meditation.phase.value, isNot(MeditationPhase.failed));
      // Welcome and the one segment; no completion message after a stop.
      expect(provider.playedTexts, hasLength(2));

      final producedAtStop = provider.synthesizedTexts.length;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(provider.synthesizedTexts, hasLength(producedAtStop));
    });
  });

  group('narration lookahead depth', () {
    test('a session without biosignals uses the configured depth', () {
      final meditation = _PipelineMeditation(
        provider: _RecordingTtsProvider(),
        maxSegments: 1,
      );
      addTearDown(meditation.dispose);
      expect(
        meditation.narrationPrefetchDepth,
        OverallMeditationConfig.narrationPrefetchDepth,
      );
      expect(OverallMeditationConfig.narrationPrefetchDepth, greaterThan(1));
    });

    test('the producer stays within the lookahead depth', () async {
      final provider = _RecordingTtsProvider();
      final meditation = _PipelineMeditation(
        provider: provider,
        maxSegments: 12,
        exitAfterSegments: 1,
      );
      addTearDown(meditation.dispose);

      await meditation.start().timeout(const Duration(seconds: 30));

      // Welcome, completion, the first segment, and at most a full buffer
      // beyond it. Without the bound the producer would have raced through
      // all twelve segments while the first one played.
      expect(
        provider.synthesizedTexts.length,
        lessThanOrEqualTo(
          3 + OverallMeditationConfig.narrationPrefetchDepth + 1,
        ),
      );
    });
  });

  group('prepared narration', () {
    test('synthesis happens in prepare, not in play', () async {
      final provider = _RecordingTtsProvider();
      final service = TtsService(
        userAccount: UserAccount(),
        provider: provider,
      );
      addTearDown(service.dispose);

      final narration = await service.prepare('breathe out slowly');
      expect(provider.synthesizedTexts, ['breathe out slowly']);
      expect(narration.isDeviceSpoken, isFalse);

      await service.play(narration);
      expect(provider.synthesizedTexts, ['breathe out slowly']);
    });

    test('synthesis retries, playback of the result does not', () async {
      final provider = _RecordingTtsProvider(failuresBeforeSuccess: 2);
      final service = TtsService(
        userAccount: UserAccount(),
        provider: provider,
      );
      addTearDown(service.dispose);

      final narration = await service.prepare('settle into the chair');
      expect(
        provider.synthesizedTexts,
        hasLength(OverallMeditationConfig.cloudTtsRetryDelays.length),
      );
      expect(narration.sources, isNotNull);
    });

    test('a voice service that never recovers stops the session', () async {
      final provider = _RecordingTtsProvider(failuresBeforeSuccess: 99);
      final service = TtsService(
        userAccount: UserAccount(),
        provider: provider,
      );
      addTearDown(service.dispose);

      await expectLater(
        service.prepare('this will not arrive'),
        throwsA(isA<TtsSessionException>()),
      );
    });

    test('a session without a usable cloud voice speaks on the device', () {
      // No provider override and no credentials: nothing to synthesize ahead.
      const narration = PreparedNarration(text: 'spoken by the phone');
      expect(narration.isDeviceSpoken, isTrue);
    });
  });
}

/// A [Meditation] whose narration comes from a fake voice and which can be
/// told to exit or stop after a given number of segments.
class _PipelineMeditation extends Meditation {
  final _RecordingTtsProvider provider;
  final int? exitAfterSegments;
  final int? stopAfterSegments;
  int _segmentsPlayed = 0;

  _PipelineMeditation({
    required this.provider,
    required super.maxSegments,
    this.exitAfterSegments,
    this.stopAfterSegments,
  }) : super(userAccount: UserAccount()) {
    provider.timeline = timeline;
  }

  final List<String> timeline = [];

  @override
  TtsService createTtsService() =>
      TtsService(userAccount: userAccount, provider: provider);

  @override
  bool checkEarlyExit() {
    _segmentsPlayed++;
    if (stopAfterSegments != null && _segmentsPlayed >= stopAfterSegments!) {
      unawaited(stop());
      return true;
    }
    return exitAfterSegments != null && _segmentsPlayed >= exitAfterSegments!;
  }
}

/// Records when each synthesis starts and finishes, and when the audio it
/// produced is played, on a single shared timeline.
class _RecordingTtsProvider implements TtsProvider {
  static const _synthesisDelay = Duration(milliseconds: 20);

  int failuresBeforeSuccess;

  /// After this many successful syntheses the fake voice service never
  /// recovers, standing in for a cloud outage mid-session.
  final int? failAfterSyntheses;

  final List<String> synthesizedTexts = [];
  final List<String> playedTexts = [];
  List<String> timeline = [];

  final Map<int, String> _textBySourceTag = {};
  int _synthesisCount = 0;

  _RecordingTtsProvider({
    this.failuresBeforeSuccess = 0,
    this.failAfterSyntheses,
  });

  @override
  bool get isAvailable => true;

  @override
  Future<List<Source>> synthesize(String text) async {
    synthesizedTexts.add(text);
    final index = ++_synthesisCount;
    timeline.add('synthesizing:$index');
    await Future<void>.delayed(_synthesisDelay);
    if (failAfterSyntheses != null && index > failAfterSyntheses!) {
      throw StateError('the fake voice service went away');
    }
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      throw StateError('the fake voice service is unavailable');
    }
    timeline.add('synthesized:$index');
    // The tag travels in the audio bytes so playback can be attributed back to
    // the text that produced it.
    final bytes = Uint8List.fromList([index]);
    _textBySourceTag[index] = text;
    return [_TaggedSource(index, this, BytesSource(bytes))];
  }

  void _onPlaybackStarted(int tag) {
    playedTexts.add(_textBySourceTag[tag]!);
    timeline.add('playing:$tag');
  }

  void _onPlaybackFinished(int tag) => timeline.add('played:$tag');

  @override
  void dispose() {}
}

/// A [Source] that reports to its provider when it is handed to the player.
class _TaggedSource extends Source {
  final int tag;
  final _RecordingTtsProvider owner;
  final BytesSource delegate;

  _TaggedSource(this.tag, this.owner, this.delegate);

  @override
  String? get mimeType => delegate.mimeType;

  @override
  Future<void> setOnPlayer(AudioPlayer player) async {
    owner._onPlaybackStarted(tag);
    unawaited(
      player.onPlayerComplete.first.then((_) => owner._onPlaybackFinished(tag)),
    );
    await delegate.setOnPlayer(player);
  }
}

/// Stands in for the native audioplayers implementation.
///
/// The plugin waits for a `prepared` event before it will resume, and the
/// narration player waits for `complete` before moving on, so both have to be
/// pushed back through the event channel the way the platform would.
class _FakeAudioPlatform {
  static const _playbackDuration = Duration(milliseconds: 60);
  static const _methodChannel = MethodChannel('xyz.luan/audioplayers');
  static const _globalChannel = MethodChannel('xyz.luan/audioplayers.global');
  static const _pathProvider =
      MethodChannel('plugins.flutter.io/path_provider');
  static const _codec = StandardMethodCodec();

  final _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final Set<String> _players = {};
  final Set<String> _stopped = {};

  void install() {
    _messenger.setMockMethodCallHandler(_methodChannel, _handle);
    _messenger.setMockMethodCallHandler(_globalChannel, (_) async => null);
    _messenger.setMockMethodCallHandler(
      _pathProvider,
      (_) async => Directory.systemTemp.path,
    );
    // The background-music asset is 200+ MB of WAV on disk; the player never
    // decodes it here, so a stub of a few bytes is enough.
    _messenger.setMockMessageHandler(
      'flutter/assets',
      (_) async => ByteData.view(Uint8List.fromList(const [0, 0, 0, 0]).buffer),
    );
  }

  void uninstall() {
    _messenger.setMockMethodCallHandler(_methodChannel, null);
    _messenger.setMockMethodCallHandler(_globalChannel, null);
    _messenger.setMockMethodCallHandler(_pathProvider, null);
    _messenger.setMockMessageHandler('flutter/assets', null);
    for (final playerId in _players) {
      _messenger.setMockMethodCallHandler(
        MethodChannel(_eventChannelName(playerId)),
        null,
      );
    }
    _players.clear();
  }

  static String _eventChannelName(String playerId) =>
      'xyz.luan/audioplayers/events/$playerId';

  Future<Object?> _handle(MethodCall call) async {
    final arguments = call.arguments as Map<Object?, Object?>?;
    final playerId = arguments?['playerId'] as String?;

    switch (call.method) {
      case 'create':
        _players.add(playerId!);
        _messenger.setMockMethodCallHandler(
          MethodChannel(_eventChannelName(playerId)),
          (_) async => null,
        );
      case 'setSourceUrl':
      case 'setSourceBytes':
        _stopped.remove(playerId);
        _emit(playerId!, const {'event': 'audio.onPrepared', 'value': true});
      case 'resume':
        _resumeAndComplete(playerId!);
      case 'stop':
      case 'pause':
      case 'release':
        _stopped.add(playerId!);
      case 'dispose':
        _stopped.add(playerId!);
        _players.remove(playerId);
      case 'getCurrentPosition':
        return 0;
    }
    return null;
  }

  void _resumeAndComplete(String playerId) {
    Future<void>.delayed(_playbackDuration, () {
      if (_stopped.contains(playerId) || !_players.contains(playerId)) return;
      _emit(playerId, const {'event': 'audio.onComplete'});
    });
  }

  /// Delivered on a later turn so the plugin's stream subscription is in place.
  void _emit(String playerId, Map<String, Object?> event) {
    Future<void>.delayed(Duration.zero, () {
      if (!_players.contains(playerId)) return;
      _messenger.handlePlatformMessage(
        _eventChannelName(playerId),
        _codec.encodeSuccessEnvelope(event),
        (_) {},
      );
    });
  }
}
