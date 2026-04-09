import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logger/logger.dart';
import 'meditation_config.dart';
import 'user_account.dart';
import 'meditation_cache.dart';

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
  late final GenerativeModel _model;
  ChatSession? _chatSession;
  int _iterationCount = 0;
  UserAccount? _userAccount;
  
  ImprovedMeditationLLMService() {
    _initializeModel();
  }
  
  void _initializeModel() {
    try {
      _model = GenerativeModel(
        model: 'gemini-2.5-flash', // Using newest Gemini model (2026)
        apiKey: MeditationConfig.geminiApiKey,
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
  }
  
  /// Get style-specific guidance for LLM
  String _getStyleGuidance(String style) {
    switch (style) {
      case 'calm and empathetic':
        return '''Your tone should be especially warm and understanding. Show deep compassion for their feelings.
Focus on emotional validation and gentle encouragement. Use phrases like "I understand", "you're safe here", "it's okay to feel this way".''';
      
      case 'gentle and soothing':
        return '''Your tone should be extra soft and nurturing, like a lullaby. Create maximum comfort and safety.
Use very slow pacing, longer pauses. Focus on creating a cocoon of peace. Emphasize softness, gentleness, and protection.''';
      
      case 'warm and compassionate':
        return '''Your tone should radiate kindness and care. Be like a supportive friend who truly understands.
Balance warmth with strength. Acknowledge challenges while building confidence. Use inclusive "we" language often.''';
      
      case 'peaceful and mindful':
        return '''Your tone should be centered and grounded. Emphasize present-moment awareness and acceptance.
Use mindfulness language: observe, notice, allow, let be. Focus on non-judgment and natural flow. Be neutral yet caring.''';
      
      default:
        return '''Your tone should be warm, empathetic, and professional.''';
    }
  }
  
  String _getSystemPrompt() {
    final userContext = _userAccount?.getLLMContext() ?? '';
    
    // Get meditation style guidance
    final style = _userAccount?.meditationStyle ?? 'calm and empathetic';
    final styleGuidance = _getStyleGuidance(style);
    
    return '''You are a highly empathetic, warm, and professional meditation guide with a naturally calming voice.
Your purpose is to lead personalized, adaptive meditations based on real-time biosignals (heart rate and HRV) and user demographics.

$userContext

MEDITATION STYLE: $style
$styleGuidance

CRITICAL GUIDELINES:
1. ALWAYS include specific breathing instructions in every segment:
   - "Breathe in slowly for 4 counts... and breathe out for 6 counts"
   - "Let's take a deep breath together... in through your nose... out through your mouth"
   - "Notice your breath... inhale deeply... exhale completely..."

2. Make it PERSONAL:
   - Use their name naturally (not every sentence, but occasionally)
   - Reference their specific stress triggers if mentioned
   - Use their preferred environment imagery
   - Adapt to their age and fitness level
   - Consider their gender when choosing imagery/language

3. This is a MULTI-SEGMENT meditation:
   - Each response is ONE segment in a longer session
   - Create natural transitions, not endings
   - Build on previous themes and progressions
   - End with gentle pauses that invite continuation
   - DO NOT say "the meditation is now over" unless explicitly asked

4. VARY your approach across segments:
   - Segment 1: Grounding, body awareness, breath focus
   - Segment 2: Progressive muscle relaxation, body scan
   - Segment 3: Calming visualization of their preferred environment
   - Segment 4+: Mix techniques, deepen relaxation, maintain engagement

5. VOICE QUALITY matters:
   - Speak slowly and clearly
   - Use soothing, descriptive language
   - Create natural pauses with ellipses (...)
   - Guide the breathing rhythm with your pacing

6. OUTPUT FORMAT:
   - Plain text only
   - No markdown, no meta-comments
   - Just the spoken meditation words
   - Approximately ${MeditationConfig.targetWordCount} words per segment

Remember: You're creating a calming, safe space for someone who is stressed. Be warm, patient, and genuinely caring.''';
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
      
      final prompt = '''Create a warm, empathetic welcome for a meditation session. 

User Info:
${_userAccount?.getLLMContext() ?? ''}

Current State:
- Status: ${currentHr > baselineHr + 10 ? 'Elevated/Stressed' : 'Calm/Stable'}
- Goal: Deep relaxation and grounding

The user is showing signs of stress. Acknowledge their current state warmly. Reassure them that you'll guide them through a personalized meditation to help them find calm.

CRITICAL INSTRUCTION: Do NOT mention specific heart rate numbers (e.g., don't say "85 BPM"). Just refer to "your racing heart" or "tension in your body" or "your calm state". Focus on FEELING, not metrics.

Use their name naturally if provided. Keep it under 80 words, warm and personal.''';

      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? "${nameGreeting}I notice your heart rate is elevated. Let's work together to bring you back to a state of calm.";
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
      
      _logger.i('Generating segment #$_iterationCount (Stress: ${stressLevel.toStringAsFixed(1)}%) - CALLING GEMINI API...');
      
      final response = await _chatSession!.sendMessage(Content.text(prompt));
      final text = response.text ?? '';
      
      if (text.isEmpty) {
        throw Exception('Empty LLM response');
      }
      
      _logger.i(' SUCCESS! Got ${text.length} characters from Gemini API');
      _logger.i(' First 150 chars: "${text.substring(0, text.length > 150 ? 150 : text.length)}..."');
      
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
      final fallbackText = 'Take a deep breath in... hold gently for a moment... and slowly release. '
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
    final environment = _userAccount?.preferredEnvironment ?? 'nature';
    
    // Define SPECIFIC technique for each segment to prevent repetition
    String technique = '';
    String example = '';
    
    switch (iteration) {
      case 1:
        technique = 'DEEP BELLY BREATHING: Guide slow, gentle breathing. Have them place hand on belly to feel movement. Focus ONLY on breath, no imagery. NO counting - use flowing descriptions instead.';
        example = 'Place your hand gently on your belly. Feel it rise as you breathe in slowly and deeply. Hold for a moment. Now release that breath, long and slow. Feel your belly falling, all tension releasing with each exhale.';
        break;
      case 2:
        technique = 'BODY SCAN: Start at toes, move up through legs, torso, arms, neck, head. Name each part and guide release. NO breath counting here.';
        example = 'Bring your attention to your toes. Notice any tension there. Imagine warm, healing light flowing into your feet, releasing any tightness. Now move up to your calves...';
        break;
      case 3:
        technique = 'VISUALIZATION: Create vivid $environment scene. Describe 3-4 sensory details (sights, sounds, smells, textures). Make them FEEL transported.';
        example = 'Picture yourself in a peaceful $environment. The air is fresh and cool on your skin. You hear gentle sounds around you. Take in the beauty, feeling completely safe and at peace here.';
        break;
      case 4:
        technique = 'PROGRESSIVE MUSCLE RELAXATION: Tense then release specific muscle groups. Start with hands, then arms.';
        example = 'Make a gentle fist with your hands. Feel the tension... hold it... now release completely. Feel the difference as your hands soften, fingers relaxing, all tightness flowing away.';
        break;
      case 5:
        technique = 'LOVING-KINDNESS: Send warmth to self. Use gentle affirmations. Build self-compassion.';
        example = 'Place your hand over your heart. Feel your heartbeat, steady and strong. Silently say to yourself: I am worthy of peace. I am safe. I am calm. Let these words sink in deeply.';
        break;
      default:
        technique = 'BREATH + MANTRA: Combine slow breathing with a calming phrase or word. Repeat gently with each breath.';
        example = 'With each breath in, silently say "I am". With each breath out, say "calm". Breathe in... I am. Breathe out... calm. Let this rhythm carry you deeper into peace.';
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
      final hrImprovement = ((startHr - endHr) / startHr * 100);
      final hrvImprovement = ((endHrv - startHrv) / startHrv * 100);
      
      final userName = _userAccount?.name ?? '';
      final namePrefix = userName.isNotEmpty ? '$userName, ' : '';
      
      final prompt = '''Create a SHORT, warm congratulatory message for completing a meditation.

User: ${userName.isNotEmpty ? userName : 'User'}
Starting heart rate: ${startHr.toStringAsFixed(0)} beats per minute
Ending heart rate: ${endHr.toStringAsFixed(0)} beats per minute

REQUIREMENTS:
1. Use their name once: "${userName}"
2. Mention the biomarker improvement explicitly (e.g., "from ${startHr.toStringAsFixed(0)} to ${endHr.toStringAsFixed(0)} beats per minute")
3. Keep it to 2-3 SHORT sentences maximum (under 50 words)
4. Be warm but concise
5. Write numbers clearly for text-to-speech (avoid "BPM" abbreviation)

EXAMPLE:
"${userName}, wonderful work. Your heart rate has come down from ${startHr.toStringAsFixed(0)} to ${endHr.toStringAsFixed(0)} beats per minute. Carry this peace with you."

Generate a SHORT completion message like the example above.''';

      final response = await _model.generateContent([Content.text(prompt)]);
      final rawText = response.text ?? "${namePrefix}wonderful work. Your heart rate has come down from ${startHr.toStringAsFixed(0)} to ${endHr.toStringAsFixed(0)} beats per minute. You've successfully calmed your mind and body. Carry this peace with you.";
      
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
        .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1)!) // **bold** -> bold
        .replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m.group(1)!) // *italic* -> italic
        .replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m.group(1)!) // __bold__ -> bold
        .replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m.group(1)!) // _italic_ -> italic
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
        .replaceAllMapped(RegExp(r'\s+([,.:;!?])'), (m) => m.group(1)!) // Remove space before punctuation
        .replaceAllMapped(RegExp(r'([,.:;!?])([^\s])'), (m) => '${m.group(1)} ${m.group(2)}') // Add space after punctuation
        .trim();
    
    // SAFETY CHECK: Detect completely invalid content
    final invalidWords = ['dollar', 'money', 'price', 'cost', 'payment', 'currency', '\$'];
    for (final word in invalidWords) {
      if (cleaned.toLowerCase().contains(word)) {
        _logger.e('INVALID CONTENT DETECTED: Text contains "$word" - this is NOT meditation content!');
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


