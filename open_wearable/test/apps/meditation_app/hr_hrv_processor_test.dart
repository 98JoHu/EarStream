import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/apps/meditation_app/model/hr_hrv_processor.dart';

void main() {
  group('HrHrvProcessor.hrvMinimumWindow', () {
    // The setter converts a Duration into sensor ticks via timestampExponent,
    // so it must round-trip for every exponent the sensors actually report.
    // Getting this wrong silently changes how long RMSSD stays null.
    for (final exponent in const [-3, -6]) {
      test('round-trips through tick conversion at exponent $exponent', () {
        final processor = HrHrvProcessor(
          sampleFreq: 200,
          timestampExponent: exponent,
        );
        addTearDown(processor.dispose);

        expect(processor.hrvMinimumWindow, const Duration(seconds: 60));

        processor.hrvMinimumWindow = const Duration(seconds: 15);
        expect(processor.hrvMinimumWindow, const Duration(seconds: 15));
      });
    }
  });
}
