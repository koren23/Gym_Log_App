import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/models/analysis_result.dart';
import 'package:gym_tracker/models/body_weight_entry.dart';
import 'package:gym_tracker/providers/analysis_providers.dart';

BodyWeightEntry _entry(int daysAgo, double weightKg) => BodyWeightEntry(
  date: DateTime.now().subtract(Duration(days: daysAgo)),
  weightKg: weightKg,
  rowIndex: 0,
);

void main() {
  test('returns unknown with fewer than 2 recent entries', () {
    expect(bodyWeightTrend(const []), TrendDirection.unknown);
    expect(bodyWeightTrend([_entry(1, 80)]), TrendDirection.unknown);
  });

  test('detects a clear downward trend (losing weight)', () {
    final entries = [
      _entry(50, 82),
      _entry(40, 81.5),
      _entry(30, 81),
      _entry(20, 79),
      _entry(10, 78.5),
      _entry(1, 78),
    ];
    expect(bodyWeightTrend(entries), TrendDirection.down);
  });

  test('detects a clear upward trend (gaining weight)', () {
    final entries = [
      _entry(50, 75),
      _entry(40, 75.5),
      _entry(30, 76),
      _entry(20, 78),
      _entry(10, 78.5),
      _entry(1, 79),
    ];
    expect(bodyWeightTrend(entries), TrendDirection.up);
  });

  test('reads as flat within the noise threshold', () {
    final entries = [
      _entry(50, 80.0),
      _entry(40, 80.2),
      _entry(30, 79.9),
      _entry(20, 80.1),
      _entry(10, 80.0),
      _entry(1, 80.1),
    ];
    expect(bodyWeightTrend(entries), TrendDirection.flat);
  });

  test('ignores entries outside the scan window', () {
    final entries = [
      _entry(400, 100), // far outside the ~8-week window — should be ignored
      _entry(10, 80),
      _entry(1, 79.5),
    ];
    // Only the two recent, close-together entries should count — if the
    // 400-days-ago entry were included it would swamp the average with a
    // huge apparent drop.
    expect(bodyWeightTrend(entries), TrendDirection.flat);
  });
}
