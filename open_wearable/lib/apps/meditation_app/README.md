# EarStreAM Meditation In-App

EarStreAM is the meditation in-app integrated into `open_wearable`. It combines
OpenEarable PPG and motion streams with local HR/RMSSD processing, stress
detection, DeepSeek-generated guidance, and ElevenLabs, Tencent Cloud, or local
Kokoro-82M text-to-speech (TTS).

This document describes the implementation in this directory. It intentionally
does not describe the older `lib/apps/meditation` prototype.

## Current feature set

- Three top-level modes: **Biosignal-Adaptive**, **Timed**, and **Demo**.
- Two conference-demo experiences: a condensed biosignal-adaptive cycle and a
  personalized meditation without biosignal adaptation.
- Local PPG-derived heart-rate and RMSSD processing.
- Accelerometer/gyroscope activity classification and movement-aware stress
  suppression. The angular-rate unit is read from `Sensor.axisUnits` rather
  than assumed, since the thresholds are in degrees/s.
- Physiological-only baseline measurement in both biosignal-adaptive modes.
- Stress onset based jointly on elevated HR and reduced RMSSD.
- Meditation recovery based only on HR returning to baseline or below.
- DeepSeek segment generation with a static local-script fallback.
- ElevenLabs, Tencent Cloud, local Kokoro-82M, or on-device Flutter TTS.
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
| Demo: biosignal-adaptive | PPG + accelerometer + gyroscope | Up to 3 | About 30 seconds each | No |
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
- Computation: the running mean of measured HR and RMSSD, blended with the
  profile's population-level estimate while too little has been measured for
  the measurement to stand alone. Nothing is published during the first
  minute; from there the prior's share falls linearly from 70% at one minute
  to 30% at five. It applies only when the profile carries age, gender **and**
  fitness level together - a missing field would leave a generic population
  default standing in for it - and only in this mode. The conference demo
  keeps a sensor-only baseline.
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
- The next segment is requested while the current one is still speaking, so the
  HR/RMSSD sample it carries is the one read when the current segment *starts*,
  not when it ends. See Narration pipeline below.
- After each segment, the app checks whether measured HR is at or below the
  baseline HR. If so, it proceeds to the completion message.
- RMSSD is deliberately not part of the recovery/termination condition.
- The current segment finishes before recovery ends the meditation, avoiding
  an abrupt narration cut-off.

### Recorded stress control

The regular mode exposes a **Simulate Stress** control for development
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

Both demo experiences are two steps: attendee preferences, then the
meditation. Rating the finished session on the mood card ends the demo and
returns to the mode picker with a fresh attendee account - there is only one
pass through it. **End Demo** remains available throughout as a way out
mid-session, and dismissing a *failed* session deliberately does not end the
run, so the operator can see what happened. The seal check is reachable from the drawer whenever it is needed,
but it is deliberately not part of the demo flow, which is kept as short as an
attendee can walk through unaided.

Demo mode creates a fresh attendee-scoped `UserAccount` whenever a demo starts
or finishes. It copies only cloud-service configuration and the voice choice
from the main account. Permanent profile fields, stored baselines, stress
sensitivity, and personal meditation preferences are not copied.

Attendees can choose voice gender, meditation type, environment, and speaking
speed for the current demo; "Surprise me" randomises all four. Provider, region
and credentials are configured only on the **API Keys** page.

The demo prompt policy excludes both permanent profile information and
physiological measurements. HR/RMSSD processing remains local to the phone.

### Biosignal-adaptive demo

This is the condensed version of the regular biosignal pipeline; it uses the
same `Measurement`, `HrHrvProcessor`, `StressDetector`, and meditation classes
with `BioAdaptiveSessionConfig.conferenceDemo`.

- 30-second filter calibration with no displayed metrics.
- 30-second physiological baseline.
- HR and RMSSD both use 30-second metric/history windows in this mode.
- The first live estimates become eligible after 30 seconds of measurement;
  later estimates use the trailing 30-second signal. A measured baseline is
  labeled as such until a live monitoring estimate arrives. If updates stop,
  old live numbers are replaced by a neutral measuring state rather than
  presented as current readings.
- The baseline deadline can use the best physiologically plausible,
  beat-derived estimate from retained conditioned data. It does not substitute
  fixed synthetic HR/RMSSD values.
- Stress sensitivity: 3%.
- No simulated/recorded stress control.
- A meditation starts when stress is detected or, if no intervention has
  started, after two minutes in the monitoring phase.
- Meditation structure: welcome message, up to three generated 30-second
  segments, completion message.
- The segment count is a cap, not a fixed length. The demo ends on the same
  HR-only recovery rule as the regular mode: after each segment, measured heart
  rate at or below baseline completes the meditation.
- A meditation started by the two-minute guarantee rather than by stress
  detection begins with heart rate already at or near baseline, so it will
  often satisfy that rule after the first segment.

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

Requested stream rates are 200 Hz for PPG and 25 Hz for accelerometer and
gyroscope. The lower motion-sensor rates reduce concurrent streaming traffic
while meditation audio plays. When sensor metadata is unavailable, the
configured fallbacks are 100 Hz for PPG and 25 Hz for both motion sensors.

### Optical channel selection

The channel carrying the pulse is chosen by **perfusion index** — modulation
relative to that channel's own DC level — and then held for the measurement.

Ranking by absolute AC amplitude, as the earlier rule did, favours whichever
channel is brightest rather than whichever has the strongest pulse. On an
OpenEarable v2 recording the two differ sharply:

| channel | DC | perfusion | cardiac-band SNR |
| --- | ---: | ---: | ---: |
| green | 128540 | 0.045% | 33.6 dB |
| red | 85990 | 0.055% | 37.0 dB |
| infrared | 40890 | 0.107% | 43.6 dB |

Green has the largest absolute swing and the weakest pulse. The old rule
selected it 96.8% of the time and the pipeline detected 73% of beats.

A switch is also not free: it is a discontinuity for every filter downstream
that carries state. The old selector switched 68 times in 150 seconds, and
ranking correctly while still switching recovered only 83% of beats. So the
choice is committed when calibration ends and released only when a new
calibration begins, since the earbud may have been refitted by then. A
challenger must beat the channel in use by 15% before the selector moves at
all, which keeps genuinely comparable channels from trading places on noise.

Measured end to end on that recording: beat yield 0.73 to 0.98, RMSSD 265 ms to
110 ms, channel switches 68 to 0. The decision is recorded in the diagnostic
trace as `optical_channel_committed`, with each channel's perfusion index.
Set `BioAdaptiveModeConfig.useNormalizedChannelSelection` or
`commitOpticalChannelAtMeasurementStart` to false to restore the old behaviour
for comparison.

Named optical axes are resolved before positional fallbacks are used. Red and
infrared matching is deliberately disambiguated, so an `infrared` label cannot
also be selected as the red channel. Cartesian motion axes use token/exact-name
matching rather than arbitrary substring matches.

The low-level filters, quality scoring, adaptive channel selection, and
estimator coefficients live in `model/hr_hrv_processor.dart`; pulse-interval
artifact handling lives in `model/pulse_interval_rmssd.dart`. They are
intentionally not duplicated in the high-level configuration files.
The baseline deadline and live monitoring use the same peak-detection
candidates. The processor ranks positive/negative peaks at the existing
standard/sensitive thresholds by clean consecutive beat pairs, keeps the
selected detector stable, and resets RR history before a justified detector
switch. This avoids mixing pulse peaks from different polarities in RMSSD.
The IMU-dependent motion-filter smoothing is scaled to the selected motion
sensor rate, so requesting 25 Hz does not silently slow its response relative
to the former higher-rate setting.

### Opt-in HR/RMSSD diagnostic trace

To investigate implausible RMSSD readings on a real earbud, run a **debug**
build from `open_wearable/` with:

```powershell
flutter run --dart-define=MEDITATION_HR_HRV_TRACE=true
```

To isolate the effect of background audio on earbud sensor delivery, compare
one traced debug session with the normal command against another using:

```powershell
flutter run --dart-define=MEDITATION_HR_HRV_TRACE=true --dart-define=MEDITATION_SKIP_BACKGROUND_MUSIC=true
```

The second command skips background music only in a debug build; narration
still plays, and normal/release meditation behavior is unchanged.

Normal debug runs and all profile/release builds leave tracing off. Each live
biosignal session writes a JSONL file to the app-private application-support
directory under `meditation_hr_hrv_traces/`. The exact absolute path is printed
once in the Flutter debug log as `HR/HRV diagnostic trace: ...`; Android Studio's
Device Explorer can retrieve it from the debug app's private files. The file
records requested and observed sample rates, source-delivery counts and
processing time, timestamp gaps, selected optical channel and switch counts,
phase boundaries, meditation/audio/narration start and app-lifecycle events,
waveform quality, detected peak times, interval acceptance/rejection, rolling
HR/RMSSD and its pair count, and the demo baseline deadline decision. It does
**not** record raw PPG samples, names, API keys, or cloud prompts, and it is never
uploaded automatically. Nevertheless, beat times
and biometrics are sensitive physiological data: share the file only
deliberately and remove it from the device after analysis. A trace stops at
5 MiB; a new session creates a new file. The trace observes existing decisions
and does not change any filtering, eligibility, or mode timing.

To compare PPG delivery during audio **without** the JSONL trace, run a debug
build with only `--dart-define=MEDITATION_PPG_RATE_LOG=true`. Flutter logs then
print `Meditation PPG delivery` every five seconds with the received sample
rate and sensor-time span, plus the selected sensor rates at session start.
This does not write a file or time individual samples; it is also off by
default and in release builds. To compare baseline and live metrics without
the file trace, additionally set
`--dart-define=MEDITATION_HR_HRV_SUMMARY_LOG=true`. This prints only baseline
and published HR/RMSSD summaries, detector mode, and clean-pair count.

To compare all four detector candidates on the **same conditioned PPG window**
without writing a trace file, add
`--dart-define=MEDITATION_DETECTOR_COMPARE_LOG=true` to a debug run. The log
reports a baseline-deadline snapshot in the demo, then at most one monitoring
snapshot every 30 seconds after 30 seconds of measurement data. Each snapshot
includes the candidate's peak count, accepted and
rejected interval counts, clean consecutive-pair count, HR, and RMSSD/method.
It also identifies the active and internally top-ranked candidate. The snapshot reports each of the four
polarity/sensitivity modes on **both** signal paths, tagged with `signal_path`,
so one traced run compares them without rebuilding the app.
This is a
shadow comparison: it never selects a mode or changes published measurements.
It adds work only at those snapshots, not for each PPG sample, and does not
write a file unless the separate trace flag is enabled. Internal consistency
is not a ground-truth accuracy test; choosing one fixed release detector needs
comparison with an independent beat-time reference across representative
wearers and conditions.

For a compact beat-timing diagnostic, add
`--dart-define=MEDITATION_BEAT_QUALITY_LOG=true`. At the same baseline and
monitoring snapshot cadence, this prints the active detector's complete
peak-to-peak interval sequence in milliseconds (`!` marks an interval outside
250–2000 ms), detected peak/clean-pair counts, age of the newest peak,
effective PPG rate, selected optical channel, and the existing last-three-
seconds waveform-quality and motion scores. At the baseline deadline it uses
the detector chosen from the retained baseline window. The sequence is derived
from detected beats, not an independent heart-rate reference. No raw PPG or
file is written by this flag; the printed intervals are still sensitive
physiological data. This snapshot is observational and cannot change HR,
RMSSD, detector choice, stress detection, or timing. Combine it with the PPG
rate, summary, and detector-comparison flags for a fully lightweight demo run.

### Beat timing signal path

Two signals are derived from each PPG sample. The **conditioned** signal runs
the full chain — ambient cancellation, IMU cancellation, motion suppression,
DC block, band-pass, bounded normalisation — and is what quality scoring is
calibrated against. The **beat** signal takes the selected optical channel
straight into a DC block and band-pass with the same coefficients, skipping
every smoothing stage.

The reason is peak sharpness. The smoothing stages round the systolic edge into
a broad hump, so its maximum wanders: measured peak positions on an
OpenEarable v2 recording sat 130–148 ms behind a clean reference (a constant
group delay, harmless) with a standard deviation of **62 ms**. RMSSD squares
successive differences, so that jitter alone contributes roughly 87 ms of pure
measurement noise. The conditioned signal's samples near a peak are 4.6× flatter
than its own average, which is what makes the maximum ambiguous.

Detecting and timing beats on the lightly filtered path instead, on that same
recording: outlier-filtered RMSSD **117 ms to 81 ms** during meditation with
implausible intervals dropping from 3 to 1, and **166 ms to 111 ms** during
monitoring. The band itself is not the issue — 0.45–5.5 Hz and 0.7–3.0 Hz
perform identically — so the existing coefficients are reused unchanged.

The obvious objection — that the skipped stages exist to tolerate movement —
was tested on a recording with deliberate head movement and talking. Mean clean
consecutive beat pairs per comparison window:

| motion level | beat path | conditioned |
| --- | ---: | ---: |
| still, below 0.15 | 8.0 | 7.5 |
| light, 0.15–0.35 | 16.2 | 12.0 |
| sustained, above 0.35 | 11.5 | 8.5 |

The lightly filtered path led in 7 of 8 windows with lower RMSSD throughout, so
it is **on** by default. Those stages were not protecting the waveform under
motion; the motion suppressor's step limiter and the normalizer's clipping were
themselves distorting it. Evidence is one recording of eight comparison
windows, so `BioAdaptiveModeConfig.useLightlyFilteredBeatPath` can be set to
false to revert. Whichever way it is set, the detector-comparison diagnostic
evaluates every detector on **both** paths over identical windows, tagging each
candidate with `signal_path`.

The smoothing this path skips was doing **two** jobs, and the first attempt only
accounted for one. It rounded off the systolic edge, costing timing precision —
but it also blurred away the dicrotic notch. Restoring the edge restores the
notch, and the 250 ms beat-separation floor used for the conditioned signal then
lets the notch register as a beat. Because a detector mode is selected once and
then held, one unlucky selection locked a bad mode in for a whole session:
published heart rate read 77 bpm against a true 52, having started at 144 and
decayed slowly as the Kalman filter converged.

`beatPathMinimumBeatIntervalSeconds` (400 ms) is the fix. What matters is not
just that the best mode improves but that the modes stop disagreeing, since that
is what makes the one-shot selection safe. Worst-case spread across the four
legacy modes, measured on three recordings:

| session | channel | before | after |
| --- | --- | ---: | ---: |
| still | infrared | 1.8 bpm | 0.9 bpm |
| with movement | green | 18.4 bpm | 3.7 bpm |
| seated | green | 13.3 bpm | 1.1 bpm |

Green is the channel that suffers: its dicrotic notch is more prominent than
infrared's, so sessions committing to infrared never showed the fault.

Ruled out along the way, each measured rather than assumed: a running-window
amplitude threshold, the refractory period (swept 212–600 ms), the normalizer's
±1.45 clamp (raising it to 4.0 cuts saturation from 5.1% to 0.2% and moves
jitter by 1.5 ms), and each conditioning stage bypassed individually.

### Waveform capture and offline replay

The decision-only trace above records what the processor *concluded*. To work
out *why* it concluded it, a debug build can additionally record the waveform
itself:

```powershell
flutter run --dart-define=MEDITATION_CAPTURE_SIGNAL=true
```

This implies the trace flag and adds three block events to the same JSONL file:

| Event | Contents |
| --- | --- |
| `ppg_raw_block` | raw `red`, `ir`, `green`, `ambient` as delivered by the sensor |
| `imu_raw_block` | raw accelerometer `x`, `y`, `z` |
| `ppg_conditioned_block` | the conditioned `signal` and `motion` level, with phase and selected channel |

Samples are grouped into blocks with timestamps stored as offsets from each
block's base, because one line per sample at 200 Hz is neither readable nor
compact. Conditioned values are rounded to five decimals. Capturing raw and
conditioned data together means an offline replay can re-run conditioning with
different filters *and* verify it reproduces what the device computed. Partial
blocks are flushed when the session ends, so the final seconds survive. The
trace size limit rises from 5 MiB to 256 MiB while capture is enabled.

Analyse a capture without a device using the replay harness:

```powershell
flutter test test/apps/meditation_app/trace_replay_test.dart "--dart-define=MEDITATION_TRACE=C:\Users\you\Downloads\hr_hrv_2026-09-21T13-01-19-249509Z.jsonl"
```

Run it from `open_wearable/`, and substitute your own absolute path. Quote the
whole `--dart-define=...` argument: that keeps a path containing spaces in one
token, and PowerShell treats `<` and `>` as redirection operators, so a literal
placeholder in angle brackets is a syntax error rather than a prompt.

It reports session markers, stream health and published metrics split at the
moment audio starts, the per-detector comparison table, and — when a waveform
capture is present — replays the raw signal through the real pipeline under
both beat detectors. The harness is skipped when no trace is supplied, so it
never runs as part of the normal suite.

This capture is the most sensitive artefact the app can produce: it is the raw
optical waveform, not just derived numbers. It is debug-only, never uploaded,
and should be deleted from the device and the analysis machine afterwards.

### Audio route diagnostic

PPG delivery collapses from 200 Hz to roughly 67 Hz in some sessions and not at
all in others, with the same build and the same earbud. Across three traced
sessions:

| ambience at | first narration | rate collapse | after audio |
| ---: | ---: | ---: | ---: |
| 180.8 s | 189.4 s | 187.8 s | 67 Hz |
| 146.5 s | 168.1 s | never | 200 Hz |
| 180.4 s | 189.2 s | 188.7 s | 67 Hz |

The collapse lands *before* the first narration in both degraded sessions, so
it is not narration; and the middle session played ambience for 84 seconds plus
all three narration segments without degrading, so it is not simply ambience
either. When it happens it happens 7–8 seconds after `audio_started` and
persists for the whole session. That pattern — all-or-nothing, fixed latency,
never recovering — points at how the audio link gets established rather than at
steady contention.

Nothing in Dart can observe which output device Android chose, so this is the
one diagnostic that reaches into the platform layer:
`android/app/src/main/kotlin/.../AudioRouteDiagnostics.kt`, a method channel
that reports connected output device types, whether a Bluetooth audio sink is
among them, the A2DP and LE Audio profile connection states, the communication
device on API 31 and above, and whether music is active.

It is strictly read-only — it never changes routing, volume, focus or any
Bluetooth profile — and `AudioRouteDiagnostics.isAvailable` gates it on the
biosignal trace being enabled, so a normal build never invokes the channel at
all. Three snapshots are recorded per session: at `audio_started`, twelve
seconds later (bracketing the 7–8 second collapse window), and at every
narration. The replay harness prints each snapshot next to the PPG rate
measured around it, which is what distinguishes "the route changed" from "the
route was always the earbud and something else gave way".

## Keeping the screen awake

A meditation waits minutes on DeepSeek and the text-to-speech service with no
touch input. When Android turns the display off it suspends those requests and
the session stalls partway through, so `MeditationView` holds a wakelock for as
long as the in-app is open: acquired in `initState`, released in `dispose`.

This only prevents the idle timeout. It is not background execution, and it does
not stop someone deliberately pressing the power button.

The host app already exposes a global **keep app in foreground** setting driving
the same wakelock, so `ScreenWakelock.release()` restores whatever that setting
asks for rather than switching it off. A failure to set the lock is logged and
ignored; it must never prevent a meditation from starting.

## Reading the metric tiles

Entering monitoring deliberately rebuilds the HR and RMSSD tiles so each can
show the measured baseline, labelled `Baseline: …`, until its first live
monitoring sample arrives. That label therefore means "no live value yet for
this metric", not "poor signal".

It is easy to make it appear far more often than intended. `StreamBuilder`
compares stream *instances*, so a stream derived inside `build` is a new object
every time and makes it resubscribe, drop to `ConnectionState.waiting` and show
the baseline again. `Measurement` therefore exposes every tile stream as a
`late final` - including `rmssdDisplay`, which filters out samples carrying no
RMSSD and formats the number - rather than letting the view derive them. The
RMSSD tile is the one that suffers most from getting this wrong, because that
filtering means the next live value can be a long time coming.

## Losing the sensor

The in-app is pushed as its own route, so a disconnected earbud leaves the
screen underneath rebuilding while the session on top keeps running against a
device that is no longer there. Two mechanisms cover that:

- `WearableConnection` follows the SDK's disconnect listener. Starting an
  EarStreAM session or choosing a demo mode while disconnected is refused with
  an explanation rather than beginning a measurement that can never complete.
- `SensorBiometricSource` watches PPG arrival and publishes `signalAlive`. At
  200 Hz a five-second silence is never signal quality, so the session says so
  instead of leaving a full progress bar with no explanation. The streams also
  carry `onError`/`onDone` handlers, which previously had none: a stream that
  ended simply stopped delivering, silently and permanently.

This matters most in the baseline. The demo's guaranteed-meditation timer only
arms once monitoring is reached, so a dead sensor during the baseline would
otherwise strand the session with the safety net disarmed.

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

Both system prompts require breathing guidance in every segment but forbid
counting it out: no numerals and no number words for breath timing. The pacing
is carried by wording and ellipses instead ("let the out-breath run longer than
the in-breath"). Counted cadence was the earlier instruction, and numerals in
particular read badly on the local Kokoro voice, which speaks them as digits
rather than pacing them. Like the English-only rule, it is repeated in every
segment request, since a constraint stated once in the system prompt drifts as
the conversation grows.

Standard-mode prompts include profile and meditation context. Biosignal-adaptive
standard sessions additionally include the latest HR/RMSSD after a segment.
Timed sessions report that no biosignals are available.

Demo prompts contain only the attendee's session meditation type and imagery
environment. They explicitly prohibit names, age, gender, fitness information,
health inferences, permanent profile data, and physiological measurements.

If the opening generation fails, the whole session switches to the static
local script. If generation of a later adaptive segment fails, that segment is
replaced with the static fallback text and the remaining session can continue.

### Backup narration when DeepSeek is unreachable

Generation can drop out in three places, and all three resolve through
`createFallbackScript`:

1. no valid DeepSeek key, so `createMeditationScript` never builds an adaptive
   script at all;
2. the opening request fails, which `Meditation._run` catches; and
3. a later segment request fails, which `AdaptiveMeditationScript` catches
   internally.

Regular and timed sessions fall back to one generic paragraph, which is
acceptable for a session the user can restart. The conference demo cannot be
restarted gracefully with an attendee already wearing the earbuds, so it falls
back to pre-written narration in `model/demo_fallback_script.dart` instead,
chosen by `MeditationPromptPolicy.conferenceDemo`.

That script covers every combination an attendee can select: four meditation
types by five environments, each with its own welcome, completion message and
three segments.

The texts are not hand-written. They were captured from DeepSeek by driving
`AdaptiveMeditationScript` with the real conference-demo prompts once per
combination, so a fallback session reads exactly like a live one rather than
noticeably flatter. Regenerate them with:

```powershell
# 1. capture, by running the real demo prompts once per combination
flutter test test/apps/meditation_app/demo_fallback_generator_test.dart `
  --dart-define=GENERATE_DEMO_FALLBACK=true
# 2. bake the captured text into Dart constants
dart run tool/bake_demo_fallback.dart
dart format lib/apps/meditation_app/model/demo_fallback_script.dart
```

Both halves are committed, so the narration can be reviewed as a diff and
rebuilt without guesswork: the captured text in `tool/demo_fallback.json`, and
the two steps that turn it into `demo_fallback_script.dart`. That file is
generated — edit the JSON and re-bake rather than editing it by hand.

The capture step is skipped by default and is the only test that reaches the
network, so a normal `flutter test` run never calls DeepSeek. Only the two
session preferences reach the prompt, so the captured text contains nothing
personal. Rerun it after changing the demo prompts or the selectable
preferences.

Segment indices past the written three wrap around, so raising the demo segment
cap keeps producing usable narration. The biosignal-adaptive demo can end after
any segment once heart rate has returned to baseline, and the completion
message closes the session from wherever it stopped.

The texts are Dart constants rather than a bundled asset: they exist for the
case where things are already failing, and a constant cannot fail to load,
parse, or be left out of a build. Speaking speed and voice gender do not affect
them — those are delivery settings, applied by the TTS provider.

### Narration pipeline

Generation and speech synthesis used to happen in the gap between segments, so
the listener sat through a DeepSeek request plus a TTS request as silence
before every segment. They now run *during* playback of the previous segment.

`TtsService` splits into `prepare(text)`, which synthesizes and returns a
`PreparedNarration`, and `play(narration)`, which only plays. `Meditation`
runs a single producer that generates and synthesizes ahead into a bounded
buffer, while the consumer plays from that buffer.

- One producer, not several: each generated segment is conditioned on the
  conversation history of the one before it, so the requests cannot be
  parallelized.
- Lookahead depth is `OverallMeditationConfig.narrationPrefetchDepth` (3).
  `BiometricMeditation` overrides it to 1, because its request carries the
  biometrics read when the current segment starts; producing further ahead
  would send readings from progressively further in the past.
- The **decision** to play a produced segment is unchanged: it is still taken
  at the end of the previous segment, against heart rate. A segment that was
  produced ahead of a recovery exit is discarded, not played.
- The welcome message is the one narration nothing precedes, so its synthesis
  is still awaited on its own. The first segment and the completion message are
  produced while it plays.
- Producer and consumer wake each other directly, so a segment that arrives
  late starts playing the moment it is ready.
- When the session ends early, the producer is told to stop and is *not*
  awaited: a request already in flight has nowhere to go and must not hold back
  the closing narration. Disposing the script ends that request.
- Retries live in `prepare`. Playback of already-fetched audio is not retried,
  since replaying part of a spoken segment is worse than surfacing the error.
- Narration that was prepared before a voice-service outage is still played;
  the session fails only once it actually runs out of narration.

## Text-to-speech and audio

The TTS provider, the processing region and the ElevenLabs voice id are
selected on the **API Keys** page, and are not available in Profile,
Meditation Preferences, or demo attendee preferences.

Voice gender is a meditation preference, not a service setting: it appears at
the top of **Meditation Preferences** and of the demo attendee preferences, as
well as on the API Keys page where it is labelled **Default Voice**. All three
edit the same `UserAccount.voiceGender`, which every provider maps to its own
voice — an ElevenLabs voice id, a Tencent voice type, or a Kokoro speaker id.

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

### Kokoro (on-device)

A third provider that synthesizes narration on the phone, selectable exactly
like the two cloud voices: `TTS_PROVIDER=kokoro` in the environment asset, or
the TTS Provider dropdown on the **API Keys** page. It needs no API key, no
account, and no network request, which is what makes it usable where the cloud
endpoints are unreachable.

- Model: `kokoro-multi-lang-v1_0` (Kokoro v1.0, 82M) run through
  `sherpa_onnx`. The earlier `kokoro-en-v0_19` was trained on under a hundred
  hours against v1.0's several hundred, which is where its remaining synthetic
  edge came from; v1.0 keeps both voices.
- Voices: `bf_isabella` (speaker 22) and `bm_lewis` (speaker 27), chosen by the
  **Default Voice** setting. The speaker ids are positions in that model's own
  voice list and move if the model is swapped - the same two voices were 8 and
  10 under v0.19.
- Pronunciation uses the bundled `lexicon-gb-en.txt`, matching the British
  voices, with espeak-ng as the fallback for anything not in it. The model also
  ships American and Chinese lexicons, a Chinese dictionary and Chinese
  normalisation FSTs; the narration is English-only by prompt rule, so none of
  them are loaded. They can be deleted from the asset directory to save about
  22 MB, and a re-extract restores them.
- Speaking speed maps onto Kokoro's own multiplier, where 1.0 is the model's
  natural pace. This is not the normalized 0.0-1.0 scale `flutter_tts` uses.
  All four settings sit below 1.0 (0.50/0.60/0.70/0.80): Kokoro's natural pace
  is a reading pace and is too brisk for guided meditation. Note that
  ElevenLabs sends no speed parameter at all, so the same setting has no effect
  there.
- Synthesis runs in a worker isolate: the native engine handle never leaves it
  and only finished audio comes back, so a segment that takes tens of seconds
  does not freeze the UI. The narration pipeline above overlaps that cost with
  playback of the previous segment.
- One engine is shared for as long as the in-app is open, because loading the
  model costs seconds and several hundred MB. It is released in
  `MeditationView.dispose`.
- Output is 16-bit PCM WAV played from memory, like the cloud providers' MP3.

Rhythm is tuned with `kokoroSilenceScale`, which multiplies every pause longer
than 0.2 s after synthesis. sherpa-onnx defaults it to 0.2, compressing pauses
to a fifth of their length; the in-app sets 1.5 instead, because in guided
meditation the pauses carry the pacing. Valid range is 0.01 to 10.

Kokoro has no pitch parameter and no style or instruction prompt: its timbre
comes entirely from the speaker's style vector in `voices.bin`, so the only
ways to change the delivery are the voice, the speed, the silence scale, and
the punctuation of the generated text. Ellipses, commas and sentence breaks are
what produce the pauses that the silence scale then stretches, which makes the
DeepSeek prompt the closest thing to a style control.

#### Adding the model to a build

The model is not in the repository: it is about 340 MB and is gitignored. A
build without it simply reports the local voice as unavailable, and sessions
fall back to the device voice exactly as they do for an unverified API key.

```powershell
# From the repository root. Requires the tar bundled with Windows 11.
curl.exe -L -o kokoro.tar.bz2 `
  https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2
tar -xf kokoro.tar.bz2 -C open_wearable/android/app/src/main/assets/
```

That leaves `android/app/src/main/assets/kokoro-multi-lang-v1_0/` containing
`model.onnx`, `voices.bin`, `tokens.txt`, `lexicon-gb-en.txt`, and
`espeak-ng-data/`. Rebuild the
APK, then press **Prepare On-Device Voice** on the API Keys page once per
phone.

It lives under `src/main/assets/` rather than in the Flutter `assets:` list on
purpose. Flutter's asset declarations do not recurse into sub-directories, and
espeak-ng's phoneme data is several hundred nested files; `rootBundle.load`
would also have to hold the 330 MB ONNX graph in memory in one piece. Android's
`AssetManager` can walk the tree and stream each file, so `KokoroModelInstaller`
copies it out in constant memory. ONNX Runtime needs real filesystem paths, so
that one-time copy cannot be avoided: expect roughly 340 MB of app storage on
top of the APK, and up to a minute the first time.

The copy is resumable. Each file is written under a `.partial` name and renamed
into place, so a file that exists is complete; a `.installed` marker written at
the end lets later launches skip the walk entirely.

#### Build size

The debug APK is already around 500 MB before the model, mostly the bundled WAV
ambience plus native libraries for four ABIs. With the model it approaches
850 MB, which makes `flutter install` slow. Building only for the demo phones'
architecture avoids shipping three unused copies of the ONNX Runtime and
sherpa-onnx libraries:

```powershell
flutter build apk --release --target-platform android-arm64
```

### Provider consistency and device fallback

The TTS route is selected once when a meditation object is created.

- If the selected provider is not marked valid at session start, the whole
  meditation uses on-device Flutter TTS. For Kokoro "valid" means the model is
  bundled in this build, which is probed when the in-app opens rather than
  entered by the user.
- The speaking-speed preference reaches every provider: Tencent's own scale,
  Kokoro's multiplier, and ElevenLabs' `voice_settings.speed` (0.7-1.2, where
  1.0 is the voice's natural pace).
- If a selected provider is initially available but later fails, the app
  retries it three times (immediately, after one second, and after two seconds).
- After those failures, the meditation stops and shows a voice-service failure
  card. It does not switch voices in the middle of a meditation. Kokoro is a
  selectable provider, not an automatic fallback for a failing cloud voice;
  swapping the narrator mid-session is what this rule exists to prevent.

Pausing suspends narration in place rather than stopping it, so resuming
continues the segment instead of speaking it again from the first word. The
on-device `flutter_tts` fallback offers no dependable resume, so that one route
is stopped and replayed.

Pausing the EarStreAM session pauses a running meditation with it. It used to
stop and dispose the session, so resuming brought back nothing and analytics
recorded an abandoned meditation every time the user paused.

The background player and the voice service are created on first use. A
scheduled meditation can sit queued for hours, and building them at schedule
time held a native audio player - and, with Kokoro selected, potentially a
loaded voice model - for a session that had not started.

Other unexpected playback/session failures also stop both narration and
ambience and show a dismissible interruption card. Failure handling belongs to
the shared meditation session, so timed and both demo/regular meditation paths
behave consistently.

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

Connection checks are revisioned: a response from an older check is ignored if
the credentials or region changed while it was in flight. Verifying a different
ElevenLabs account also clears a selected voice ID when that voice is not
available to the newly verified account.

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
- **Meditation Preferences**: voice gender, speaking speed, meditation type,
  environment, additional text preference, and regular stress sensitivity;
- **Weekly Analytics**;
- **Seal Check**; and
- **API Keys**: provider, voice, Tencent region, credentials, and live service
  checks.

Provider, region and credential settings exist only on API Keys. Voice gender
and speaking speed are meditation-delivery preferences and are editable in
Meditation Preferences and in the demo attendee preferences as well.

When no sensor baseline exists, profile-derived HR/RMSSD estimates can provide
context outside the live baseline workflow. These estimates are calculated on
demand and are not stored in the measured-baseline fields.

## Completion and analytics

Completed sessions show a success card and the single-line mood choices
**Serene**, **Relaxed**, **Neutral**, and **Stressed**. Selecting a mood
currently dismisses the completed session; mood values are not persisted.

In the biosignal-adaptive modes the card replaces the session view rather than
appearing beneath it: the live measurement, API warnings, and session controls
are hidden while it is shown, matching the meditation-only demo. The measurement
keeps running underneath, hidden rather than removed, so the heart-rate chart
retains its history and is live again the moment the card is dismissed. The
demo's **End Demo** button sits outside this view and stays available.

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
| `overall_config.dart` | Shared generation, cloud and local TTS, playback, environment, sensitivity, and analytics values |
| `timed_mode_config.dart` | Timed segment count and scheduling intervals |
| `bio_adaptive_mode_config.dart` | Regular phases, processing windows, sensors, activity thresholds, recorded stress, and HR recovery |
| `demo_mode_config.dart` | Condensed demo timing, segment counts, privacy, guaranteed trigger, and China deployment values |

`model/bio_adaptive_session_config.dart` maps the regular and conference-demo
configuration into the same measurement/session pipeline.

The shared session lifecycle and mode-specific meditation subclasses live in
`model/meditation.dart`; narration routing is isolated in
`model/tts_service.dart`, with the local Kokoro engine and its model unpacking
in `model/kokoro_tts_engine.dart` and `model/kokoro_model_installer.dart`. Credential verification is similarly kept in
`model/service_connection_manager.dart`, while `widgets/status_field.dart`
only renders its state. Sensor-name interpretation is isolated in
`model/sensor_axis_mapping.dart`, and the translation from an SDK reading to
the pipeline's own sample types in `model/sensor_sample_decoding.dart` - pure
functions, so the optical-channel and axis handling is testable without a
device. Labels, icons, and colors for monitoring,
stress, and activity states remain in the bio-adaptive view rather than the
domain models.

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
|   |-- demo_fallback_script.dart
|   |-- elevenlabs_api.dart
|   |-- hr_hrv_diagnostics.dart
|   |-- hr_hrv_processor.dart
|   |-- kokoro_model_installer.dart
|   |-- kokoro_tts_engine.dart
|   |-- measurement.dart
|   |-- measurement_phase.dart
|   |-- meditation.dart
|   |-- meditation_analytics.dart
|   |-- meditation_prompt_policy.dart
|   |-- meditation_session_generator.dart
|   |-- monitoring_meditation_deadline.dart
|   |-- pulse_interval_rmssd.dart
|   |-- sensor_axis_mapping.dart
|   |-- sensor_sample_decoding.dart
|   |-- service_connection_manager.dart
|   |-- stress_detector.dart
|   |-- tencent_tts_client.dart
|   |-- tts_service.dart
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
flutter test test/apps/meditation_app/
flutter run
```

`hr_hrv_processor_test.dart` covers configuration alignment, calibration
isolation, demo deadline estimates, provider/region parsing, voice selection,
demo privacy, stress playback, HR-only recovery, demo segment capping,
presentation, weekly analytics, Tencent signing/chunking, sensor-axis
disambiguation, stale credential checks, prompt formatting, and
demographic-baseline isolation.

`meditation_pipeline_test.dart` drives a whole `Meditation` against a fake
audioplayers platform and a fake `TtsProvider`, and covers the narration
pipeline: overlap of synthesis with playback, the lookahead bound, discarding a
segment prefetched ahead of an early exit, stopping the producer on stop, and
voice-outage handling.

`kokoro_tts_test.dart` covers the on-device voice: provider selection from the
environment, speaker and speed mapping, engine sharing, WAV encoding, and every
way the local route can be absent. The native library and the model are not
available to the test VM, so the engine and the platform channel are replaced;
everything built on top of them runs for real.

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
