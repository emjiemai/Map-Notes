class Visit {
  final String id;
  final String placeId;
  final String userId;
  final String? authorName;
  final String? comment;
  final List<String> photoUrls;
  final DateTime createdAt;

  Visit({
    required this.id,
    required this.placeId,
    required this.userId,
    required this.authorName,
    required this.comment,
    required this.photoUrls,
    required this.createdAt,
  });

  // Author names are resolved separately (VisitsRepository fetches them in
  // one batched query and passes the lookup in here) rather than via a
  // PostgREST embed — `visits` has no direct foreign key to `profiles`
  // (both just happen to reference auth.users), which made that embed
  // resolve inconsistently.
  factory Visit.fromMap(Map<String, dynamic> map, {Map<String, String>? profileNames}) {
    final userId = map['user_id'] as String;
    return Visit(
      id: map['id'] as String,
      placeId: map['place_id'] as String,
      userId: userId,
      authorName: profileNames?[userId],
      comment: map['comment'] as String?,
      photoUrls: ((map['photo_urls'] as List?) ?? const []).cast<String>(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
