enum MeditationPromptPolicy {
  standard(
    includeProfileInformation: true,
    includePhysiologicalInformation: true,
  ),
  conferenceDemo(
    includeProfileInformation: false,
    includePhysiologicalInformation: false,
  );

  final bool includeProfileInformation;
  final bool includePhysiologicalInformation;

  const MeditationPromptPolicy({
    required this.includeProfileInformation,
    required this.includePhysiologicalInformation,
  });
}
