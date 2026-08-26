import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/result.dart';
import '../../models/pending_sync_item.dart';
import '../../models/rating_relevance.dart';
import '../../models/workout_day_def.dart';
import '../../models/workout_visit.dart';
import '../../models/year_sheet_data.dart';
import '../sheets/sheets_repository.dart';

/// Resolves the fresh write context (matrix tab data + its grid ID + meta
/// tab name) needed to replay a queued workout-visit write for [year].
/// Must re-read current sheet state (not a stale cache) so retries can
/// de-dupe week-column creation against what's actually on the sheet now.
typedef YearContextResolver =
    Future<Result<YearWriteContext>> Function(int year);

class YearWriteContext {
  const YearWriteContext({
    required this.yearData,
    required this.sheetGridId,
    required this.metaTabName,
  });

  final YearSheetData yearData;
  final int sheetGridId;
  final String metaTabName;
}

/// Local, offline-durable queue of writes that failed to reach the sheet.
/// No background service, no exponential backoff — just an honest local
/// record replayed on app resume / manual retry, in original order.
class PendingSyncQueue {
  PendingSyncQueue(this._prefs);

  final SharedPreferences _prefs;
  static const _kKey = 'pending_sync_queue_v1';
  static const _uuid = Uuid();

  List<PendingSyncItem> getAll() {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => PendingSyncItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveAll(List<PendingSyncItem> items) async {
    await _prefs.setString(
      _kKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> enqueueWorkoutVisit(WorkoutVisit visit) =>
      _enqueue(PendingSyncPayloadType.workoutVisit, jsonEncode(visit.toJson()));

  Future<void> enqueueRating({
    required String metaTabName,
    required int metaRowIndex,
    required double rating,
    RatingRelevance? ratingRelevance,
  }) => _enqueue(
    PendingSyncPayloadType.rating,
    jsonEncode({
      'metaTabName': metaTabName,
      'metaRowIndex': metaRowIndex,
      'rating': rating,
      if (ratingRelevance != null) 'ratingRelevance': ratingRelevance.name,
    }),
  );

  Future<void> enqueueBodyWeight({
    required DateTime date,
    required double weightKg,
  }) => _enqueue(
    PendingSyncPayloadType.bodyWeight,
    jsonEncode({'date': date.toIso8601String(), 'weightKg': weightKg}),
  );

  Future<void> enqueueWorkoutDay(WorkoutDayDef def) =>
      _enqueue(PendingSyncPayloadType.workoutDay, jsonEncode(def.toJson()));

  /// Removes any still-queued "add this workout day" item for [id] — used
  /// when the user deletes a day before its add ever synced, so it doesn't
  /// get resurrected by a later retry.
  Future<void> cancelPendingWorkoutDay(String id) async {
    final items = getAll().where((item) {
      if (item.payloadType != PendingSyncPayloadType.workoutDay) return true;
      final json = jsonDecode(item.serializedPayload) as Map<String, dynamic>;
      return json['id'] != id;
    }).toList();
    await _saveAll(items);
  }

  Future<void> _enqueue(PendingSyncPayloadType type, String payload) async {
    final items = getAll()
      ..add(
        PendingSyncItem(
          id: _uuid.v4(),
          createdAt: DateTime.now(),
          payloadType: type,
          serializedPayload: payload,
        ),
      );
    await _saveAll(items);
  }

  /// Replays queued items in original order. Stops at the first failure
  /// (later items may depend on an earlier one's effect, e.g. a week
  /// column it creates) and leaves the remaining queue untouched. Returns
  /// the number of items successfully synced.
  Future<int> retryAll({
    required SheetsRepository repository,
    required YearContextResolver resolveYearContext,
  }) async {
    final items = getAll();
    var syncedCount = 0;

    for (final item in items) {
      final result = await _replayOne(
        item,
        repository: repository,
        resolveYearContext: resolveYearContext,
      );
      final remaining = getAll();

      if (result.isOk) {
        await _saveAll(remaining.where((e) => e.id != item.id).toList());
        syncedCount++;
        continue;
      }

      final errorText = result.when(
        ok: (_) => null,
        err: (error, _) => error.toString(),
      );
      final updated = remaining
          .map(
            (e) => e.id == item.id
                ? e.copyWith(retryCount: e.retryCount + 1, lastError: errorText)
                : e,
          )
          .toList();
      await _saveAll(updated);
      break;
    }

    return syncedCount;
  }

  Future<Result<void>> _replayOne(
    PendingSyncItem item, {
    required SheetsRepository repository,
    required YearContextResolver resolveYearContext,
  }) async {
    switch (item.payloadType) {
      case PendingSyncPayloadType.workoutVisit:
        final visit = WorkoutVisit.fromJson(
          jsonDecode(item.serializedPayload) as Map<String, dynamic>,
        );
        final contextResult = await resolveYearContext(visit.isoYear);
        if (contextResult is Err<YearWriteContext>) {
          return Result.err(contextResult.error, contextResult.stackTrace);
        }
        final context = (contextResult as Ok<YearWriteContext>).value;
        final writeResult = await repository.writeVisit(
          yearData: context.yearData,
          sheetGridId: context.sheetGridId,
          visit: visit,
          metaTabName: context.metaTabName,
        );
        if (writeResult is Err<int>) {
          return Result.err(writeResult.error, writeResult.stackTrace);
        }
        return const Result.ok(null);

      case PendingSyncPayloadType.rating:
        final json = jsonDecode(item.serializedPayload) as Map<String, dynamic>;
        final metaTabName = json['metaTabName'] as String;
        final metaRowIndex = json['metaRowIndex'] as int;
        final ratingResult = await repository.updateRating(
          metaTabName: metaTabName,
          metaRowIndex: metaRowIndex,
          rating: (json['rating'] as num).toDouble(),
        );
        if (ratingResult.isErr) return ratingResult;
        final relevanceName = json['ratingRelevance'] as String?;
        if (relevanceName == null) return const Result.ok(null);
        return repository.updateRatingRelevance(
          metaTabName: metaTabName,
          metaRowIndex: metaRowIndex,
          value: RatingRelevance.values.firstWhere(
            (r) => r.name == relevanceName,
            orElse: () => RatingRelevance.normal,
          ),
        );

      case PendingSyncPayloadType.bodyWeight:
        final json = jsonDecode(item.serializedPayload) as Map<String, dynamic>;
        return repository.appendBodyWeight(
          date: DateTime.parse(json['date'] as String),
          weightKg: (json['weightKg'] as num).toDouble(),
        );

      case PendingSyncPayloadType.workoutDay:
        final json = jsonDecode(item.serializedPayload) as Map<String, dynamic>;
        return repository.appendWorkoutDay(WorkoutDayDef.fromJson(json));
    }
  }
}
