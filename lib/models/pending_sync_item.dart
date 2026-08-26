enum PendingSyncPayloadType { workoutVisit, rating, bodyWeight, workoutDay }

class PendingSyncItem {
  const PendingSyncItem({
    required this.id,
    required this.createdAt,
    required this.payloadType,
    required this.serializedPayload,
    this.retryCount = 0,
    this.lastError,
  });

  final String id;
  final DateTime createdAt;
  final PendingSyncPayloadType payloadType;

  /// JSON-encoded payload specific to [payloadType].
  final String serializedPayload;
  final int retryCount;
  final String? lastError;

  PendingSyncItem copyWith({int? retryCount, String? lastError}) =>
      PendingSyncItem(
        id: id,
        createdAt: createdAt,
        payloadType: payloadType,
        serializedPayload: serializedPayload,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'payloadType': payloadType.name,
    'serializedPayload': serializedPayload,
    'retryCount': retryCount,
    'lastError': lastError,
  };

  factory PendingSyncItem.fromJson(Map<String, dynamic> json) =>
      PendingSyncItem(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        payloadType: PendingSyncPayloadType.values.firstWhere(
          (t) => t.name == json['payloadType'],
        ),
        serializedPayload: json['serializedPayload'] as String,
        retryCount: json['retryCount'] as int? ?? 0,
        lastError: json['lastError'] as String?,
      );
}
