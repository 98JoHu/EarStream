# Meditation App Code Structure Analysis Report

**Generated:** April 14, 2026  
**Location:** `open_wearable/lib/apps/meditation/`

---

## 1. File Inventory

### Model Files (20 files, 3,339 total lines)

| File | Lines | Description | Used By |
|------|-------|-------------|---------|
| `activity_detector.dart` | 174 | Detects physical activity from IMU sensors (earable-specific thresholds) | ✅ `earable_hr_sensor.dart`, `improved_meditation_controller.dart`, `meditation_view.dart` |
| `band_pass_filter_meditation.dart` | 38 | Band-pass filter for PPG signal processing | ✅ `ppg_filter_meditation.dart` |
| `earable_hr_sensor.dart` | 501 | Real HR/HRV sensor implementation using OpenEarable PPG | ✅ `meditation_view.dart` |
| `hrv_calculator.dart` | 121 | Computes HRV metrics (SDNN, RMSSD, pNN50) from RR intervals | ✅ `earable_hr_sensor.dart` |
| `hr_sensor_interface.dart` | 18 | Abstract interface for HR/HRV sensors | ✅ `meditation_view.dart`, `llm_meditation_widget.dart`, `improved_meditation_controller.dart` |
| `improved_meditation_controller.dart` | 737 | Main meditation session controller (state machine, biosignal monitoring) | ✅ `llm_meditation_widget.dart` |
| `improved_meditation_llm_service.dart` | 383 | LLM-powered content generation using Gemini API | ✅ `llm_meditation_widget.dart`, `improved_meditation_controller.dart` |
| `meditation_cache.dart` | 136 | TTS audio caching (premium/free voice separation) | ✅ `meditation_voice_service.dart`, `improved_meditation_controller.dart` |
| `meditation_config.dart` | 98 | Static configuration (API keys from .env, thresholds, defaults) | ✅ Multiple files (config access point) |
| `meditation_history.dart` | 174 | Session history storage and statistics | ✅ `improved_meditation_controller.dart` |
| `meditation_runtime_config.dart` | 101 | Runtime config resolution (in-app vs .env fallback) | ✅ `improved_meditation_llm_service.dart`, `meditation_voice_service.dart` |
| `meditation_voice_service.dart` | 363 | TTS (ElevenLabs premium/Flutter TTS free) | ✅ `llm_meditation_widget.dart`, `improved_meditation_controller.dart` |
| `mock_hr_sensor.dart` | 99 | Mock sensor for testing without hardware | ✅ `meditation_view.dart` |
| `mood_entry.dart` | 129 | Post-session mood tracking and history | ✅ `llm_meditation_widget.dart`, `weekly_analysis_screen.dart` |
| `outlook_meeting_blocker.dart` | 187 | Microsoft Graph integration to suppress prompts during meetings | ✅ `llm_meditation_widget.dart`, `earstream_settings_pages.dart` |
| `personalized_stress_detector.dart` | 286 | Demographics-aware stress detection (age/gender/fitness) | ✅ `improved_meditation_controller.dart` |
| `ppg_filter_meditation.dart` | 140 | PPG signal filtering and HR/RR extraction | ✅ `earable_hr_sensor.dart` |
| `stress_detector.dart` | 67 | **UNUSED** - Basic stress detector (superseded by `personalized_stress_detector.dart`) | ❌ **NOT IMPORTED** |
| `user_account.dart` | 237 | User profile with demographics, API keys, preferences | ✅ Multiple files (central user data) |
| `user_meditation_profile.dart` | 70 | **LEGACY** - Old profile format (superseded by `user_account.dart`) | ⚠️ Only `profile_settings_dialog.dart` |

### View Files (5 files, 2,739 total lines)

| File | Lines | Description | Used By |
|------|-------|-------------|---------|
| `meditation_view.dart` | **1304** 🔴 | **MAIN VIEW** - App entry point, sensor management, mode selection | Main router |
| `earstream_settings_pages.dart` | 934 | Settings UI (personal info, preferences, API keys, Outlook) | ✅ `meditation_view.dart` |
| `success_dialog.dart` | 271 | Post-session success dialog with metrics comparison | ⚠️ Not imported (likely legacy) |
| `snooze_dialog.dart` | 120 | Snooze options dialog (10min, 30min, 1hr, today) | ⚠️ Not imported (likely legacy) |
| `stress_prompt_dialog.dart` | 110 | Stress detection prompt dialog | ⚠️ Not imported (likely legacy) |

### Widget Files (9 files, 2,942 total lines)

| File | Lines | Description | Used By |
|------|-------|-------------|---------|
| `llm_meditation_widget.dart` | **1029** 🔴 | **CORE WIDGET** - Meditation UI, controller integration, stress monitoring | ✅ `meditation_view.dart` |
| `user_onboarding_screen.dart` | 812 | Onboarding flow for new users | ⚠️ Not imported (standalone screen) |
| `hr_hrv_chart.dart` | 655 | Historical HR/HRV chart visualization | ❌ **NOT IMPORTED** |
| `weekly_analysis_screen.dart` | 502 | Weekly meditation analytics and mood trends | ✅ `meditation_view.dart`, `llm_meditation_widget.dart` |
| `hr_hrv_display_new.dart` | 280 | Real-time HR/HRV display card | ✅ `meditation_view.dart` |
| `cute_timer_widget.dart` | 203 | Animated timer widget with dancing elements | ✅ `hr_hrv_chart.dart` |
| `api_debug_widget.dart` | 163 | API debugging interface (logs, errors, stats) | ✅ `meditation_view.dart` |
| `breathing_animation.dart` | 143 | Breathing circle animation (Apple Watch style) | ✅ `llm_meditation_widget.dart` |
| `profile_settings_dialog.dart` | 155 | **LEGACY** - Old profile settings dialog | ❌ **NOT IMPORTED** |

---

## 2. Categorization of Model Files

### **Biosignal Processing (HR, HRV, PPG, Activity)**
- ✅ `activity_detector.dart` - IMU-based activity detection
- ✅ `band_pass_filter_meditation.dart` - Signal filtering
- ✅ `earable_hr_sensor.dart` - Main sensor implementation
- ✅ `hrv_calculator.dart` - HRV metrics computation
- ✅ `hr_sensor_interface.dart` - Sensor abstraction
- ✅ `mock_hr_sensor.dart` - Testing mock
- ✅ `ppg_filter_meditation.dart` - PPG processing
- ✅ `personalized_stress_detector.dart` - Stress detection (uses biosignals)
- ❌ `stress_detector.dart` - **UNUSED** (basic version)

### **Meditation Logic (Controller, LLM Service)**
- ✅ `improved_meditation_controller.dart` - Session state machine
- ✅ `improved_meditation_llm_service.dart` - Gemini content generation
- ✅ `meditation_voice_service.dart` - TTS playback

### **User/Account Management**
- ✅ `user_account.dart` - Main user profile
- ⚠️ `user_meditation_profile.dart` - **LEGACY** (mostly replaced)

### **Configuration**
- ✅ `meditation_config.dart` - Static config (.env loader)
- ✅ `meditation_runtime_config.dart` - Runtime config resolution

### **Data Storage/History**
- ✅ `meditation_cache.dart` - Audio caching
- ✅ `meditation_history.dart` - Session history
- ✅ `mood_entry.dart` - Mood tracking

### **Integrations**
- ✅ `outlook_meeting_blocker.dart` - Microsoft Graph calendar integration

---

## 3. Dependency Graph

### Key Import Relationships

```
meditation_view.dart (ENTRY POINT)
├── model/
│   ├── mock_hr_sensor.dart
│   ├── earable_hr_sensor.dart
│   │   ├── ppg_filter_meditation.dart
│   │   │   └── band_pass_filter_meditation.dart
│   │   ├── hrv_calculator.dart
│   │   └── activity_detector.dart
│   ├── hr_sensor_interface.dart
│   ├── activity_detector.dart
│   └── user_account.dart
├── widgets/
│   ├── hr_hrv_display_new.dart
│   ├── llm_meditation_widget.dart ⭐
│   │   ├── model/improved_meditation_controller.dart
│   │   │   ├── improved_meditation_llm_service.dart
│   │   │   │   ├── meditation_config.dart
│   │   │   │   ├── meditation_runtime_config.dart
│   │   │   │   │   └── meditation_config.dart
│   │   │   │   └── user_account.dart
│   │   │   ├── meditation_voice_service.dart
│   │   │   │   ├── meditation_cache.dart
│   │   │   │   ├── meditation_config.dart
│   │   │   │   └── meditation_runtime_config.dart
│   │   │   ├── personalized_stress_detector.dart
│   │   │   │   ├── user_account.dart
│   │   │   │   └── activity_detector.dart
│   │   │   ├── meditation_history.dart
│   │   │   ├── meditation_cache.dart
│   │   │   └── activity_detector.dart
│   │   ├── model/outlook_meeting_blocker.dart
│   │   ├── model/mood_entry.dart
│   │   └── widgets/breathing_animation.dart
│   ├── api_debug_widget.dart
│   └── weekly_analysis_screen.dart
│       └── model/mood_entry.dart
└── view/
    └── earstream_settings_pages.dart
        ├── model/meditation_config.dart
        ├── model/outlook_meeting_blocker.dart
        └── model/user_account.dart
```

---

## 4. meditation_view.dart Analysis

**Size:** 1,304 lines 🔴 **VERY LARGE**

### Main Responsibilities (Too Many!)

1. **Sensor Management** (~200 lines)
   - Initialize mock/real sensors
   - Switch between sensor types
   - Monitor connection state
   - Subscribe to HR/HRV streams

2. **Mode Selection & Timer Management** (~150 lines)
   - Handle 3 meditation modes (normal/timer/test)
   - Schedule timed sessions
   - Timer countdown logic

3. **UI State Management** (~200 lines)
   - Track HR/HRV values
   - Monitor stress levels
   - Handle activity detection
   - Manage HRV stability tracking

4. **UI Rendering** (~600 lines)
   - Main scaffold and layout
   - Mode selection cards
   - Timer configuration UI
   - Settings navigation
   - Debug controls

5. **Lifecycle & Cleanup** (~100 lines)
   - Initialize/dispose subscriptions
   - Handle widget lifecycle
   - Reset sessions

### Recommended Extraction

**Current Structure:**
```
meditation_view.dart (1304 lines)
├── All sensor logic
├── All mode/timer logic
├── All state management
└── All UI rendering
```

**Suggested Refactoring:**
```
meditation_view.dart (400 lines) - Main coordinator
├── view_models/
│   ├── meditation_sensor_manager.dart (250 lines)
│   │   └── Sensor initialization, switching, monitoring
│   ├── meditation_timer_manager.dart (150 lines)
│   │   └── Timer/scheduling logic
│   └── meditation_state_provider.dart (200 lines)
│       └── State management (ChangeNotifier)
└── widgets/
    ├── mode_selector_card.dart (100 lines)
    ├── timer_config_card.dart (150 lines)
    └── sensor_controls_card.dart (100 lines)
```

**Benefits:**
- Single Responsibility Principle
- Easier testing
- Better code reusability
- Clearer separation of concerns

---

## 5. Unused Files & Duplications

### ❌ Completely Unused Files

1. **`model/stress_detector.dart`** (67 lines)
   - **Reason:** Superseded by `personalized_stress_detector.dart`
   - **Action:** DELETE (functionality fully replaced)

2. **`widgets/hr_hrv_chart.dart`** (655 lines) 🚨
   - **Reason:** Not imported anywhere
   - **Action:** INVESTIGATE - Contains historical chart logic that might be valuable
   - **Note:** Imports `cute_timer_widget.dart` which is ONLY used here

3. **`widgets/profile_settings_dialog.dart`** (155 lines)
   - **Reason:** Legacy UI using old `user_meditation_profile.dart`
   - **Action:** DELETE (replaced by `earstream_settings_pages.dart`)

### ⚠️ Legacy/Partially Unused Files

4. **`model/user_meditation_profile.dart`** (70 lines)
   - **Status:** Only used by `profile_settings_dialog.dart` (which is unused)
   - **Action:** DELETE after confirming no external dependencies

5. **`view/success_dialog.dart`** (271 lines)
   - **Status:** Not imported (likely replaced by inline dialogs)
   - **Action:** INVESTIGATE - May be called dynamically via Navigator

6. **`view/snooze_dialog.dart`** (120 lines)
   - **Status:** Not imported
   - **Action:** INVESTIGATE if used for timed mode

7. **`view/stress_prompt_dialog.dart`** (110 lines)
   - **Status:** Not imported
   - **Action:** INVESTIGATE - Might be used in timer mode

### Duplicated Functionality

**PPG Filtering:**
- `band_pass_filter_meditation.dart` is a **copy** of Heart Tracker's filter
- `ppg_filter_meditation.dart` is a **copy** of Heart Tracker's filter
- **Reason:** "Separated to avoid dependencies on other apps"
- **Impact:** Code duplication but intentional isolation

---

## 6. Import Analysis & Dead Code

### Files with No Imports (Self-Contained)

✅ Good for modularity:
- `activity_detector.dart` - Only math & logger
- `band_pass_filter_meditation.dart` - Pure math
- `hrv_calculator.dart` - Pure computation
- `hr_sensor_interface.dart` - Interface only
- `stress_detector.dart` - **BUT UNUSED**
- `breathing_animation.dart` - Pure Flutter
- `cute_timer_widget.dart` - Pure Flutter

### Unused Imports (Potential)

To verify unused imports, run:
```bash
dart fix --dry-run
```

Common suspects:
- `view/success_dialog.dart` - Likely has unnecessary imports if unused
- `widgets/profile_settings_dialog.dart` - Imports `user_meditation_profile.dart`

---

## 7. Recommendations

### High Priority 🔴

1. **Refactor `meditation_view.dart` (1304 lines)**
   - Extract sensor management → `MeditationSensorManager`
   - Extract timer logic → `MeditationTimerManager`
   - Extract state → `MeditationStateProvider` (ChangeNotifier)
   - Extract UI cards → Separate widget files

2. **Delete Dead Code**
   ```
   ❌ DELETE: model/stress_detector.dart
   ❌ DELETE: widgets/profile_settings_dialog.dart
   ❌ DELETE: model/user_meditation_profile.dart
   ```

3. **Investigate & Delete/Document**
   ```
   ⚠️ INVESTIGATE: widgets/hr_hrv_chart.dart (655 lines!)
   ⚠️ INVESTIGATE: view/success_dialog.dart
   ⚠️ INVESTIGATE: view/snooze_dialog.dart
   ⚠️ INVESTIGATE: view/stress_prompt_dialog.dart
   ```

### Medium Priority 🟡

4. **Reduce `llm_meditation_widget.dart` (1029 lines)**
   - Extract mood tracking logic
   - Extract Outlook meeting logic
   - Split UI from controller interaction

5. **Consolidate Config**
   - `meditation_config.dart` + `meditation_runtime_config.dart` overlap
   - Consider merging or clearer separation

### Low Priority 🟢

6. **Document Intentional Duplications**
   - Add comments in `band_pass_filter_meditation.dart` explaining why it's copied
   - Consider shared package in future for filters

7. **Add Tests**
   - All model files are testable (minimal dependencies)
   - Priority: `hrv_calculator.dart`, `activity_detector.dart`, `personalized_stress_detector.dart`

---

## 8. Summary Statistics

| Category | Count | Total Lines | Avg Lines/File |
|----------|-------|-------------|----------------|
| **Model Files** | 20 | 3,339 | 167 |
| **View Files** | 5 | 2,739 | 548 🔴 |
| **Widget Files** | 9 | 2,942 | 327 |
| **TOTAL** | 34 | 9,020 | 265 |

### Code Health Metrics

- 🔴 **2 files over 1000 lines** (`meditation_view.dart`, `llm_meditation_widget.dart`)
- ⚠️ **3-7 potentially unused files** (need investigation)
- ❌ **1 confirmed duplicate** (`stress_detector.dart` vs `personalized_stress_detector.dart`)
- ✅ **Good modularity** in model layer (small, focused files)
- ✅ **Clear separation** of biosignal processing from meditation logic

---

## 9. Next Steps

### Immediate Actions

1. Run `dart fix` to identify unused imports
2. Search codebase for dynamic imports (Navigator.push to dialogs)
3. Confirm `hr_hrv_chart.dart` is truly unused (grep for class name)
4. Delete confirmed dead code (`stress_detector.dart`, etc.)

### Refactoring Roadmap

**Phase 1: Delete Dead Code** (1-2 hours)
- Remove confirmed unused files
- Update imports
- Run tests

**Phase 2: Extract View Logic** (4-6 hours)
- Create `MeditationSensorManager`
- Create `MeditationTimerManager`
- Create `MeditationStateProvider`
- Refactor `meditation_view.dart`

**Phase 3: Widget Extraction** (2-3 hours)
- Extract mode selector
- Extract timer config UI
- Extract sensor controls

**Phase 4: Testing** (4-8 hours)
- Unit tests for managers
- Widget tests for extracted widgets
- Integration tests for full flow

---

**Report End**
