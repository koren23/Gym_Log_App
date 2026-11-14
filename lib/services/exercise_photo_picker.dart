import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Picks a photo from the gallery and copies it into this app's own
/// documents directory (so it survives independent of wherever the user
/// picked it from), returning the new file's path for storage as an
/// [Exercise.photoAssetKey]. Not supported on web — there's no app-private
/// filesystem to copy into, so callers should hide the picker entry point
/// there (bundled seed photos still display fine via [ExercisePhoto]).
Future<String?> pickAndStoreExercisePhoto() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;

  final dir = await getApplicationDocumentsDirectory();
  final photosDir = Directory(p.join(dir.path, 'exercise_photos'));
  await photosDir.create(recursive: true);

  final ext = p.extension(picked.path);
  final destPath = p.join(
    photosDir.path,
    '${DateTime.now().microsecondsSinceEpoch}$ext',
  );
  await File(picked.path).copy(destPath);
  return destPath;
}
