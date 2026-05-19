// ignore_for_file: require_trailing_commas

import 'package:flutter/material.dart';
import '../../../models/user_account.dart';

/// Beautiful onboarding screen for user account setup
class UserOnboardingScreen extends StatefulWidget {
  final UserAccount? existingAccount;

  const UserOnboardingScreen({super.key, this.existingAccount});

  @override
  State<UserOnboardingScreen> createState() => _UserOnboardingScreenState();
}

class _UserOnboardingScreenState extends State<UserOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  late PageController _pageController;
  int _currentPage = 0;

  // Form fields
  late TextEditingController _nameController;
  late TextEditingController _ageController;
  late TextEditingController _elevenLabsApiKeyController;
  late TextEditingController _microsoftGraphTokenController;
  String _gender = 'other';
  String _fitnessLevel = 'moderate';
  String _voiceGender = 'female';
  String _meditationType = 'mindfulness';
  String _meditationEnvironment = 'peaceful nature';
  String _speakingSpeed = 'slow';
  late TextEditingController _additionalPreferencesController;
  double _stressThreshold = 0.10; // 10% by default
  bool _usePremiumVoice = false; // Premium voice toggle

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    // Load existing data if available
    final account = widget.existingAccount;
    _nameController = TextEditingController(text: account?.name ?? '');
    _ageController = TextEditingController(text: account?.age.toString() ?? '');
    _elevenLabsApiKeyController =
        TextEditingController(text: account?.elevenLabsApiKey ?? '');
    _microsoftGraphTokenController =
        TextEditingController(text: account?.microsoftGraphAccessToken ?? '');
    _additionalPreferencesController =
        TextEditingController(text: account?.additionalPreferences ?? '');
    _gender = account?.gender ?? 'other';
    _fitnessLevel = account?.fitnessLevel ?? 'moderate';
    _voiceGender = account?.voiceGender ?? 'female';
    _meditationType = account?.meditationType ?? 'mindfulness';
    _meditationEnvironment =
        account?.meditationEnvironment ?? 'peaceful nature';
    _speakingSpeed = account?.speakingSpeed ?? 'slow';
    _stressThreshold = account?.stressThreshold ?? 0.10;
    _usePremiumVoice = account?.usePremiumVoice ?? false;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _elevenLabsApiKeyController.dispose();
    _microsoftGraphTokenController.dispose();
    _additionalPreferencesController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish() async {
    // Validate form only if it's in the tree and has state
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      // Go back to basic info page if validation fails
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    // Use default values if fields are empty
    final name = _nameController.text.trim().isEmpty
        ? 'User'
        : _nameController.text.trim();
    final age = int.tryParse(_ageController.text) ?? 30;

    final account = UserAccount(
      userId: widget.existingAccount?.userId ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      age: age,
      gender: _gender,
      fitnessLevel: _fitnessLevel,
      voiceGender: _voiceGender,
      meditationType: _meditationType,
      meditationEnvironment: _meditationEnvironment,
      speakingSpeed: _speakingSpeed,
      additionalPreferences: _additionalPreferencesController.text.trim(),
      stressThreshold: _stressThreshold,
      usePremiumVoice: _usePremiumVoice,
      elevenLabsApiKey: _elevenLabsApiKeyController.text.trim(),
      microsoftGraphAccessToken: _microsoftGraphTokenController.text.trim(),
    );

    await account.save();

    if (mounted) {
      Navigator.pop(context, account);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFD946EF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Progress indicator
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: List.generate(4, (index) {
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: EdgeInsets.only(right: index < 3 ? 8 : 0),
                        decoration: BoxDecoration(
                          color: index <= _currentPage
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Pages
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  children: [
                    _buildWelcomePage(),
                    _buildBasicInfoPage(),
                    _buildHealthInfoPage(),
                    _buildPreferencesPage(),
                  ],
                ),
              ),

              // Navigation buttons
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    if (_currentPage > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _previousPage,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side:
                                const BorderSide(color: Colors.white, width: 2),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Back',
                              style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    if (_currentPage > 0) const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _nextPage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF6366F1),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 8,
                        ),
                        child: Text(
                          _currentPage < 3 ? 'Continue' : 'Get Started',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.self_improvement,
                size: 80, color: Colors.white),
          ),
          const SizedBox(height: 32),
          const Text(
            'Welcome to\nMindful Meditation',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Let\'s personalize your meditation experience based on your unique profile',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tell us about yourself',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            _buildWhiteCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your Name',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Enter your name',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text('Your Age',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Enter your age',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (value) {
                      final age = int.tryParse(value ?? '');
                      if (age == null || age < 13 || age > 120) {
                        return 'Please enter a valid age';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text('Gender',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildOptionButton(
                          label: 'Male',
                          icon: Icons.man,
                          selected: _gender == 'male',
                          onTap: () => setState(() => _gender = 'male'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildOptionButton(
                          label: 'Female',
                          icon: Icons.woman,
                          selected: _gender == 'female',
                          onTap: () => setState(() => _gender = 'female'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildOptionButton(
                          label: 'Other',
                          icon: Icons.person,
                          selected: _gender == 'other',
                          onTap: () => setState(() => _gender = 'other'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Fitness Level',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'This helps us personalize stress detection',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 32),
          _buildWhiteCard(
            child: Column(
              children: [
                _buildFitnessOption(
                  title: 'Sedentary',
                  subtitle: 'Little to no exercise',
                  value: 'sedentary',
                  icon: Icons.weekend,
                ),
                _buildFitnessOption(
                  title: 'Moderate',
                  subtitle: 'Exercise 1-3 times per week',
                  value: 'moderate',
                  icon: Icons.directions_walk,
                ),
                _buildFitnessOption(
                  title: 'Active',
                  subtitle: 'Exercise 4-5 times per week',
                  value: 'active',
                  icon: Icons.directions_run,
                ),
                _buildFitnessOption(
                  title: 'Athlete',
                  subtitle: 'Daily intense training',
                  value: 'athlete',
                  icon: Icons.fitness_center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Meditation Preferences',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 32),
          _buildWhiteCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),

                // Voice Gender
                const Text('Voice Gender',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _voiceGender,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'female',
                      child: Text('👩 Female'),
                    ),
                    DropdownMenuItem(
                      value: 'male',
                      child: Text('👨 Male'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _voiceGender = value!),
                ),
                const SizedBox(height: 24),

                // Speaking Speed
                const Text('Speaking Speed',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _speakingSpeed,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'very_slow',
                      child: Text('🐌 Very Slow'),
                    ),
                    DropdownMenuItem(
                      value: 'slow',
                      child: Text('🐢 Slow (Recommended)'),
                    ),
                    DropdownMenuItem(
                      value: 'medium',
                      child: Text('🚶 Medium'),
                    ),
                    DropdownMenuItem(
                      value: 'fast',
                      child: Text('🏃 Fast'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _speakingSpeed = value!),
                ),
                const SizedBox(height: 24),

                const Text('Meditation Type',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _meditationType,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'mindfulness',
                      child: Text('🧘 Mindfulness'),
                    ),
                    DropdownMenuItem(
                      value: 'breathing',
                      child: Text('🌬️ Breathing'),
                    ),
                    DropdownMenuItem(
                      value: 'body_scan',
                      child: Text('💆 Body Scan'),
                    ),
                    DropdownMenuItem(
                      value: 'visualization_journey',
                      child: Text('🌅 Visualization Journey'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _meditationType = value!),
                ),
                const SizedBox(height: 24),

                const Text('Meditation Environment',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _meditationEnvironment,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'peaceful nature',
                        child: Text('🌳 Peaceful Nature')),
                    DropdownMenuItem(
                        value: 'calm ocean beach',
                        child: Text('🌊 Ocean Beach')),
                    DropdownMenuItem(
                        value: 'quiet mountain', child: Text('⛰️ Mountain')),
                    DropdownMenuItem(
                        value: 'serene forest', child: Text('🌲 Forest')),
                    DropdownMenuItem(
                        value: 'gentle garden', child: Text('🌸 Garden')),
                  ],
                  onChanged: (value) =>
                      setState(() => _meditationEnvironment = value!),
                ),
                const SizedBox(height: 24),

                // Additional Preferences
                const Text('Additional Preferences (Optional)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _additionalPreferencesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'E.g., "I prefer longer pauses" or "Focus on calming imagery"',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Stress Threshold
                const Text('Stress Detection Threshold',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  'How much must your heart rate increase (and HRV decrease) above baseline to be considered stressed?',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<double>(
                  value: _stressThreshold,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 0.05,
                      child: Text('📊 5% (Very Sensitive)'),
                    ),
                    DropdownMenuItem(
                      value: 0.10,
                      child: Text('📊 10% (Recommended)'),
                    ),
                    DropdownMenuItem(
                      value: 0.15,
                      child: Text('📊 15% (Moderate)'),
                    ),
                    DropdownMenuItem(
                      value: 0.20,
                      child: Text('📊 20% (Less Sensitive)'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _stressThreshold = value!),
                ),

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                // Premium Voice Toggle - COMMENTED OUT (ElevenLabs standard voices sufficient)
                /* Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Text(
                                '🎤 Premium Voice',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.auto_awesome,
                                  size: 18, color: Colors.amber),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'High-quality ElevenLabs voice\n(Standard rates apply)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _usePremiumVoice,
                      onChanged: (value) {
                        setState(() => _usePremiumVoice = value);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              value
                                  ? '✨ Premium voice enabled!'
                                  : '✅ Free voice selected',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      activeThumbColor: Colors.amber,
                    ),
                  ],
                ), */
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                ...[
                  const Text(
                    'ElevenLabs Voice Configuration',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'These fields are stored locally and used whenever valid ElevenLabs credentials are available.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCredentialField(
                    label: 'ElevenLabs API Key',
                    controller: _elevenLabsApiKeyController,
                    hintText: 'Enter your ElevenLabs API key',
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Calendar Integration',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Used for Outlook meeting suppression and stored locally on this device.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _buildCredentialField(
                  label: 'Microsoft Graph Access Token',
                  controller: _microsoftGraphTokenController,
                  hintText: 'OAuth access token for Outlook calendar',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiteCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildCredentialField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    bool isSecret = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isSecret,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6366F1) : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.grey[700]),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFitnessOption({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
  }) {
    final selected = _fitnessLevel == value;

    return GestureDetector(
      onTap: () => setState(() => _fitnessLevel = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6366F1).withValues(alpha: 0.1)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF6366F1) : Colors.grey[200]!,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF6366F1) : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  color: selected ? Colors.white : Colors.grey[600], size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color:
                          selected ? const Color(0xFF6366F1) : Colors.grey[800],
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: Color(0xFF6366F1)),
          ],
        ),
      ),
    );
  }
}
