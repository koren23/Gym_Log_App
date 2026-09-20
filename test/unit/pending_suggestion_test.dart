import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/models/analysis_result.dart';
import 'package:gym_tracker/models/exercise.dart';
import 'package:gym_tracker/models/pending_suggestion.dart';
import 'package:gym_tracker/models/recent_suggestion_record.dart';

void main() {
  group('PendingSuggestion', () {
    test('round-trips a rep-range-for-set suggestion through JSON', () {
      final suggestion = PendingSuggestion(
        kind: SuggestionKind.changeRepRangeForSet,
        subjectExerciseName: 'Bench press',
        setIndex: 2,
        newRepRangeLow: 9,
        newRepRangeHigh: 11,
        acceptedAt: DateTime.utc(2026, 8, 14),
      );
      final restored = PendingSuggestion.fromJson(suggestion.toJson());
      expect(restored.kind, SuggestionKind.changeRepRangeForSet);
      expect(restored.subjectExerciseName, 'Bench press');
      expect(restored.setIndex, 2);
      expect(restored.newRepRangeLow, 9);
      expect(restored.newRepRangeHigh, 11);
      expect(restored.replacementExercise, isNull);
    });

    test('round-trips an exercise-swap suggestion, including the replacement', () {
      final suggestion = PendingSuggestion(
        kind: SuggestionKind.changeExercise,
        subjectExerciseName: 'Flat bench press',
        replacementExercise: const Exercise(
          name: 'Incline dumbbell press',
          muscleGroup: MuscleGroup.upperChest,
        ),
        acceptedAt: DateTime.utc(2026, 8, 14),
      );
      final restored = PendingSuggestion.fromJson(suggestion.toJson());
      expect(restored.replacementExercise?.name, 'Incline dumbbell press');
      expect(restored.replacementExercise?.muscleGroup, MuscleGroup.upperChest);
    });
  });

  group('RecentSuggestionRecord', () {
    test('round-trips through JSON, including a null detail', () {
      final record = RecentSuggestionRecord(
        kind: SuggestionKind.deload,
        subjectName: 'Deadlift',
        shownAt: DateTime.utc(2026, 8, 14),
      );
      final restored = RecentSuggestionRecord.fromJson(record.toJson());
      expect(restored.kind, SuggestionKind.deload);
      expect(restored.subjectName, 'Deadlift');
      expect(restored.detail, isNull);
      expect(restored.shownAt, DateTime.utc(2026, 8, 14));
    });

    test('round-trips a non-null detail (e.g. the swapped-in exercise name)', () {
      final record = RecentSuggestionRecord(
        kind: SuggestionKind.changeExercise,
        subjectName: 'Flat bench press',
        detail: 'Incline dumbbell press',
        shownAt: DateTime.utc(2026, 8, 14),
      );
      final restored = RecentSuggestionRecord.fromJson(record.toJson());
      expect(restored.detail, 'Incline dumbbell press');
    });
  });
}
