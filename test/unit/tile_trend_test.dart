import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/analysis/tile_trend.dart';
import 'package:gym_tracker/models/analysis_result.dart';

AnalysisFinding _finding({
  required TrendDirection weightTrend,
  required bool isPlateaued,
}) {
  return AnalysisFinding(
    subjectName: 'Bench press',
    weightTrend: weightTrend,
    ratingTrend: TrendDirection.unknown,
    isPlateaued: isPlateaued,
    repRangeChanged: false,
    message: 'irrelevant',
  );
}

void main() {
  test('null finding classifies as unknown', () {
    expect(classifyTrend(null), TileTrend.unknown);
  });

  test('trending up and not plateaued classifies as improving', () {
    final finding = _finding(
      weightTrend: TrendDirection.up,
      isPlateaued: false,
    );
    expect(classifyTrend(finding), TileTrend.improving);
  });

  test('plateaued classifies as stuck, even if weight trend reads up', () {
    final finding = _finding(
      weightTrend: TrendDirection.up,
      isPlateaued: true,
    );
    expect(classifyTrend(finding), TileTrend.stuck);
  });

  test('flat and not plateaued classifies as steady', () {
    final finding = _finding(
      weightTrend: TrendDirection.flat,
      isPlateaued: false,
    );
    expect(classifyTrend(finding), TileTrend.steady);
  });

  test('down and not plateaued classifies as steady, not improving', () {
    final finding = _finding(
      weightTrend: TrendDirection.down,
      isPlateaued: false,
    );
    expect(classifyTrend(finding), TileTrend.steady);
  });
}
