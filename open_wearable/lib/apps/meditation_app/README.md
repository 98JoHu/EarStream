# EarStreAM Meditation In-App

EarStreAM is the meditation in-app integrated into `open_wearable`. It combines
OpenEarable PPG and motion streams with local HR/RMSSD processing, stress
detection, DeepSeek-generated guidance, and either ElevenLabs or Tencent Cloud
text-to-speech (TTS).

This document describes the implementation in this directory. It intentionally
does not describe the older `lib/apps/meditation` prototype.

## Current feature set

- Three top-level modes: **Biosignal-Adaptive**, **Timed**, and **Demo**.
- Two conference-demo experiences: a condensed biosignal-adaptive cycle and a
  personalized meditation without biosignal adaptation.
- Local PPG-derived heart-rate and RMSSD processing.
- Accelerometer/gyroscope activity classification and movement-aware stress
  suppression.
- Physiological-only baseline measurement in both biosignal-adaptive modes.
- Stress onset based jointly on elevated HR and reduced RMSSD.
- Meditation recovery based only on HR returning to baseline or below.
- DeepSeek segment generation with a static local-script fallback.
- ElevenLabs, Tencent Cloud, or on-device Flutter TTS playback.
- Local weekly analytics for regular biosignal-adaptive and timed sessions.
- Demo isolation from the permanent profile and from analytics.

## Integration into `open_wearable`

The app is registered as **EarStreAM** in
`lib/apps/widgets/apps_page.dart`. It currently supports devices whose name
starts with `OpenEarable`.

At launch, the integration searches the selected wearable's sensor list for:

- a PPG/pulse/photoplethysmography sensor;
- an accelerometer; and
- a gyroscope.

Those sensors and the shared `SensorConfigurationProvider` are passed to
`MeditationView`. If the sensor manager or any required sensor is unavailable,
the launcher now shows a specific compatibility message instead of attempting
to start with a null sensor.

`lib/main.dart` optionally loads
`lib/apps/meditation_app/assets/.env` before the Flutter application starts.

## Modes at a glance

| Mode | Biosignals | Guidance segments | Segment target | Analytics |
| --- | --- | ---: | --- | --- |
| Regular biosignal-adaptive | PPG + accelerometer + gyroscope | Up to 10 | About 280 words; narration-driven | Yes |
| Timed | None | 3 | About 280 words; narration-driven | Yes |
| Demo: biosignal-adaptive | PPG + accelerometer + gyroscope | Exactly 1 | About 30 seconds | No |
| Demo: personalized only | None | 3 | About 30 seconds each | No |

Welcome and completion messages are separate from the generated-segment counts.
TTS is never cut off merely because a nominal segment duration has elapsed.

## Regular biosignal-adaptive mode

The regular path uses `BioAdaptiveSessionConfig.standard` and the following
phases.

### 1. Calibration

- Duration: 30 seconds.
- Purpose: warm the signal-conditioning filters and remove their transient
  response.
- No HR or RMSSD is published or displayed.
- Calibration samples do not enter peak detection or RR-interval history.

### 2. Baseline

- Duration: at least 5 minutes.
- Computation: physiological data only; profile-derived values are not blended
  into the measured baseline.
- The phase advances only after at least one valid HR and one valid RMSSD value
  have been measured. If either is unavailable at the five-minute point, the
  phase waits for valid sensor-derived data.
- Production processor defaults:
  - HR rolling buffer: 10 seconds;
  - metric eligibility: 4 seconds;
  - minimum RMSSD history: 60 seconds;
  - maximum RMSSD history: 5 minutes;
  - metric emission interval: 3 seconds.

### 3. Monitoring and stress detection

The stored sensitivity is 10% by default and can be selected as 5%, 10%, 15%,
or 20% under **Meditation Preferences**.

For sensitivity `s`, the thresholds are:

```text
HR threshold    = baseline HR * (1 + s)
RMSSD threshold = baseline RMSSD * (1 - s)
```

Stress begins only when both conditions hold:

```text
current HR > HR threshold
current RMSSD < RMSSD threshold
```

A missing RMSSD value cannot trigger stress. In the regular mode, physical
activity can suppress a new stress classification, as described under
Activity handling below.

### 4. Adaptive meditation and recovery

- A detected stressed state starts a `BiometricMeditation`.
- The maximum is 10 generated segments.
- Each regular segment requests approximately 280 words from DeepSeek.
- Regular segments are narration-driven; no 30-second target is applied.
- After each spoken segment, the current HR/RMSSD sample may be sent to
  DeepSeek so the next segment can adapt.
- After each segment, the app checks whether measured HR is at or below the
  baseline HR. If so, it proceeds to the completion message.
- RMSSD is deliberately not part of the recovery/termination condition.
- The current segment finishes before recovery ends the meditation, avoiding
  an abrupt narration cut-off.

### Recorded stress control

The regular mode exposes a **Play Recorded Stress** control for development
and demonstration. It uses `RecordedStressBiometricSource`, not randomly
generated sensor values and not the live sensor stream.

The recording-derived trajectory is configured as:

- baseline: 71 BPM / 80 ms RMSSD;
- build-up target: 80 BPM / 50 ms RMSSD;
- peak: 97 BPM / 12 ms RMSSD;
- build-up ends at 90 seconds;
- stress spike ends at 120 seconds;
- detector thresholds: 90 BPM / 40 ms RMSSD.

When the scripted stress triggers a meditation, the source begins a gradual
six-minute recovery toward 62 BPM / 90 ms RMSSD. This control is not available
in demo mode.

## Demo mode

Demo mode creates a fresh attendee-scoped `UserAccount` whenever a demo starts
or finishes. It copies only cloud-service configuration and the voice choice
from the main account. Permanent profile fields, stored baselines, stress
sensitivity, and personal meditation preferences are not copied.

Attendees can choose meditation type, environment, and speaking speed for the
current demo. Provider, region, and voice selection are configured only on the
**API Keys** page.

The demo prompt policy excludes both permanent profile information and
physiological measurements. HR/RMSSD processing remains local to the phone.

### Biosignal-adaptive demo

This is the condensed version of the regular biosignal pipeline; it uses the
same `Measurement`, `HrHrvProcessor`, `StressDetector`, and meditation classes
with `BioAdaptiveSessionConfig.conferenceDemo`.

- Optional seal-check step before sensing.
- 30-second filter calibration with no displayed metrics.
- 30-second physiological baseline.
- HR and RMSSD both use 30-second metric/history windows in this mode.
- The baseline deadline can use the best physiologically plausible,
  beat-derived estimate from retained conditioned data. It does not substitute
  fixed synthetic HR/RMSSD values.
- Stress sensitivity: 3%.
- No simulated/recorded stress control.
- A meditation starts when stress is detected or, if no intervention has
  started, after two minutes in the monitoring phase.
- Meditation structure: welcome message, exactly one generated 30-second
  segment, completion message.
- The one-segment cap applies regardless of the participant's stress level.

### Personalized-meditation-only demo

- Does not start the biosignal pipeline.
- Uses only attendee-selected meditation type, environment, and speaking speed.
- Meditation structure: welcome message, three generated segments targeting
  about 30 seconds each, completion message.
- Uses the same privacy-restricted prompt policy as the adaptive demo.

Neither demo submode writes weekly analytics.

## Timed mode

Timed mode supports:

- Start Now;
- start after 5, 10, or 30 minutes; and
- start at a selected clock time (the next day if today's time has passed).

Scheduled meditations are held in memory and checked once per second. They are
not operating-system alarms and do not persist across app restarts. A late
poll still starts an overdue session, and only one timed meditation runs at a
time.

Each timed meditation contains three generated segments. Like the regular
biosignal-adaptive mode, each segment requests approximately 280 words and is
narration-driven rather than fixed to 30 seconds. Timed sessions use profile
and meditation preferences but do not provide live biosignals to the generator.

## Biosignal processing

The processing path is:

```text
OpenEarable PPG
  -> channel selection and signal conditioning
  -> ambient/motion suppression
  -> pulse peak and RR-interval extraction
  -> HR and RMSSD estimation
  -> baseline / monitoring phases
  -> activity-aware stress detector
```

Requested stream rates are 200 Hz for PPG and 100 Hz for accelerometer and
gyroscope. When sensor metadata is unavailable, the configured fallbacks are
100 Hz for all three streams.

The low-level filters, quality scoring, artifact rejection, adaptive channel
selection, and estimator coefficients live next to the implementation in
`model/hr_hrv_processor.dart`. They are intentionally not duplicated in the
high-level configuration files.

## Activity handling

`ActivityTracker` classifies resting, light, moderate, vigorous, and intense
activity from three-second accelerometer and gyroscope windows. It retains five
minutes of classification history.

New stress detection is suppressed when the retained history contains at least:

- 40% light-or-higher activity;
- 20% moderate-or-higher activity;
- 5% vigorous-or-higher activity; or
- 2% intense activity.

These percentages suppress new stress detection only in the regular
biosignal-adaptive mode. The demo uses the same live classification and shows
the same activity levels in the UI, but its mode configuration explicitly
disables activity-based intervention suppression. Consequently, neither a
physiological stress trigger nor the demo's guaranteed two-minute trigger can
be blocked by activity. Once stress has already been detected in the regular
mode, recovery tracking is likewise not blocked by activity and remains
HR-only.

## Meditation generation

`AdaptiveMeditationScript` uses:

- API base: `https://api.deepseek.com`;
- endpoint: `/chat/completions`;
- model: `deepseek-v4-pro`;
- temperature: `0.7`;
- maximum response tokens: `2000`;
- request timeout: 30 seconds.

Standard-mode prompts include profile and meditation context. Biosignal-adaptive
standard sessions additionally include the latest HR/RMSSD after a segment.
Timed sessions report that no biosignals are available.

Demo prompts contain only the attendee's session meditation type and imagery
environment. They explicitly prohibit names, age, gender, fitness information,
health inferences, permanent profile data, and physiological measurements.

If the opening generation fails, the whole session switches to the static
local script. If generation of a later adaptive segment fails, that segment is
replaced with the static fallback text and the remaining session can continue.

## Text-to-speech and audio

The TTS provider and voice are selected on the **API Keys** page. They are not
available in Profile, Meditation Preferences, or demo attendee preferences.

### ElevenLabs

- Model: `eleven_flash_v2_5`.
- Coded male default: `CwhRBWXzGAHq8TQ4Fs17`.
- Coded female default: `hpp4J3VqNfWAUOO0d1Us`.
- After credential verification, a fetched ElevenLabs voice can be selected
  explicitly; it overrides the coded gender default.
- Request timeout: 20 seconds.

### Tencent Cloud

- Premium male voice type: `101050`.
- Premium female voice type: `101051`.
- English primary language, model type 1, 16 kHz MP3.
- Long input is split conservatively before `TextToVoice` requests.
- Request timeout: 25 seconds.

Supported endpoint choices:

| Selection | Region | Host |
| --- | --- | --- |
| International | `ap-singapore` | `tts.intl.tencentcloudapi.com` |
| Mainland China | `ap-guangzhou` | `tts.tencentcloudapi.com` |

International and Mainland China service activation/credentials are not
assumed to be interchangeable.

### Provider consistency and device fallback

The TTS route is selected once when a meditation object is created.

- If the selected cloud provider is not marked valid at session start, the
  whole meditation uses on-device Flutter TTS.
- If a selected cloud provider is initially available but later fails, the app
  retries it three times (immediately, after one second, and after two seconds).
- After those failures, the meditation stops and shows a voice-service failure
  card. It does not switch voices in the middle of a meditation.

Background ambience loops at volume `0.3`. Cloud narration requests transient
audio ducking so the ambience is lowered rather than stopped during speech.

## Environment configuration

The bundled environment asset is:

```text
lib/apps/meditation_app/assets/.env
```

Supported entries are:

```dotenv
DEEPSEEK_API_KEY=
ELEVENLABS_API_KEY=
TTS_PROVIDER=elevenlabs
TENCENT_SECRET_ID=
TENCENT_SECRET_KEY=
TENCENT_TTS_REGION=ap-singapore
```

`TENCENT_TTS_API_KEY` remains accepted as a legacy alias for
`TENCENT_SECRET_KEY`.

At startup, non-empty credentials loaded from this asset are marked usable so
the controlled demo can start without a separate verification step. Editing a
credential, Tencent region, or Tencent voice in the API Keys page marks the
affected service unverified until its live service check succeeds.

For a Mainland China Tencent setup, use:

```dotenv
TTS_PROVIDER=tencent
TENCENT_TTS_REGION=ap-guangzhou
TENCENT_SECRET_ID=<mainland-account-secret-id>
TENCENT_SECRET_KEY=<mainland-account-secret-key>
```

The DeepSeek base URL is unchanged between the international and China
configuration. Network reachability and service/account availability still
need to be tested at the deployment location.

The `.env` file is bundled as a Flutter asset. It is suitable for controlled
demos but must not be treated as a secure production secret store because
packaged application assets can be extracted. Values edited on the API Keys
page affect the current in-memory app session; this in-app implementation does
not persist those edited credentials itself.

## Navigation and user settings

The in-app drawer contains:

- **Meditation Mode**: mode selection and current session;
- **Profile**: name, age, gender, and fitness level;
- **Meditation Preferences**: speaking speed, meditation type, environment,
  additional text preference, and regular stress sensitivity;
- **Weekly Analytics**;
- **Seal Check**; and
- **API Keys**: provider, voice, Tencent region, credentials, and live service
  checks.

Voice/provider settings exist only on API Keys. Speaking speed remains a
meditation-delivery preference.

## Completion and analytics

Completed sessions show a success card and the single-line mood choices
**Serene**, **Relaxed**, **Neutral**, and **Stressed**. Selecting a mood
currently dismisses the completed session; mood values are not persisted.

Weekly analytics stores regular biosignal-adaptive and timed session records in
`SharedPreferences`. Each record contains mode, start time, end time, and
completion state. The dashboard derives total duration, completion rate,
active days, daily activity, mode breakdown, and recent sessions.

- Weeks begin on Monday.
- Records are retained for 366 days.
- Demo sessions are excluded from both demo submodes.
- Storage errors and malformed stored data are treated as an empty history and
  never prevent a meditation from running.

## Configuration sources of truth

High-level parameters are centralized in `configs/`:

| File | Responsibility |
| --- | --- |
| `overall_config.dart` | Shared generation, TTS, playback, environment, sensitivity, and analytics values |
| `timed_mode_config.dart` | Timed segment count and scheduling intervals |
| `bio_adaptive_mode_config.dart` | Regular phases, processing windows, sensors, activity thresholds, recorded stress, and HR recovery |
| `demo_mode_config.dart` | Condensed demo timing, segment counts, privacy, guaranteed trigger, and China deployment values |

`model/bio_adaptive_session_config.dart` maps the regular and conference-demo
configuration into the same measurement/session pipeline.

## Directory structure

```text
meditation_app/
|-- README.md
|-- assets/
|   |-- .env
|   |-- earstream_logo.png
|   |-- ubicomp_logo.png
|   `-- audio/
|-- configs/
|   |-- overall_config.dart
|   |-- timed_mode_config.dart
|   |-- bio_adaptive_mode_config.dart
|   `-- demo_mode_config.dart
|-- model/
|   |-- activity_tracker.dart
|   |-- bio_adaptive_session_config.dart
|   |-- biometric_source.dart
|   |-- hr_hrv_processor.dart
|   |-- measurement.dart
|   |-- measurement_phase.dart
|   |-- meditation.dart
|   |-- meditation_analytics.dart
|   |-- meditation_prompt_policy.dart
|   |-- meditation_session_generator.dart
|   |-- monitoring_meditation_deadline.dart
|   |-- stress_detector.dart
|   |-- tencent_tts_client.dart
|   `-- user_account.dart
|-- views/
|   |-- meditation_modes/
|   |   |-- bio_adaptive_view.dart
|   |   |-- demo_view.dart
|   |   `-- timer_view.dart
|   |-- pages/
|   `-- meditation_view.dart
`-- widgets/
```

## Running and testing

From `open_wearable/`:

```powershell
flutter pub get
flutter analyze
flutter test test/apps/meditation_app/hr_hrv_processor_test.dart
flutter run
```

The focused test suite covers configuration alignment, calibration isolation,
demo deadline estimates, provider/region parsing, voice selection, demo privacy,
stress playback, HR-only recovery, one-segment demo behavior, presentation,
weekly analytics, and Tencent signing/chunking.

## Current limitations

- HR/RMSSD accuracy depends on earbud fit, motion, PPG signal quality, and the
  device-specific sensor stream.
- Stress inference is a threshold-based research prototype and is not a
  medical diagnosis.
- Regular baseline measurement intentionally waits beyond five minutes when no
  valid HR/RMSSD pair is available.
- The demo's deadline estimate is always derived from measured waveform/beat
  evidence, but a poor signal can still produce an unreliable estimate.
- LLM and cloud TTS require network access. Static meditation generation and
  on-device TTS reduce, but do not remove, all online-service limitations.
- A cloud TTS outage after a cloud-routed session begins stops that session
  rather than changing voice mid-session.
- Scheduled timed sessions are in-memory only and require the app process to
  remain active.
- Meditation execution is not implemented as an Android background service;
  operating-system suspension or loss of connectivity can interrupt cloud
  requests.
- Mood choices are UI-only and are not included in analytics.

---

Last reviewed against the implementation: September 19, 2026.
