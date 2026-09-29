import 'dart:async';

import 'package:flutter/material.dart';

/// Deliberate-friction delete flow: a 5s cooldown, then typing the
/// exercise's exact name, then a final yes/no confirmation. Returns true
/// only if the user makes it through all three steps.
Future<bool> showDeleteExerciseConfirmation(
  BuildContext context,
  String exerciseName,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _DeleteExerciseDialog(exerciseName: exerciseName),
  );
  if (confirmed != true || !context.mounted) return false;
  return _showFinalConfirmation(context, exerciseName);
}

Future<bool> _showFinalConfirmation(
  BuildContext context,
  String exerciseName,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("Delete '$exerciseName'?"),
      content: const Text(
        'This removes it from this year\'s sheet and the Exercises tab. '
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _DeleteExerciseDialog extends StatefulWidget {
  const _DeleteExerciseDialog({required this.exerciseName});

  final String exerciseName;

  @override
  State<_DeleteExerciseDialog> createState() => _DeleteExerciseDialogState();
}

class _DeleteExerciseDialogState extends State<_DeleteExerciseDialog> {
  static const _cooldownSeconds = 5;
  int _secondsLeft = _cooldownSeconds;
  Timer? _timer;
  final _typedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) _timer?.cancel();
    });
    _typedController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _typedController.dispose();
    super.dispose();
  }

  bool get _cooldownDone => _secondsLeft <= 0;
  bool get _nameMatches => _typedController.text == widget.exerciseName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete exercise'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "This will delete '${widget.exerciseName}'. This cannot be undone.",
          ),
          const SizedBox(height: 16),
          if (!_cooldownDone)
            Text(
              'Wait $_secondsLeft second${_secondsLeft == 1 ? '' : 's'}...',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            TextField(
              controller: _typedController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: "Type '${widget.exerciseName}' to confirm",
                isDense: true,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _cooldownDone && _nameMatches
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
