import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/models/set_feedback.dart';

void main() {
  group('setFeedbackFromJson', () {
    test('parses up', () {
      expect(setFeedbackFromJson('up'), SetFeedback.up);
    });

    test('parses down', () {
      expect(setFeedbackFromJson('down'), SetFeedback.down);
    });

    test('null defaults to none', () {
      expect(setFeedbackFromJson(null), SetFeedback.none);
    });

    test('unrecognized string defaults to none', () {
      expect(setFeedbackFromJson('bogus'), SetFeedback.none);
    });

    test('empty string defaults to none', () {
      expect(setFeedbackFromJson(''), SetFeedback.none);
    });
  });
}
