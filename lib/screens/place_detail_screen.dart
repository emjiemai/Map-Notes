import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/place.dart';
import '../models/visit.dart';
import '../services/visits_repository.dart';
import '../utils/date_format.dart';
import '../widgets/category_style.dart';
import '../widgets/user_avatar.dart';

class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen(
      {super.key, required this.place, required this.repository});

  final Place place;
  final VisitsRepository repository;

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  List<Visit> _visits = [];
  bool _loading = true;
  double? _distanceMiles;
  final _commentController = TextEditingController();
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadDistance();
  }

  Future<void> _load() async {
    final visits = await widget.repository.fetchVisitsForPlace(widget.place.id);
    if (!mounted) return;
    setState(() {
      _visits = visits;
      _loading = false;
    });
  }

  Future<void> _loadDistance() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final meters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        widget.place.lat,
        widget.place.lng,
      );
      if (!mounted) return;
      setState(() => _distanceMiles = meters / 1609.34);
    } catch (_) {
      // Distance badge is a nice-to-have — skip silently if location isn't available.
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    try {
      await widget.repository
          .addComment(placeId: widget.place.id, comment: text);
      _commentController.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _deleteVisit(Visit visit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this pin?'),
        content: const Text("This removes your note here. Can't be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.repository.deleteVisit(visit.id);
    if (!mounted) return;

    final remaining =
        await widget.repository.fetchVisitsForPlace(widget.place.id);
    if (!mounted) return;
    if (remaining.isEmpty) {
      // last visit deleted — the place itself is gone (server-side cleanup), leave the screen
      Navigator.of(context).pop();
      return;
    }
    setState(() => _visits = remaining);
  }

  @override
  Widget build(BuildContext context) {
    final style = styleFor(widget.place.category);
    final photos = _visits.expand((v) => v.photoUrls).toList();
    final headline = _visits.isNotEmpty ? _visits.first : null;
    final comments = _visits.length > 1 ? _visits.sublist(1) : const <Visit>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.place.name),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _load)
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        if (photos.isNotEmpty)
                          SizedBox(
                            height: 220,
                            child: PageView(children: [
                              for (final url in photos)
                                Image.network(url, fit: BoxFit.cover),
                            ]),
                          )
                        else
                          Container(
                            height: 100,
                            color: style.color.withValues(alpha: 0.12),
                            alignment: Alignment.center,
                            child:
                                Icon(style.icon, size: 40, color: style.color),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Chip(
                                    avatar: Icon(style.icon,
                                        size: 16, color: Colors.white),
                                    label: Text(style.label,
                                        style: const TextStyle(
                                            color: Colors.white)),
                                    backgroundColor: style.color,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const Spacer(),
                                  if (_distanceMiles != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        '${_distanceMiles!.toStringAsFixed(1)} mi',
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(widget.place.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              if (widget.place.address != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.location_on_outlined,
                                          size: 16, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Expanded(
                                          child: Text(widget.place.address!,
                                              style: const TextStyle(
                                                  color: Colors.grey))),
                                    ],
                                  ),
                                ),
                              if (headline != null) ...[
                                const Divider(height: 32),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    UserAvatar(
                                        userId: headline.userId, radius: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          RichText(
                                            text: TextSpan(
                                              style:
                                                  DefaultTextStyle.of(context)
                                                      .style,
                                              children: [
                                                const TextSpan(
                                                    text: 'Pinned by '),
                                                TextSpan(
                                                  text: headline.authorName ??
                                                      'Unknown rep',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                                TextSpan(
                                                  text:
                                                      ' • ${formatPinTimestamp(headline.createdAt)}',
                                                  style: const TextStyle(
                                                      color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (headline.comment != null) ...[
                                            const SizedBox(height: 4),
                                            Text(headline.comment!),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (headline.userId ==
                                        widget.repository.currentUserId)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            size: 20),
                                        tooltip: 'Delete your pin',
                                        onPressed: () => _deleteVisit(headline),
                                      ),
                                  ],
                                ),
                              ],
                              const Divider(height: 32),
                              Text('Comments (${comments.length})',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ],
                          ),
                        ),
                        for (final visit in comments)
                          ListTile(
                            leading: UserAvatar(userId: visit.userId),
                            title: Text(visit.authorName ?? 'Unknown rep'),
                            subtitle: Text(visit.comment ?? ''),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(formatPinTimestamp(visit.createdAt),
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                                if (visit.userId ==
                                    widget.repository.currentUserId)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20),
                                    tooltip: 'Delete your comment',
                                    onPressed: () => _deleteVisit(visit),
                                  ),
                              ],
                            ),
                          ),
                        if (headline == null && comments.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                                child: Text('No visits logged here yet.')),
                          ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            decoration: const InputDecoration(
                              hintText: 'Add a comment...',
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(24))),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: _posting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send),
                          onPressed: _posting ? null : _postComment,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
