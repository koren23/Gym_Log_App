import 'dart:convert';

import 'package:http/http.dart' as http;

/// Looks up a representative photo URL for [exerciseName] from the public,
/// keyless wger.de exercise database (CC BY-SA 4.0 — same source already
/// attributed for the bundled seed photos, see
/// `data/default_exercises_seed.dart`). Returns null on no match, a
/// non-200 response, or any network error — callers treat that as simply
/// "no photo available," never a crash.
Future<String?> fetchExercisePhotoUrl(String exerciseName) async {
  Future<String?> search(String param) async {
    final uri = Uri.https('wger.de', '/api/v2/exerciseinfo/', {
      param: exerciseName,
      'language__code': 'en',
      'format': 'json',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    for (final result in (body['results'] as List<dynamic>? ?? [])) {
      final images =
          (result as Map<String, dynamic>)['images'] as List<dynamic>?;
      if (images == null || images.isEmpty) continue;
      final main =
          images.firstWhere(
                (img) => (img as Map<String, dynamic>)['is_main'] == true,
                orElse: () => images.first,
              )
              as Map<String, dynamic>;
      final thumbnails = main['thumbnails'] as Map<String, dynamic>?;
      return (thumbnails?['medium'] as String?) ?? main['image'] as String?;
    }
    return null;
  }

  try {
    return await search('name__exact') ?? await search('name__search');
  } catch (_) {
    return null;
  }
}
