import 'package:flutter/material.dart';
import '../model/user_meditation_profile.dart';

class ProfileSettingsDialog extends StatefulWidget {
  final UserMeditationProfile profile;
  
  const ProfileSettingsDialog({
    super.key,
    required this.profile,
  });
  
  @override
  State<ProfileSettingsDialog> createState() => _ProfileSettingsDialogState();
}

class _ProfileSettingsDialogState extends State<ProfileSettingsDialog> {
  late TextEditingController _nameController;
  late String _voiceGender;
  late String _meditationStyle;
  late String _environment;
  late TextEditingController _activityController;
  
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.userName);
    _voiceGender = widget.profile.voiceGender;
    _meditationStyle = widget.profile.meditationStyle;
    _environment = widget.profile.preferredEnvironment;
    _activityController = TextEditingController(text: widget.profile.favoriteActivity);
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _activityController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Meditation Profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Your Name (optional)',
                hintText: 'The AI will use your name',
              ),
            ),
            const SizedBox(height: 16),
            
            const Text('Voice Gender:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Female'),
                    value: 'female',
                    groupValue: _voiceGender,
                    onChanged: (value) => setState(() => _voiceGender = value!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Male'),
                    value: 'male',
                    groupValue: _voiceGender,
                    onChanged: (value) => setState(() => _voiceGender = value!),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            const Text('Meditation Style:', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: _meditationStyle,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'calm and empathetic', child: Text('Calm & Empathetic')),
                DropdownMenuItem(value: 'gentle and soothing', child: Text('Gentle & Soothing')),
                DropdownMenuItem(value: 'warm and compassionate', child: Text('Warm & Compassionate')),
                DropdownMenuItem(value: 'peaceful and mindful', child: Text('Peaceful & Mindful')),
              ],
              onChanged: (value) => setState(() => _meditationStyle = value!),
            ),
            
            const SizedBox(height: 16),
            const Text('Preferred Environment:', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: _environment,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'peaceful nature', child: Text('🌳 Peaceful Nature')),
                DropdownMenuItem(value: 'calm ocean beach', child: Text('🌊 Ocean Beach')),
                DropdownMenuItem(value: 'quiet mountain', child: Text('⛰️ Mountain')),
                DropdownMenuItem(value: 'serene forest', child: Text('🌲 Forest')),
                DropdownMenuItem(value: 'gentle garden', child: Text('🌸 Garden')),
              ],
              onChanged: (value) => setState(() => _environment = value!),
            ),
            
            const SizedBox(height: 16),
            TextField(
              controller: _activityController,
              decoration: const InputDecoration(
                labelText: 'Favorite Relaxing Activity (optional)',
                hintText: 'e.g., walking, reading, yoga',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            widget.profile.userName = _nameController.text.trim();
            widget.profile.voiceGender = _voiceGender;
            widget.profile.meditationStyle = _meditationStyle;
            widget.profile.preferredEnvironment = _environment;
            widget.profile.favoriteActivity = _activityController.text.trim();
            
            await widget.profile.save();
            
            if (context.mounted) {
              Navigator.pop(context, true); // Return true to indicate profile was saved
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
