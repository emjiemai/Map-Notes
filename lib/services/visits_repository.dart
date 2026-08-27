import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/group.dart';
import '../models/place.dart';
import '../models/visit.dart';

/// Single entry point for all place/visit/group data access. Keeping this in
/// one place means the dedupe rule (log_visit) is the only way a *new pin*
/// gets created — screens never insert into `places` directly.
class VisitsRepository {
  VisitsRepository(this._client);

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<String?> fetchMyName() async {
    final userId = currentUserId;
    if (userId == null) return null;
    final row = await _client.from('profiles').select('full_name').eq('id', userId).maybeSingle();
    return row?['full_name'] as String?;
  }

  Future<List<Place>> fetchPlaces() async {
    final rows = await _client.from('places').select().order('created_at');
    return (rows as List).map((row) => Place.fromMap(row as Map<String, dynamic>)).toList();
  }

  Future<List<Visit>> fetchVisitsForPlace(String placeId) async {
    final rows = await _client.from('visits').select().eq('place_id', placeId).order('created_at');
    final list = (rows as List).cast<Map<String, dynamic>>();
    final names = await _fetchProfileNames(list.map((row) => row['user_id'] as String));
    return list.map((row) => Visit.fromMap(row, profileNames: names)).toList();
  }

  /// Most recent visits across all places, newest first — powers the
  /// pinned-places strip on the map screen.
  Future<List<(Visit, Place)>> fetchRecentActivity({int limit = 5}) async {
    final rows = await _client
        .from('visits')
        .select('*, places(*)')
        .order('created_at', ascending: false)
        .limit(limit);
    return _mapVisitPlaceRows(rows);
  }

  /// The current user's own pins, newest first — powers "your pinned
  /// places" on the profile screen.
  Future<List<(Visit, Place)>> fetchMyVisits() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('visits')
        .select('*, places(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return _mapVisitPlaceRows(rows);
  }

  Future<List<(Visit, Place)>> _mapVisitPlaceRows(List rows) async {
    final list = rows.cast<Map<String, dynamic>>();
    final names = await _fetchProfileNames(list.map((row) => row['user_id'] as String));
    return list.map((row) {
      final place = Place.fromMap(row['places'] as Map<String, dynamic>);
      return (Visit.fromMap(row, profileNames: names), place);
    }).toList();
  }

  // `visits` has no direct foreign key to `profiles` — both just reference
  // auth.users — so PostgREST can't reliably embed `profiles(full_name)`
  // under `visits` (it 400s, inconsistently, once a second embed like
  // `places(*)` is also requested). Resolving names as their own batched
  // query sidesteps that entirely.
  Future<Map<String, String>> _fetchProfileNames(Iterable<String> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await _client.from('profiles').select('id, full_name').inFilter('id', ids);
    return {
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        row['id'] as String: (row['full_name'] as String?) ?? 'Unknown rep',
    };
  }

  /// Most recent visitor's user id per place — used to show a rep's avatar
  /// on their pin so teammates who've never met can recognize each other.
  Future<Map<String, String>> fetchLatestVisitorByPlace() async {
    final rows = await _client
        .from('visits')
        .select('place_id, user_id, created_at')
        .order('created_at', ascending: false)
        .limit(500);
    final map = <String, String>{};
    for (final row in rows as List) {
      final placeId = row['place_id'] as String;
      map.putIfAbsent(placeId, () => row['user_id'] as String);
    }
    return map;
  }

  Future<List<Group>> fetchGroups() async {
    final rows = await _client.from('groups').select().order('created_at');
    return (rows as List).map((row) => Group.fromMap(row as Map<String, dynamic>)).toList();
  }

  Future<Group> createGroup(String name) async {
    final row = await _client.from('groups').insert({'name': name}).select().single();
    return Group.fromMap(row);
  }

  /// Uploads photos to the `visit-photos` bucket and returns their public
  /// URLs, in order. Skips silently past this call entirely if `files` is
  /// empty — photos stay optional.
  Future<List<String>> uploadPhotos(List<File> files) async {
    final urls = <String>[];
    final userId = _client.auth.currentUser!.id;
    for (final file in files) {
      final path = '$userId/${DateTime.now().microsecondsSinceEpoch}_${urls.length}.jpg';
      await _client.storage.from('visit-photos').upload(path, file);
      urls.add(_client.storage.from('visit-photos').getPublicUrl(path));
    }
    return urls;
  }

  /// Records a rep's visit at (lat, lng). The `log_visit` Postgres function
  /// finds a nearby existing place (within ~50m) and attaches the visit to
  /// it instead of creating a duplicate; only a genuinely new location
  /// creates a new place row.
  ///
  /// Returns the place id the visit was attached to.
  Future<String> logVisit({
    required double lat,
    required double lng,
    required String name,
    String? address,
    String? comment,
    PlaceCategory category = PlaceCategory.other,
    String? groupId,
    List<String> photoUrls = const [],
  }) async {
    final result = await _client.rpc('log_visit', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_name': name,
      'p_address': address,
      'p_comment': comment,
      'p_category': category.name,
      'p_group_id': groupId,
      'p_photo_urls': photoUrls,
    });
    final row = (result as List).first as Map<String, dynamic>;
    return row['place_id'] as String;
  }

  /// Adds a follow-up note to a place that's already on the map — used by
  /// the comment box on the place detail screen. Skips the dedupe search
  /// entirely since the place is already known.
  Future<void> addComment({required String placeId, required String comment}) async {
    await _client.from('visits').insert({
      'place_id': placeId,
      'user_id': _client.auth.currentUser!.id,
      'comment': comment,
    });
  }

  /// Deletes a rep's own mistaken pin. RLS only allows deleting your own
  /// visits; a DB trigger removes the place too once its last visit is gone.
  Future<void> deleteVisit(String visitId) async {
    await _client.from('visits').delete().eq('id', visitId);
  }

  /// Casts the current user's vote to delete a team. Once every current
  /// member has voted, a DB trigger deletes the team automatically — this
  /// call just records one vote, it never deletes anything itself.
  Future<void> voteToDeleteGroup(String groupId) async {
    await _client.from('group_delete_votes').insert({
      'group_id': groupId,
      'user_id': _client.auth.currentUser!.id,
    });
  }

  /// True until the last member's vote lands and the server-side trigger
  /// deletes the group — used to confirm to the voter that consensus was
  /// actually reached, since the row counts a status query would read
  /// afterward are cascade-deleted along with the group itself.
  Future<bool> groupExists(String groupId) async {
    final rows = await _client.from('groups').select('id').eq('id', groupId).limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<void> retractDeleteVote(String groupId) async {
    await _client
        .from('group_delete_votes')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', _client.auth.currentUser!.id);
  }

  /// How many members a team has, how many have voted to delete it, and
  /// whether the current user is one of them — powers the "2/5 agreed"
  /// progress shown before a team is actually deleted.
  Future<({int memberCount, int voteCount, bool hasVoted})> fetchGroupDeleteStatus(String groupId) async {
    final userId = _client.auth.currentUser!.id;
    final members = await _client.from('group_members').select('user_id').eq('group_id', groupId);
    final votes = await _client.from('group_delete_votes').select('user_id').eq('group_id', groupId);
    final voterIds = (votes as List).map((row) => row['user_id'] as String).toSet();
    return (
      memberCount: (members as List).length,
      voteCount: voterIds.length,
      hasVoted: voterIds.contains(userId),
    );
  }
}
