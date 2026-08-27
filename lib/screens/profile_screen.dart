import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/group.dart';
import '../models/place.dart';
import '../models/visit.dart';
import '../services/visits_repository.dart';
import '../widgets/category_style.dart';
import '../widgets/user_avatar.dart';
import 'place_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.repository});

  final VisitsRepository repository;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Group> _groups = [];
  List<(Visit, Place)> _myPins = [];
  String? _myName;

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _loadMyPins();
    _loadMyName();
  }

  Future<void> _loadMyName() async {
    final name = await widget.repository.fetchMyName();
    if (mounted) setState(() => _myName = name);
  }

  Future<void> _loadGroups() async {
    final groups = await widget.repository.fetchGroups();
    if (mounted) setState(() => _groups = groups);
  }

  Future<void> _loadMyPins() async {
    final pins = await widget.repository.fetchMyVisits();
    if (mounted) setState(() => _myPins = pins);
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New team'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Team name')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await widget.repository.createGroup(name);
    _loadGroups();
  }

  Future<void> _openDeleteGroupDialog(Group group) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _DeleteGroupDialog(group: group, repository: widget.repository),
    );
    _loadGroups();
  }

  Future<void> _deletePin(Visit visit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this pin?'),
        content: const Text("This removes your note here. Can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteVisit(visit.id);
    _loadMyPins();
  }

  void _openPlace(Place place) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PlaceDetailScreen(place: place, repository: widget.repository)))
        .then((_) => _loadMyPins());
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: UserAvatar(userId: user?.id ?? '', radius: 40)),
          const SizedBox(height: 12),
          Text(
            _myName ?? '...',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Your teams', style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(onPressed: _createGroup, icon: const Icon(Icons.add), label: const Text('New')),
            ],
          ),
          for (final group in _groups)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.groups_outlined),
              title: Text(group.name),
              subtitle: group.isDefault ? const Text('Shared team — can\'t be deleted') : null,
              trailing: group.isDefault
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Delete team',
                      onPressed: () => _openDeleteGroupDialog(group),
                    ),
            ),
          const SizedBox(height: 24),
          Text('Your pinned places (${_myPins.length})', style: Theme.of(context).textTheme.titleMedium),
          if (_myPins.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Places you pin will show up here.', style: TextStyle(color: Colors.grey)),
            ),
          for (final (visit, place) in _myPins)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(styleFor(place.category).icon, color: styleFor(place.category).color),
              title: Text(place.name),
              subtitle: Text(visit.comment ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(DateFormat.MMMd().format(visit.createdAt), style: Theme.of(context).textTheme.bodySmall),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Delete pin',
                    onPressed: () => _deletePin(visit),
                  ),
                ],
              ),
              onTap: () => _openPlace(place),
            ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

/// Deleting a team needs every *current* member to agree — this dialog
/// shows live vote progress and lets the viewer cast or retract their own
/// vote. The actual deletion happens server-side once the count matches
/// membership, so this never deletes anything itself.
class _DeleteGroupDialog extends StatefulWidget {
  const _DeleteGroupDialog({required this.group, required this.repository});

  final Group group;
  final VisitsRepository repository;

  @override
  State<_DeleteGroupDialog> createState() => _DeleteGroupDialogState();
}

class _DeleteGroupDialogState extends State<_DeleteGroupDialog> {
  ({int memberCount, int voteCount, bool hasVoted})? _status;
  bool _busy = false;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await widget.repository.fetchGroupDeleteStatus(widget.group.id);
    if (mounted) setState(() => _status = status);
  }

  Future<void> _toggleVote() async {
    setState(() => _busy = true);
    try {
      if (_status!.hasVoted) {
        await widget.repository.retractDeleteVote(widget.group.id);
        await _refresh();
      } else {
        await widget.repository.voteToDeleteGroup(widget.group.id);
        // The last vote triggers server-side deletion, which cascades away
        // the very membership/vote rows a status query would read next —
        // check existence directly rather than trusting a re-fetched count.
        final stillExists = await widget.repository.groupExists(widget.group.id);
        if (stillExists) {
          await _refresh();
        } else {
          setState(() => _deleted = true);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return AlertDialog(
      title: Text('Delete "${widget.group.name}"?'),
      content: _deleted
          ? const Text('Everyone agreed — this team was just deleted.')
          : status == null
              ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Every current member has to agree before this team is actually deleted.'),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: status.memberCount == 0 ? 0 : status.voteCount / status.memberCount,
                    ),
                    const SizedBox(height: 8),
                    Text('${status.voteCount} of ${status.memberCount} member(s) agreed'),
                  ],
                ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        if (status != null && !_deleted)
          FilledButton(
            onPressed: _busy ? null : _toggleVote,
            child: Text(_busy ? 'Please wait...' : (status.hasVoted ? 'Retract my vote' : 'I agree to delete')),
          ),
      ],
    );
  }
}
