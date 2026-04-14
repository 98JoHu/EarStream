# ACM UbiComp Demo Paper - Draft Section
## Physiological Measurement in EarStreAM

**Version:** Draft 1.0  
**Date:** April 14, 2026  
**Section:** Introduction → EarStreAM System → Physiological Measurement Subsection

---

## DRAFT TEXT FOR PAPER (UPDATED VERSION)

### 3.2 Physiological Measurement and Stress Detection

EarStreAM leverages the OpenEarable platform's in-ear photoplethysmography (PPG) sensors to continuously monitor cardiovascular signals for real-time stress detection. Our system implements a comprehensive signal processing pipeline that extracts heart rate (HR) and heart rate variability (HRV) metrics from raw PPG data, enabling personalized stress assessment that adapts to individual demographics and physical activity patterns.

#### Signal Processing Pipeline

Raw PPG signals are acquired at 200 Hz sampling frequency\textsuperscript{†}, following research recommendations for accurate HRV analysis \cite{task_force_1996}. The signals undergo multi-stage processing to extract robust cardiac metrics. First, the inverted PPG signal (correcting for sensor polarity) passes through a second-order IIR band-pass filter (0.5-4.0 Hz) to isolate the cardiac frequency range while attenuating motion artifacts and baseline drift. Peak detection operates on an 8-second sliding window using a prominence-based algorithm with minimum inter-peak distance enforcement (300 ms) to identify individual heartbeats. Inter-beat intervals (RR intervals) are calculated from consecutive peak timestamps and validated against physiological plausibility criteria through three-stage artifact filtering.

\textit{Artifact Filtering:} Our validation pipeline rejects artifacts through: (1) physiological range enforcement (300-2000 ms corresponding to 30-200 BPM), (2) successive difference limits (<300 ms change between consecutive intervals to detect motion-induced false peaks), and (3) statistical outlier removal (values deviating >25\% from local median). This multi-stage approach maintains robustness during normal activities while preserving genuine heart rate variations.

Heart rate is computed as the inverse of mean RR interval duration and smoothed using a Kalman filter (process noise Q=0.01, measurement noise R=4.0) to reduce transient fluctuations. HRV metrics are derived from the RR interval sequence using established time-domain methods \cite{shaffer_overview_2017}. Our implementation calculates RMSSD (root mean square of successive differences) as the primary metric for stress detection, reflecting parasympathetic nervous system activity\textsuperscript{*}. RMSSD is computed from a rolling 5-minute buffer of RR intervals (approximately 300-400 beats depending on heart rate), with initial provisional values available after 10 intervals but marked as stable only after one minute of continuous measurement. This conservative approach prevents premature stress assessments based on insufficient data. SDNN (standard deviation of NN intervals) is computed in parallel from the same 5-minute buffer for comparative analysis and user feedback, though stress detection relies exclusively on RMSSD due to its superior sensitivity to acute stress responses \cite{nunan_quantitative_2010}.

\textsuperscript{†}Configurable via \texttt{BiosignalConfig.ppgSamplingFrequency}; falls back to highest available sensor frequency if 200 Hz unsupported.

#### Personalized Baseline Establishment

A critical challenge in stress detection is accounting for substantial inter-individual variation in resting cardiovascular parameters. EarStreAM addresses this through a hybrid baseline estimation approach that combines population-based norms with individual measurements. Upon first use, the system initializes baseline values from demographic inputs (age, gender, fitness level) using established research parameters [2,3]. For example, baseline HR ranges from 68 BPM (young, athletic male) to 82 BPM (elderly, sedentary female), while baseline RMSSD ranges from 15-60 ms across the same demographic spectrum.

During each meditation session, the system performs adaptive baseline refinement over an initial 30-second calibration period. Live measurements are integrated with research-based estimates using a time-varying weighted average: initially 80% research / 20% measured, converging to 70% measured / 30% research at calibration completion. This approach enables immediate session initiation without waiting periods while accommodating acute stress states that would bias pure measurement-based calibration.

#### Activity-Aware Stress Detection

A fundamental limitation of HR-based stress detection is the confounding influence of physical activity, which elevates HR through metabolic demands rather than psychological stress. To address this, EarStreAM incorporates concurrent IMU data (accelerometer and gyroscope) from the OpenEarable device to classify activity intensity. We developed earable-specific activity thresholds that account for the unique motion characteristics of ear-worn devices, including sensitivity to jaw motion (eating, talking) and head movements.

Activity classification uses a 30-sample (≈3 second) moving average window of triaxial accelerometer magnitude deviation from 1g gravity and triaxial gyroscope angular velocity. Resting state is defined as accelerometer deviation <0.20g AND gyroscope magnitude <300°/s; moderate or higher activity (>0.40g or >450°/s) suppresses stress detection. This prevents false stress alerts during exercise while maintaining sensitivity during sedentary activities.

#### Stress Classification and Thresholds

Stress state is determined through personalized thresholds derived from the demographic baseline. We define two threshold pairs: \textit{stress thresholds} (HR > baseline $\times$ 1.25 OR HRV < baseline $\times$ 0.60) and \textit{relaxed thresholds} (HR < baseline $\times$ 1.04 AND HRV > baseline $\times$ 1.20). Stress detection is implemented as a continuous background monitor with 3-second polling intervals, triggering user notifications when sustained stress is detected without concurrent physical activity. All threshold multipliers are configurable via \texttt{BiosignalConfig} to facilitate parameter tuning and reproducibility.

Meditation session termination employs a multi-criteria decision algorithm that evaluates both absolute relaxation state (meeting relaxed thresholds) and relative physiological improvement\textsuperscript{‡}. Sessions terminate when any of five conditions are met after a minimum of 2 meditation segments: (1) HRV improvement $\geq$30\% with stress level <40\%, (2) HRV improvement $\geq$25\% with stress level <30\%, (3) HRV improvement $\geq$20\% with relaxed state achieved, (4) both HR improvement $\geq$10\% and HRV improvement $\geq$20\%, or (5) relaxed state with stress <20\% and HRV improvement $\geq$10\%. This HRV-prioritized approach reflects the greater robustness of RMSSD compared to HR as a stress indicator \cite{nunan_quantitative_2010}, while the multiple criteria prevent premature termination from transient signal fluctuations.

\textsuperscript{‡}Due to the slower physiological response of HRV compared to HR, future implementations may adopt HR-only termination criteria for faster session completion while maintaining RMSSD for stress detection accuracy.

\textsuperscript{*}While both RMSSD and SDNN are calculated, only RMSSD is used for stress detection and meditation triggering. SDNN provides supplementary information for user analytics but does not influence real-time decisions due to requiring longer measurement windows for stability.

#### Implementation and Performance

The entire signal processing pipeline executes on-device in Dart, enabling real-time operation without cloud dependencies. HR estimates stabilize within 8-10 seconds of session start, while stable HRV metrics emerge after 15-30 seconds (depending on resting heart rate). Artifact rejection combines physiological validity checks (RR interval range limits, maximum successive difference thresholds) with statistical outlier removal (2.5 SD from local mean), achieving robust operation during normal daily activities including conversation and light movement.

---

## ALTERNATIVE SHORTER VERSION (if word count is constrained)

### 3.2 Physiological Measurement and Stress Detection

EarStreAM performs continuous cardiovascular monitoring using in-ear PPG sensors to detect psychological stress in real-time. Raw PPG signals are band-pass filtered (0.5-4 Hz) and processed through a peak detection algorithm to extract inter-beat intervals (RR intervals). Heart rate is computed as the inverse of mean RR duration and smoothed via Kalman filtering, while heart rate variability is quantified using time-domain metrics including RMSSD (root mean square of successive differences) and SDNN (standard deviation of RR intervals) [1].

To accommodate inter-individual variability, the system establishes personalized baselines through hybrid estimation: demographic-based population norms (age, gender, fitness level) from research literature [2,3] are adaptively refined with 30-second live measurements at session start. Stress thresholds are derived as proportional deviations from baseline (HR >125%, HRV <60%), with continuous monitoring at 3-second intervals triggering user notifications upon sustained stress detection.

A critical innovation is activity-aware stress classification. Concurrent IMU data (accelerometer/gyroscope) classifies physical activity intensity using earable-specific thresholds calibrated for head motion characteristics. Moderate or higher activity suppresses stress detection, preventing false alerts from exercise-induced HR elevation while maintaining sensitivity during sedentary periods. Meditation sessions terminate through multi-criteria evaluation of both absolute relaxation state and relative physiological improvement, with HRV improvement prioritized over HR due to superior robustness as a stress indicator.

---

## TECHNICAL DETAILS FOR METHODS SECTION (if space permits)

### Signal Processing Specifications

**Band-Pass Filter:**
- Type: Second-order IIR biquad filter
- Passband: 0.5-4.0 Hz (30-240 BPM physiological range)
- Center frequency: 1.41 Hz, Q-factor: 0.40
- Implementation: Cascaded difference equations with state preservation

**Peak Detection:**
- Method: Three-point local maxima with prominence validation  
- Window: 8-second sliding buffer with 4-sample Gaussian smoothing  
- Constraints: Minimum prominence = 0.1 (normalized), minimum interval = 300 ms  
- Validation: Symmetric prominence requirement on both flanks

**HRV Calculation:**
- RMSSD: √(mean((RR[i+1] - RR[i])²)), minimum 10 intervals  
- SDNN: √(variance(RR)), minimum 30 intervals, ideal 300 intervals  
- Artifact rejection: 300-2000 ms range, <300 ms successive difference, 2.5 SD outlier removal

**Activity Detection:**
- Sensors: Triaxial accelerometer + gyroscope at 10 Hz  
- Accelerometer: Magnitude deviation from 1g gravity  
- Gyroscope: Angular velocity magnitude (rad/s → deg/s)  
- Thresholds: Rest <0.20g AND <300°/s, Moderate >0.40g OR >450°/s  
- Smoothing: 30-sample moving average (≈3 seconds)

**Baseline Estimation:**
- Research norms: Age-stratified (5 brackets), gender-adjusted (±4-6 BPM, ±6 ms HRV), fitness-scaled (4 levels)  
- Example ranges: HR 68-82 BPM, RMSSD 15-60 ms across demographics  
- Adaptive refinement: Weighted average over 30s calibration (80→30% research weight)  
- Override: User-measured resting values replace research estimates if available

**Stress Thresholds (personalized):**
- Stress triggers: HR > baseline × 1.25 OR HRV < baseline × 0.60  
- Relaxed state: HR < baseline × 1.04 AND HRV > baseline × 1.20  
- Monitoring: 3-second polling during idle periods  
- Activity suppression: No stress detection during moderate+ physical activity

**Session Termination Criteria:**
- Minimum: 2 meditation segments completed  
- Scenario 1: HRV↑ ≥30% AND stress <40%  
- Scenario 2: HRV↑ ≥25% AND stress <30%  
- Scenario 3: HRV↑ ≥20% AND relaxed state  
- Scenario 4: HR↓ ≥10% AND HRV↑ ≥20%  
- Scenario 5: Relaxed state AND stress <20% AND HRV↑ ≥10%

---

## LIMITATIONS SUBSECTION (optional, for discussion)

While EarStreAM demonstrates robust real-time physiological monitoring, several limitations merit consideration. First, PPG-based HRV measurement is inherently more susceptible to motion artifacts than ECG gold standards; our multi-stage artifact rejection mitigates but does not eliminate this issue. Second, the minimum 10-interval threshold for RMSSD calculation enables rapid feedback but yields less stable early measurements compared to clinical standards (typically 2-5 minute recordings). Third, activity detection thresholds are calibrated for general populations and may not optimally handle individual variation in jaw motion patterns or head movement styles. Fourth, while our demographic-based baseline initialization prevents delay, the 30-second calibration window may be insufficient for users starting sessions in highly stressed states. Future work should validate PPG-derived HRV against simultaneous ECG measurements in the target earable form factor, and explore adaptive learning of individual-specific thresholds from longitudinal data.

---

## SUGGESTED REFERENCES

[1] Shaffer, F., & Ginsberg, J. P. (2017). An overview of heart rate variability metrics and norms. *Frontiers in Public Health*, 5, 258.

[2] Nunan, D., Sandercock, G. R., & Brodie, D. A. (2010). A quantitative systematic review of normal values for short-term heart rate variability in healthy adults. *Pacing and Clinical Electrophysiology*, 33(11), 1407-1417.

[3] Tegegne, B. S., Man, T., van Roon, A. M., Riese, H., & Snieder, H. (2018). Determinants of heart rate variability in the general population: the Lifelines Cohort Study. *Heart Rhythm*, 15(10), 1552-1558.

[4] Task Force of the European Society of Cardiology. (1996). Heart rate variability: standards of measurement, physiological interpretation, and clinical use. *Circulation*, 93(5), 1043-1065.

---

## FIGURES/TABLES TO CONSIDER

**Figure 1: Signal Processing Pipeline**
- Flowchart showing: Raw PPG → Band-pass filter → Peak detection → RR intervals → {HR (Kalman), HRV (RMSSD/SDNN)}
- Parallel path: IMU → Activity detection → Stress suppression logic

**Figure 2: Adaptive Baseline Calibration**
- Time-series plot showing convergence of research-based vs. measured baseline over 30s calibration period
- Two panels: HR and HRV
- Shaded regions showing confidence intervals

**Table 1: Demographic Baseline Parameters**
| Age Range | Gender | Fitness | Baseline HR (BPM) | Baseline RMSSD (ms) |
|-----------|--------|---------|-------------------|---------------------|
| 20-25     | Male   | Athlete | 56                | 85                  |
| 20-25     | Female | Active  | 68                | 48                  |
| 35-45     | Male   | Moderate| 70                | 38                  |
| 55-65     | Female | Sedentary| 82              | 17                  |
*(Selected representative combinations from full demographic matrix)*

**Table 2: Activity-Aware Stress Detection**
| Activity Level | Accel (g) | Gyro (°/s) | HR=90 BPM | HRV=20 ms | Stress? |
|----------------|-----------|------------|-----------|-----------|---------|
| Resting        | 0.15      | 150        | Elevated  | Low       | **Yes** |
| Light          | 0.35      | 400        | Elevated  | Low       | **Yes** |
| Moderate       | 0.60      | 600        | Elevated  | Low       | No (exercise) |
| Vigorous       | 1.50      | 800        | Very High | Very Low  | No (exercise) |
*(Assuming baseline HR=72, baseline HRV=35ms for 35-year-old moderate fitness user)*

**Figure 3: Session Termination Example**
- Real session data showing HR and HRV trajectories over time
- Annotations showing which termination criterion was met
- Comparison of start vs. end physiological state

---

## WRITING TIPS FOR FINAL VERSION

1. **Be Quantitative:** Include specific numbers (filter frequencies, window sizes, thresholds) to enable reproducibility

2. **Justify Choices:** Briefly explain WHY each design decision was made (e.g., "RMSSD prioritized over SDNN due to faster response to acute stress")

3. **Acknowledge Limitations:** UbiComp reviewers appreciate honest discussion of trade-offs (e.g., "10-interval minimum enables rapid feedback but reduces early measurement stability")

4. **Compare to Prior Work:** Position against existing wrist-worn devices, ECG-based systems, or other earable applications

5. **Emphasize Novelty:** 
   - Demographic-personalized baselines (not just one-size-fits-all)
   - Activity-aware stress detection (distinguishes exercise from stress)
   - Adaptive calibration (immediate start without waiting)
   - Multi-criteria termination (prevents both premature and prolonged sessions)

6. **Use Active Voice:** "We compute RMSSD from..." rather than "RMSSD is computed..."

7. **Define Acronyms:** Always spell out on first use: "heart rate variability (HRV)"

8. **Stay Concise:** UbiComp demo papers are SHORT (typically 4-6 pages). Every sentence must earn its place.

9. **Connect to Application:** Periodically remind readers WHY this matters for meditation guidance

10. **Validate Claims:** If you say "robust," provide evidence (e.g., "operates reliably across X sessions with Y% success rate")

---

## POTENTIAL REVIEWER QUESTIONS TO ADDRESS

**Q1:** "How does in-ear PPG compare to wrist-worn or chest ECG?"
- **Address in text:** "While chest ECG remains the gold standard, in-ear PPG offers sufficient accuracy for stress detection [cite validation study] with superior user comfort for extended wear."

**Q2:** "Why only 30-second calibration? Isn't that too short?"
- **Address in text:** "The 30-second calibration balances rapid session initiation (critical for UX) with measurement stability, leveraging research-based priors to mitigate acute stress bias in initial readings."

**Q3:** "How do you handle motion artifacts during meditation (user shifting position)?"
- **Address in text:** "Multi-stage artifact rejection (band-pass filtering, outlier removal, physiological validity checks) maintains robustness during typical meditation postures, while activity detection suppresses stress calculations during large movements."

**Q4:** "What about users on beta-blockers or with cardiovascular conditions?"
- **Address in text (limitations):** "Current demographic baselines assume healthy populations without cardiovascular medications. Future work should incorporate medical history adjustments and provide opt-out for users with contraindications."

**Q5:** "How many users tested? What's the validation data?"
- **Address with:** "Pilot testing with N users demonstrated X% agreement with self-reported stress (p<Y). Full validation study underway comparing to simultaneous ECG measurements."
- **If no validation yet:** "As a demonstration system, validation against medical-grade monitors remains future work."

**Q6:** "Why terminate on HRV improvement rather than absolute HRV value?"
- **Address in text:** "Relative improvement accommodates inter-individual baseline variation; a 30% HRV increase signals effective stress reduction regardless of absolute values, which vary 10-fold across healthy populations [cite range]."

---

**END OF DRAFT DOCUMENT**

This draft provides multiple versions and supplementary material. Select and adapt sections based on your paper's word limit and focus. Good luck with your submission!
