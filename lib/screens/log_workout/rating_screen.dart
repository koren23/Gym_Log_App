import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/exercise_note.dart';
import '../../models/rating_relevance.dart';
import '../../models/workout_visit.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../widgets/star_rating_input.dart';
import 'post_save_insight_screen.dart';

class RatingScreen extends ConsumerStatefulWidget {
  const RatingScreen({super.key, required this.visit, this.notes = const []});

  final WorkoutVisit visit;

  /// Per-exercise/per-set notes collected while logging, saved to the
  /// separate `Notes` tab right after [visit] itself is successfully saved.
  final List<ExerciseNote> notes;

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  double _rating = 3.0;
  RatingRelevance _ratingRelevance = RatingRelevance.normal;
  bool _saving = false;

  Future<void> _submit() async {
    setState(() => _saving = true);
    final ratedVisit = widget.visit.copyWith(
      rating: _rating,
      ratingRelevance: _ratingRelevance,
    );
    final (outcome, _) = await ref
        .read(snapshotProvider.notifier)
        .logVisit(ratedVisit);

    var notesFailed = false;
    if (widget.notes.isNotEmpty) {
      final notesOk = await ref
          .read(snapshotProvider.notifier)
          .saveNotesForVisit(ratedVisit.visitId, widget.notes);
      notesFailed = !notesOk;
    }

    // The visit is now either synced or safely queued for retry — either
    // way the log-workout draft it came from is no longer needed.
    await ref.read(appSettingsServiceProvider).clearWorkoutDraft();

    if (!mounted) return;
    setState(() => _saving = false);

    if (outcome == SaveOutcome.queuedOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved locally — will sync when back online.'),
        ),
      );
    } else if (notesFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Workout saved, but the notes couldn't be saved — check your connection.",
          ),
        ),
      );
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PostSaveInsightScreen(visit: ratedVisit),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rate this workout')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'How was this workout?',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              StarRatingInput(
                value: _rating,
                onChanged: (v) => setState(() => _rating = v),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Feeling sick / not 100%?'),
                subtitle: const Text(
                  "Won't count against your progress trends.",
                ),
                value: _ratingRelevance == RatingRelevance.unrelated,
                onChanged: (checked) => setState(() {
                  _ratingRelevance = (checked ?? false)
                      ? RatingRelevance.unrelated
                      : RatingRelevance.normal;
                }),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
