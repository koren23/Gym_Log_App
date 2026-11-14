import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Renders an exercise's [photoAssetKey] — a bundled asset path (seeded
/// starter exercises, e.g. `assets/exercise_photos/bench_press.jpg`), an
/// on-device file path (user-picked via Settings), or an `http(s)://` URL
/// (auto-fetched from the wger.de exercise API — see
/// `services/exercise_photo_api.dart`). Bundled keys always start with
/// `assets/` so the cases can be told apart without hitting disk; a
/// leftover file path to a since-deleted file, or a URL that fails to
/// load, falls back to [placeholder].
class ExercisePhoto extends StatelessWidget {
  const ExercisePhoto({
    super.key,
    required this.photoAssetKey,
    this.size = 48,
    this.borderRadius = 8,
  });

  final String? photoAssetKey;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final key = photoAssetKey;
    final child = key == null
        ? _placeholder(context)
        : key.startsWith('assets/')
        ? Image.asset(
            key,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(context),
          )
        : key.startsWith('http://') || key.startsWith('https://')
        ? Image.network(
            key,
            width: size,
            height: size,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _placeholder(context),
            errorBuilder: (_, __, ___) => _placeholder(context),
          )
        : (kIsWeb
              ? _placeholder(context)
              : Image.file(
                  File(key),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(context),
                ));
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    alignment: Alignment.center,
    child: Icon(
      Icons.fitness_center,
      size: size * 0.5,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
