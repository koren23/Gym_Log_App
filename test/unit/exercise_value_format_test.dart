import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/utils/exercise_value_format.dart';
import 'package:gym_tracker/models/exercise_unit.dart';

void main() {
  test('kg formats with one decimal and a kg suffix', () {
    expect(formatExerciseValue(ExerciseUnit.kg, 80), '80.0kg');
  });

  test('bodyweight at 0 shows BW', () {
    expect(formatExerciseValue(ExerciseUnit.bodyweight, 0), 'BW');
  });

  test('bodyweight above 0 shows a + prefix', () {
    expect(formatExerciseValue(ExerciseUnit.bodyweight, 10), '+10.0kg');
  });

  test('time drops a trailing .0', () {
    expect(formatExerciseValue(ExerciseUnit.time, 45), '45sec');
  });

  test('time keeps a genuine fraction', () {
    expect(formatExerciseValue(ExerciseUnit.time, 12.5), '12.5sec');
  });

  test('custom uses the given label', () {
    expect(
      formatExerciseValue(ExerciseUnit.custom, 12, customLabel: 'floors'),
      '12 floors',
    );
  });

  test('custom falls back to "unit" when no label is given', () {
    expect(formatExerciseValue(ExerciseUnit.custom, 3), '3 unit');
  });
}
