# EarStreAM Meditation App - Refactoring Plan

## Current Issues
- meditation_view.dart is 1,304 lines (too large)
- 7 unused files (1,386 lines of dead code)
- No clear folder organization
- .env in wrong location
- Assets not organized

## New Structure

```
meditation/
├── config/
│   ├── .env                          # Moved from root
│   ├── meditation_config.dart        # API keys & configuration
│   └── meditation_runtime_config.dart # Runtime configuration resolution
│
├── core/
│   ├── biosignals/
│   │   ├── activity_detector.dart
│   │   ├── band_pass_filter_meditation.dart
│   │   ├── ppg_filter_meditation.dart
│   │   ├── hrv_calculator.dart
│   │   └── sensors/
│   │       ├── hr_sensor_interface.dart
│   │       ├── earable_hr_sensor.dart
│   │       └── mock_hr_sensor.dart
│   │
│   ├── meditation/
│   │   ├── improved_meditation_controller.dart
│   │   ├── improved_meditation_llm_service.dart
│   │   ├── meditation_voice_service.dart
│   │   ├── personalized_stress_detector.dart
│   │   └── outlook_meeting_blocker.dart
│   │
│   └── storage/
│       ├── meditation_cache.dart
│       ├── meditation_history.dart
│       └── mood_entry.dart
│
├── models/
│   └── user_account.dart
│
├── ui/
│   ├── screens/
│   │   ├── meditation_screen.dart     # Main screen (refactored from meditation_view.dart)
│   │   ├── weekly_analysis_screen.dart
│   │   └── settings/
│   │       ├── earstream_settings_pages.dart
│   │       └── user_onboarding_screen.dart
│   │
│   ├── components/
│   │   ├── biosignal_display/
│   │   │   └── hr_hrv_display_new.dart
│   │   ├── meditation_session/
│   │   │   ├── llm_meditation_widget.dart
│   │   │   ├── breathing_animation.dart
│   │   │   └── cute_timer_widget.dart
│   │   └── debug/
│   │       └── api_debug_widget.dart
│   │
│   └── shared/
│       └── earstream_style.dart
│
├── assets/
│   ├── audio/
│   │   ├── backgrounds/        # Ambient sounds
│   │   │   ├── Forest.wav
│   │   │   ├── Garden.mp3
│   │   │   ├── Mountain.wav
│   │   │   ├── Ocean_Beach.wav
│   │   │   └── Peaceful_Nature.wav
│   │   └── meditation_sound.mp3
│   └── images/
│       └── image.png
│
├── CODE_QUALITY_REPORT.md
└── README.md
```

## Files to DELETE (unused)
1. model/stress_detector.dart (superseded)
2. model/user_meditation_profile.dart (legacy)
3. view/success_dialog.dart (not used)
4. view/snooze_dialog.dart (not used)  
5. view/stress_prompt_dialog.dart (not used)
6. widgets/hr_hrv_chart.dart (655 lines, not imported)
7. widgets/profile_settings_dialog.dart (replaced)

## Import Updates Required
After moving files, all imports must be updated:
- model/ → core/biosignals/, core/meditation/, core/storage/, models/
- view/ → ui/screens/
- widgets/ → ui/components/
- earstream_style.dart → ui/shared/

## Execution Steps
1. Create new folder structure
2. Move .env from root to meditation/config/
3. Move model files to appropriate subfolders
4. Reorganize assets
5. Move view files to ui/screens
6. Move widgets to ui/components
7. Delete unused files
8. Update all imports
9. Test compilation
