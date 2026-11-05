# EarStreAM

EarStreAM is a guided-meditation in-app for OpenWearable. It can run an
ordinary timed meditation or use live signals from a compatible OpenEarable to
wait for signs of stress and start a meditation when support may be useful.

EarStreAM received one of the Best Demo Awards at UbiComp 2026 in Shanghai.

EarStreAM is a research and wellness tool. Its stress estimates are not a
medical diagnosis and must not be used for medical decisions or emergencies.

## What you need

- The OpenWearable app with EarStreAM included.
- A compatible OpenEarable exposing PPG, accelerometer, and gyroscope sensors
  for biosignal-adaptive sessions.
- A stable earbud fit. The **Seal Check** page can help you check it.
- Internet access only if you choose cloud personalization. Local guidance and
  on-device speech remain available without cloud services.

Timed meditation does not use wearable measurements, but EarStreAM currently
opens through OpenWearable's wearable-selection flow.

## First use

When EarStreAM opens for the first time, it asks how meditation data may be
processed:

- **Cloud personalization** allows DeepSeek to generate guidance from the
  profile and meditation preferences you save. In a biosignal-adaptive session,
  heart rate and HRV readings can also be included after meditation segments.
  The selected ElevenLabs or Tencent service receives the generated narration
  to turn it into speech.
- **Local only** uses pre-written guidance, on-device text-to-speech, and
  bundled ambience. EarStreAM does not send your profile, preferences, heart
  rate, HRV, or narration to those cloud providers.

This is not a permanent decision. Open **Privacy & Data** from the EarStreAM
menu at any time to change it. Selecting local-only mode keeps saved API
credentials on the device but does not use them.

## Start a meditation

1. Connect a compatible OpenEarable in OpenWearable and open **EarStreAM**.
2. Use **Seal Check** if the earbud fit or signal quality is uncertain.
3. Optionally complete **Profile** and **Meditation Preferences**.
4. If you want cloud-generated guidance or a cloud voice, configure and verify
   the services on **API Keys**.
5. Open **Meditation Mode**, choose a mode, and follow its on-screen controls.
6. Keep the OpenWearable app active during the session. EarStreAM keeps the
   screen awake, but it is not a background service.

Pausing a session also pauses its narration. After a completed regular session,
you can select how you feel and review session activity in **Weekly Analytics**.

## Meditation modes

### Biosignal-Adaptive

This is the normal stress-adaptive mode. It uses PPG to estimate heart rate and
heart-rate variability (RMSSD), and motion sensors to avoid interpreting
sustained physical activity as stress.

A session progresses through three stages:

1. **Calibration** takes about 30 seconds and evaluates the available optical
   channels.
2. **Baseline** takes at least five minutes and waits longer when no reliable
   heart-rate and RMSSD pair is available. A complete age, gender, and fitness
   profile can support the early baseline estimate, but it never replaces the
   live measurement.
3. **Monitoring** compares current measurements with the baseline. A meditation
   starts when heart rate rises and RMSSD falls beyond the selected sensitivity
   while the user is sufficiently still.

The meditation can contain up to ten segments. After each segment, EarStreAM
checks whether heart rate has returned to the measured baseline and can finish
the meditation early.

For testing and demonstrations, this mode also exposes **Play Recorded Stress**.
It plays a fixed stress-and-relaxation trajectory at the same display cadence
as live measurements; it is not a recording of the current user's body and
should not be used as a real measurement.

### Timed

Timed mode starts guided meditation without using biosignals. You can start
immediately, after 5, 10, or 30 minutes, or at a chosen time. It uses the saved
profile and preferences when cloud personalization is enabled and runs three
guided segments.

Scheduling is in-memory only: it is not an operating-system alarm or
notification. The OpenWearable process must remain active, and a scheduled
session is lost if the app is closed or restarted.

### Demo

Demo mode is the condensed experience created for short demonstrations. It
does not add sessions to Weekly Analytics and uses an attendee-specific set of
preferences rather than the saved personal profile.

- **Biosignal-adaptive demo** uses a 30-second calibration, a 30-second live
  baseline, a lower stress threshold, and up to three 30-second meditation
  segments. If no stress response is detected, a meditation is started after
  two minutes of monitoring so the demonstration can finish on time.
- **Personalized meditation demo** does not use biosignals. It creates three
  30-second segments from the attendee's selected meditation type and
  environment.

Demo cloud prompts exclude the permanent profile and physiological readings.
If local-only mode is selected, the demo uses its pre-written guidance and
on-device speech instead.

## Configure EarStreAM

All settings below are available from the menu inside EarStreAM and persist
across app restarts.

### Profile

Save a first name, age, gender, and fitness level. A complete demographic
profile can contribute to the early baseline estimate and to cloud-personalized
wording. Leaving fields empty is supported.

### Meditation Preferences

Choose:

- default voice gender and speaking speed;
- mindfulness, breathing, body scan, or visualization guidance;
- nature, ocean beach, mountain, forest, or garden ambience;
- optional free-text guidance preferences; and
- biosignal-adaptive stress sensitivity.

The five ambience tracks are bundled compressed MP3 files and play locally.

### API Keys

Cloud services are optional. The page supports:

- **DeepSeek** for generated meditation guidance;
- **ElevenLabs** for cloud speech and selectable voices; and
- **Tencent Cloud TTS** for cloud speech, with International (Singapore) and
  Mainland China (Guangzhou) processing choices.

Enter credentials, run the connection check, and select the desired speech
provider. Credentials and service choices remain saved after EarStreAM or the
whole app is closed. API secrets use the operating system's protected
credential storage; provider, region, voice, and verification state use local
app preferences.

If DeepSeek is unavailable at the start of a session, EarStreAM uses local
pre-written guidance. If the selected speech provider is unavailable at the
start, it uses device text-to-speech for the entire session. If an active cloud
voice repeatedly fails during a session, EarStreAM stops the session instead
of unexpectedly changing voices midway through it.

Using cloud services may incur charges on the account associated with the API
credentials.

### Privacy & Data

Use this page to:

- switch between cloud personalization and local-only meditation;
- open the privacy policies of the supported cloud providers; and
- delete all EarStreAM data from the device.

Deleting EarStreAM data removes the saved profile, meditation preferences, API
credentials, cloud choice, measured baseline, and weekly analytics. It does not
delete data belonging to other OpenWearable in-apps.

### Weekly Analytics

Weekly Analytics summarizes regular biosignal-adaptive and timed sessions,
including duration, completion rate, active days, mode use, and recent
sessions. Records are stored locally for up to 366 days. Demo sessions and the
post-session mood choice are not included.

## Troubleshooting

- **EarStreAM says sensors are missing:** reconnect a compatible OpenEarable.
  The in-app requires PPG, accelerometer, and gyroscope sensors.
- **Calibration or baseline does not finish:** reseat the earbud, run Seal
  Check, stay still, and wait for a reliable signal. The normal baseline is
  intentionally longer than five minutes when valid HR and RMSSD are missing.
- **A meditation does not start while moving:** regular adaptive mode suppresses
  new stress triggers during sustained activity.
- **Cloud guidance or speech is not used:** confirm that cloud personalization
  is selected, the correct provider is selected on API Keys, and its connection
  check succeeds.
- **A timed session did not start:** scheduled sessions require the app process
  to remain active and do not survive an app restart.
- **A session stops after disconnecting:** reconnect the wearable and start a
  new session. EarStreAM cannot continue a live measurement without its sensor
  stream.

Signal quality and stress estimates depend on fit, motion, skin contact, and
the connected device. Network loss, operating-system suspension, or a cloud
provider outage can interrupt cloud-enabled sessions.
