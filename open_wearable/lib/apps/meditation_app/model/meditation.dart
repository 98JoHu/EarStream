import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'user_account.dart';
import 'measurement.dart';

class Meditation {
  final UserAccount userAccount;
  final Measurement measurement;
  final AudioPlayer musicPlayer = AudioPlayer();
  final FlutterTts voicePlayer = FlutterTts();
  // late final List<MeditationSegment> segments;

  Meditation({required this.userAccount, required this.measurement}) {
    initializeAudioPlayers();
  }

  void initializeAudioPlayers() async {
    // Initialize the music player
    await musicPlayer.setReleaseMode(ReleaseMode.loop);
    await musicPlayer.setVolume(0.3);

    // Initialize the voice player
    await voicePlayer.setLanguage("en-US");
    await voicePlayer.setSpeechRate(0.4);
    await voicePlayer.setVolume(1.0);
  }

  Future<void> start() async {
    // Reset the segments list to ensure a fresh start for each meditation session
    // segments.clear();

    // Start background music
    musicPlayer.audioCache =
        AudioCache(prefix: "lib/apps/meditation_app/assets/audio/");
    await musicPlayer.play(
      AssetSource(
        userAccount.meditationEnvironment?.assetPath ??
            MeditationEnvironment.nature.assetPath,
      ),
    );

    // Generate welcome message
    // TODO: Implement LLM generation
    String welcomeMessage =
        "Welcome. I'm here to guide you through a calming meditation. Let's begin together.";

    // Read the welcome message out loud
    await voicePlayer.speak(welcomeMessage);

    // for (MeditationSegment segment in segments) {
    //   await segment.start();
    //   measurement.checkStressLevel();
    // }
  }

  Future<void> stop() async {
    await musicPlayer.stop();
    await voicePlayer.stop();
  }

  void pause() {
    musicPlayer.pause();
    voicePlayer.pause();
  }
}

class MeditationSegment {
  final String text;
  final Duration duration;

  MeditationSegment({required this.text, required this.duration});

  Future<void> start() async {}
}
