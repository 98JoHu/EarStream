// ignore_for_file: require_trailing_commas

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logger/logger.dart';
import '../../config/meditation_config.dart';
import '../../config/demo_config.dart';
import '../../config/meditation_runtime_config.dart';
import '../../models/user_account.dart';

final _logger = Logger();

/// LLM-powered meditation content generation service
///
/// Generates personalized, stress-adaptive meditation guidance using Google's Gemini.
/// Falls back to pre-generated personalized texts when API is unavailable.
///
/// Features:
/// - Real-time biosignal integration (current HR/HRV)
/// - Adaptive content based on stress levels
/// - User demographic personalization (age, preferences, style)
/// - Multi-segment sessions with natural progression
/// - Meditation style customization (calm, gentle, mindful)
/// - Environment imagery (nature, ocean, mountain, etc.)
///
/// Uses Gemini 2.0 Flash with custom system prompts for meditation guidance.
class ImprovedMeditationLLMService {
  late GenerativeModel _model;
  ChatSession? _chatSession;
  int _iterationCount = 0;
  UserAccount? _userAccount;
  
  // Demo mode support
  String _demoMode = DemoConfig.modeNone;
  DemoMeditationPreferences? _demoPreferences;
  
  // Get effective word count based on demo mode
  int get _wordCount {
    if (_demoMode != DemoConfig.modeNone) {
      return DemoConfig.segmentWordCount;
    }
    return MeditationConfig.targetWordCount;
  }

  ImprovedMeditationLLMService() {
    _initializeModel();
  }

  void _initializeModel() {
    try {
      _model = GenerativeModel(
        model: 'gemini-2.5-flash', // Using newest Gemini model (2026)
        apiKey: _effectiveGeminiApiKey,
        systemInstruction: Content.system(_getSystemPrompt()),
        generationConfig: GenerationConfig(
          temperature: 0.9,
          maxOutputTokens: 600,
        ),
      );
      _logger.i('Improved Meditation LLM initialized (gemini-2.5-flash)');
    } catch (e) {
      _logger.e('Error initializing LLM: $e');
      rethrow;
    }
  }

  /// Set user account for deep personalization
  void setUserAccount(UserAccount? account) {
    _userAccount = account;
    _logger.i('User account set: ${_userAccount?.name ?? "default"}');
    _initializeModel();
  }
  
  /// Set demo mode configuration
  void setDemoMode({
    required String demoMode,
    DemoMeditationPreferences? demoPreferences,
  }) {
    _demoMode = demoMode;
    _demoPreferences = demoPreferences;
    _logger.i('Demo mode set: $_demoMode');
    if (demoPreferences != null) {
      _logger.i('Demo preferences: ${demoPreferences.toString()}');
    }
    _initializeModel();
  }

  String get _effectiveGeminiApiKey {
    return MeditationRuntimeConfig.geminiApiKey(
          localValue: _userAccount?.geminiApiKey,
        ).value ??
        MeditationConfig.geminiApiKey;
  }

  /// Get style-specific guidance for LLM - REMOVED
  /// Meditation type is now used to determine the overall approach

  String _getSystemPrompt() {
    // In demo mode, use demo preferences instead of user account
    String userContext;
    String meditationType;
    
    if (_demoMode != DemoConfig.modeNone && _demoPreferences != null) {
      // Demo mode: use demo preferences, no demographic info
      meditationType = _demoPreferences!.meditationStyle.toLowerCase().replaceAll(' ', '_');
      userContext = '''DEMO MODE - ACM UbiComp Conference
Meditation Style: ${_demoPreferences!.meditationStyle}
Environment: ${_demoPreferences!.meditationEnvironment}
Voice Tone: ${_demoPreferences!.voiceTone}

This is a demonstration session to showcase personalized meditation capabilities.
Focus on the meditation style and environment provided.
Keep segments concise and impactful (approximately $_wordCount words).''';;
    } else {
      // Normal mode: use full user account context
      userContext = _userAccount?.getLLMContext() ?? '';
      meditationType = _userAccount?.meditationType ?? 'mindfulness';
    }

    return '''You are a highly empathetic, warm, and professional meditation guide with a naturally calming voice.
Your purpose is to lead personalized, adaptive meditations based on real-time biosignals (heart rate and HRV).

$userContext

MEDITATION TYPE: $meditationType
You are guiding a $meditationType meditation session. Stay true to this meditation type throughout all segments.

CRITICAL GUIDELINES:
1. ALWAYS include specific breathing instructions in every segment:
   - "Breathe in slowly for 4 counts... and breathe out for 6 counts"
   - "Let's take a deep breath together... in through your nose... out through your mouth"
   - "Notice your breath... inhale deeply... exhale completely..."

2. Make it PERSONAL:
   ${_demoMode == DemoConfig.modeNone ? '''- Use their name naturally (not every sentence, but occasionally)
   - Reference their specific stress triggers if mentioned
   - Use their meditation environment imagery
   - Adapt to their age and fitness level
   - Consider their gender when choosing imagery/language''' : '''- Speak in a ${_demoPreferences?.voiceTone ?? 'calm'} tone
   - Use the ${_demoPreferences?.meditationStyle ?? 'mindfulness'} meditation approach
   - Create a welcoming, professional demonstration experience'''}

3. This is a MULTI-SEGMENT meditation:
   - Each response is ONE segment in a longer session
   - Create natural transitions, not endings
   - Build on previous themes and progressions
   - End with gentle pauses that invite continuation
   - DO NOT say "the meditation is now over" unless explicitly asked

4. MEDITATION TYPE determines your approach:
   - For 'breathing' or 'breath_focus': Focus heavily on breath awareness, breath counting (if appropriate), pranayama techniques
   - For 'body_scan' or 'progressive_relaxation': Systematically guide attention through body parts, progressive relaxation
   - For 'visualization': Create vivid imagery, sensory immersion
   - For 'mindfulness': Emphasize present-moment awareness, observation without judgment, acceptance
   - For 'loving_kindness': Cultivate compassion, warmth, and kindness towards self and others

5. VOICE QUALITY matters:
   - Speak slowly and clearly
   - Use soothing, descriptive language
   - Create natural pauses with ellipses (...)
   - Guide the breathing rhythm with your pacing

6. OUTPUT FORMAT:
   - Plain text only
   - No markdown, no meta-comments
   - Just the spoken meditation words
   - Approximately $_wordCount words per segment

Remember: You're creating a calming, safe space for someone who may be stressed. Be warm, patient, and genuinely caring.''';
  }

  /// Start a new meditation session
  void startNewSession() {
    _chatSession = _model.startChat();
    _iterationCount = 0;
    _logger.i('New meditation session started');
  }

  /// Generate personalized welcome with actual biomarkers and user info
  Future<String> generatePersonalizedWelcome({
    required double currentHr,
    required double currentHrv,
    required double baselineHr,
    required double baselineHrv,
  }) async {
    try {
      final userName = _userAccount?.name ?? '';
      final nameGreeting = userName.isNotEmpty ? '$userName, ' : '';

      final prompt =
          '''Create a warm, empathetic welcome for a meditation session. 

User Info:
${_userAccount?.getLLMContext() ?? ''}

Current State:
- Status: ${currentHr > baselineHr + 10 ? 'Elevated/Stressed' : 'Calm/Stable'}
- Goal: Deep relaxation and grounding

The user is showing signs of stress. Acknowledge their current state warmly. Reassure them that you'll guide them through a personalized meditation to help them find calm.

CRITICAL INSTRUCTION: Do NOT mention specific heart rate numbers (e.g., don't say "85 BPM"). Just refer to "your racing heart" or "tension in your body" or "your calm state". Focus on FEELING, not metrics.

Use their name naturally if provided. Keep it under 80 words, warm and personal.''';
      print('Generating personalized welcome with prompt:\n$prompt');
      final response = await _model.generateContent([Content.text(prompt)]);
      print('Generated welcome text:\n${response.text ?? ''}');
      return response.text ??
          "${nameGreeting}I notice your heart rate is elevated. Let's work together to bring you back to a state of calm.";
    } catch (e) {
      _logger.e('Error generating welcome: $e');
      return "Welcome. I'm here to guide you through a calming meditation. Let's begin together.";
    }
  }

  /// Generate adaptive meditation segment
  Future<String> generateMeditationSegment({
    required double currentHr,
    required double currentHrv,
    required double baselineHr,
    required double baselineHrv,
    required bool isStressed,
    required double stressLevel,
  }) async {
    _iterationCount++;

    // DISABLE CACHE for meditation segments to ensure unique content every time
    // Each meditation should be fresh and personalized to current biomarkers
    // Note: Voice caching is still active to save API costs for repeated phrases

    if (_chatSession == null) {
      startNewSession();
    }

    try {
      final prompt = _buildDetailedPrompt(
        iteration: _iterationCount,
        isStressed: isStressed,
        stressLevel: stressLevel,
      );

      _logger.i(
          'Generating segment #$_iterationCount (Stress: ${stressLevel.toStringAsFixed(1)}%) - CALLING GEMINI API...');

      final response = await _chatSession!.sendMessage(Content.text(prompt));
      final text = response.text ?? '';

      if (text.isEmpty) {
        throw Exception('Empty LLM response');
      }

      _logger.i(' SUCCESS! Got ${text.length} characters from Gemini API');
      _logger.i(
          ' First 150 chars: "${text.substring(0, text.length > 150 ? 150 : text.length)}..."');

      // Clean text for smooth TTS playback
      final cleanedText = _cleanTextForSpeech(text);

      // Don't cache meditation segments - each should be unique
      // Only cache voice audio to save TTS API costs

      return cleanedText;
    } catch (e) {
      _logger.e(' LLM API Error: $e - Using personalized fallback text');
      // Use simple fallback text when API fails
      _logger.i('Using fallback meditation text (LLM unavailable)');

      // Simple, safe fallback that works for any meditation style
      final fallbackText =
          'Take a deep breath in... hold gently for a moment... and slowly release. '
          'Feel the tension melting away with each exhale. '
          'Your body is becoming more relaxed... your mind more peaceful. '
          'Continue breathing naturally... finding your center... '
          'allowing calmness to flow through you.';

      return fallbackText;
    }
  }

  String _buildDetailedPrompt({
    required int iteration,
    required bool isStressed,
    required double stressLevel,
  }) {
    final userName = _userAccount?.name ?? '';
    final age = _userAccount?.age ?? 30;
    final environment = _userAccount?.meditationEnvironment ?? 'nature';
    final meditationType = _userAccount?.meditationType ?? 'mindfulness';

    // Define technique based on meditation type (not per-segment)
    String technique = '';
    String example = '';

    switch (meditationType) {
      case 'breathing':
        technique =
            'BREATHING MEDITATION: Guide focused breath awareness. Use descriptive language for inhales and exhales. Create a rhythmic flow. Emphasize the naturalness of breathing.';
        example =
            'Bring all your attention to your breath. Feel the cool air as you breathe in... and the warm air as you breathe out. Notice the gentle rise and fall of your chest. Let each breath anchor you to this present moment.';
        break;
      case 'body_scan':
        technique =
            'BODY SCAN: Systematically guide attention through body parts (feet → legs → torso → arms → neck → head). Name each area, invite awareness, encourage release of tension.';
        example =
            'Bring your attention to your feet. Notice any sensations there—warmth, coolness, tingling, or perhaps nothing at all. Simply observe without judgment. Now, gently release any tension you might be holding in your feet.';
        break;
      case 'visualization_journey':
        technique =
            'VISUALIZATION JOURNEY: Create vivid imagery of their meditation environment ($environment). Engage multiple senses (sight, sound, smell, touch). Make them feel transported to a peaceful place.';
        example =
            'Picture yourself in a peaceful $environment. The air is fresh and cool on your skin. You hear gentle sounds around you—perhaps rustling leaves or flowing water. Take in the beauty, feeling completely safe and at peace here.';
        break;
      case 'mindfulness':
      default:
        technique =
            'MINDFULNESS MEDITATION: Guide present-moment awareness. Encourage observation without judgment. Use language like "notice", "observe", "allow", "let be". Emphasize acceptance of thoughts and sensations.';
        example =
            'Notice whatever arises in this moment. Perhaps thoughts drift through your mind like clouds. Simply observe them without grasping or pushing away. Let everything be just as it is. You are safe in this space of awareness.';
        break;
    }

    return '''MEDITATION SEGMENT #$iteration

USER CONTEXT:
- Name: ${userName.isNotEmpty ? userName : 'User'}
- Age: $age
- Environment preference: $environment
- Currently: ${isStressed ? 'needs calming support' : 'relaxing well, maintain peace'}

YOUR TASK:
$technique

STRICT RULES (BREAKING THESE CAUSES ERRORS):

1. NO GREETINGS: Don't say "hello", "hi", "hello again", "welcome back"
2. NO BIOMARKER NUMBERS: Don't mention heart rate, HRV, or any numbers about their health
3. NO META-TALK: Don't say "let's do", "now we'll", "in this segment"
4. NO RANDOM WORDS: NEVER say "dollars", "money", "price", or any non-meditation words
5. NO COUNTING: Don't count breaths (no "one, two, three, four"). Use flowing descriptions like "breathe in deeply... and release slowly"
6. JUMP STRAIGHT INTO THE TECHNIQUE: Start immediately with the meditation instruction
7. USE NAME SPARINGLY: Maximum once, naturally integrated (or not at all if it doesn't flow)
8. SMOOTH FLOW: Write in complete, flowing sentences. Use "..." for natural pauses
9. ONE TECHNIQUE ONLY: Stick to the technique above, don't mix multiple techniques
10. APPROXIMATELY 100 WORDS: Not too short, not too long
11. NO ENDING: Don't conclude. Just pause naturally so next segment can continue
12. MEDITATION VOCABULARY ONLY: Use only calming, meditation-appropriate words (breath, calm, peace, relax, gentle, etc.)

EXAMPLE (DO NOT COPY - just shows the style):
$example

NOW GENERATE SEGMENT #$iteration:
Write a smooth, calming meditation using the technique above. Start directly with the instruction. Make it feel like a continuous flow, not a new "chapter". No greetings, no numbers, just pure meditation guidance.''';
  }

  /// Generate completion message
  Future<String> generateCompletionText({
    required double startHr,
    required double startHrv,
    required double endHr,
    required double endHrv,
  }) async {
    try {
      final userName = _userAccount?.name ?? '';
      final namePrefix = userName.isNotEmpty ? '$userName, ' : '';

      final prompt =
          '''Create a SHORT, warm congratulatory message for completing a meditation.

User: ${userName.isNotEmpty ? userName : 'User'}
Starting heart rate: ${startHr.toStringAsFixed(0)} beats per minute
Ending heart rate: ${endHr.toStringAsFixed(0)} beats per minute

REQUIREMENTS:
1. Use their name once: "$userName"
2. Mention the biomarker improvement explicitly (e.g., "from ${startHr.toStringAsFixed(0)} to ${endHr.toStringAsFixed(0)} beats per minute")
3. Keep it to 2-3 SHORT sentences maximum (under 50 words)
4. Be warm but concise
5. Write numbers clearly for text-to-speech (avoid "BPM" abbreviation)

EXAMPLE:
"$userName, wonderful work. Your heart rate has come down from ${startHr.toStringAsFixed(0)} to ${endHr.toStringAsFixed(0)} beats per minute. Carry this peace with you."

Generate a SHORT completion message like the example above.''';

      final response = await _model.generateContent([Content.text(prompt)]);
      final rawText = response.text ??
          "${namePrefix}wonderful work. Your heart rate has come down from ${startHr.toStringAsFixed(0)} to ${endHr.toStringAsFixed(0)} beats per minute. You've successfully calmed your mind and body. Carry this peace with you.";

      // Clean text for smooth speech
      final completionText = _cleanTextForSpeech(rawText);

      _logger.i(' Completion message generated: "$completionText"');
      return completionText;
    } catch (e) {
      _logger.e('Error generating completion: $e');
      return MeditationConfig.completionText;
    }
  }

  /// Clean text for smooth speech synthesis
  String _cleanTextForSpeech(String text) {
    String cleaned = text
        // Remove any newlines that might cause pauses
        .replaceAll('\n', ' ')
        // Remove markdown formatting - MUST use replaceAllMapped for capture groups!
        .replaceAllMapped(
            RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1)!) // **bold** -> bold
        .replaceAllMapped(
            RegExp(r'\*([^*]+)\*'), (m) => m.group(1)!) // *italic* -> italic
        .replaceAllMapped(
            RegExp(r'__([^_]+)__'), (m) => m.group(1)!) // __bold__ -> bold
        .replaceAllMapped(
            RegExp(r'_([^_]+)_'), (m) => m.group(1)!) // _italic_ -> italic
        // Normalize ellipses for natural pauses
        .replaceAll(RegExp(r'\.{2,}'), '...') // Multiple dots -> exactly 3
        // CRITICAL FIX: Remove standalone digit patterns that TTS might misinterpret
        // Replace "1, 2, 3, 4" patterns with spelled-out words
        .replaceAllMapped(RegExp(r'\b1\b'), (match) => 'one')
        .replaceAllMapped(RegExp(r'\b2\b'), (match) => 'two')
        .replaceAllMapped(RegExp(r'\b3\b'), (match) => 'three')
        .replaceAllMapped(RegExp(r'\b4\b'), (match) => 'four')
        .replaceAllMapped(RegExp(r'\b5\b'), (match) => 'five')
        .replaceAllMapped(RegExp(r'\b6\b'), (match) => 'six')
        .replaceAllMapped(RegExp(r'\b7\b'), (match) => 'seven')
        .replaceAllMapped(RegExp(r'\b8\b'), (match) => 'eight')
        .replaceAllMapped(RegExp(r'\b9\b'), (match) => 'nine')
        .replaceAllMapped(RegExp(r'\b10\b'), (match) => 'ten')
        // Remove extra whitespace
        .replaceAll(RegExp(r'\s+'), ' ')
        // Clean up punctuation spacing - MUST use replaceAllMapped for capture groups!
        .replaceAllMapped(RegExp(r'\s+([,.:;!?])'),
            (m) => m.group(1)!) // Remove space before punctuation
        .replaceAllMapped(RegExp(r'([,.:;!?])([^\s])'),
            (m) => '${m.group(1)} ${m.group(2)}') // Add space after punctuation
        .trim();

    // SAFETY CHECK: Detect completely invalid content
    final invalidWords = [
      'dollar',
      'money',
      'price',
      'cost',
      'payment',
      'currency',
      '\$'
    ];
    for (final word in invalidWords) {
      if (cleaned.toLowerCase().contains(word)) {
        _logger.e(
            'INVALID CONTENT DETECTED: Text contains "$word" - this is NOT meditation content!');
        _logger.e('   Problematic text: "$cleaned"');
        // Return a safe fallback instead
        return 'Take a deep breath in... and slowly breathe out. Feel yourself becoming more calm and peaceful with each breath.';
      }
    }

    return cleaned;
  }

  void reset() {
    _chatSession = null;
    _iterationCount = 0;
  }

  void dispose() {
    reset();
  }
}
