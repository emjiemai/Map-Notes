import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../models/visit.dart';
import '../services/visits_repository.dart';
import '../widgets/category_style.dart';
import '../widgets/user_avatar.dart';
import 'place_detail_screen.dart';

// Dev/testing map: free OpenStreetMap tiles via flutter_map, no API key
// needed. Swap for Yandex MapKit before release — see README.

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.repository, this.onAddPin});

  final VisitsRepository repository;
  final VoidCallback? onAddPin;

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  List<Place> _places = [];
  Map<String, String> _latestVisitorByPlace = {};
  List<(Visit, Place)> _pinned = [];
  String _query = '';
  PlaceCategory? _categoryFilter; // null = "All Activity"

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final places = await widget.repository.fetchPlaces();
    final latestVisitor = await widget.repository.fetchLatestVisitorByPlace();
    final pinned = await widget.repository.fetchRecentActivity(limit: 15);
    if (!mounted) return;
    setState(() {
      _places = places;
      _latestVisitorByPlace = latestVisitor;
      _pinned = pinned;
    });
  }

  List<Place> get _visiblePlaces {
    return _places.where((place) {
      final matchesCategory = _categoryFilter == null || place.category == _categoryFilter;
      final matchesQuery = _query.isEmpty || place.name.toLowerCase().contains(_query.toLowerCase());
      return matchesCategory && matchesQuery;
    }).toList();
  }

  void _openPlace(Place place) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PlaceDetailScreen(place: place, repository: widget.repository)))
        .then((_) => reload());
  }

  @override
  Widget build(BuildContext context) {
    const fallbackCenter = LatLng(41.2995, 69.2401); // Tashkent

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _places.isNotEmpty ? LatLng(_places.first.lat, _places.first.lng) : fallbackCenter,
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.mapnotes.app',
              ),
              MarkerLayer(
                markers: _visiblePlaces.map((place) {
                  final style = styleFor(place.category);
                  final visitorId = _latestVisitorByPlace[place.id];
                  return Marker(
                    point: LatLng(place.lat, place.lng),
                    width: 48,
                    height: 48,
                    child: GestureDetector(
                      onTap: () => _openPlace(place),
                      child: visitorId == null
                          ? Container(
                              decoration: BoxDecoration(
                                color: style.color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: Icon(style.icon, color: Colors.white, size: 22),
                            )
                          : DecoratedBox(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: UserAvatar(userId: visitorId, radius: 20, ringColor: style.color),
                            ),
                    ),
                  );
                }).toList(),
              ),
              RichAttributionWidget(
                attributions: [TextSourceAttribution('OpenStreetMap contributors', onTap: () {})],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                children: [
                  _SearchBar(onChanged: (q) => setState(() => _query = q)),
                  const SizedBox(height: 10),
                  _CategoryChips(
                    selected: _categoryFilter,
                    onSelected: (category) => setState(() => _categoryFilter = category),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: _PinnedStrip(items: _pinned, onTap: _openPlace),
          ),
        ],
      ),
      floatingActionButton: widget.onAddPin == null
          ? null
          : FloatingActionButton(onPressed: widget.onAddPin, child: const Icon(Icons.add)),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(28),
      child: TextField(
        onChanged: onChanged,
        decoration: const InputDecoration(
          hintText: 'Search places...',
          prefixIcon: Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(28)), borderSide: BorderSide.none),
          contentPadding: EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelected});

  final PlaceCategory? selected;
  final ValueChanged<PlaceCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(
            label: const Text('All Activity'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
            backgroundColor: Colors.white,
          ),
          const SizedBox(width: 8),
          ...PlaceCategory.values.map((category) {
            final style = styleFor(category);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(style.label),
                selected: selected == category,
                onSelected: (_) => onSelected(category),
                backgroundColor: Colors.white,
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// The "Pinned" strip: every recent pin, newest first, scrollable — so a
/// rep sees their pin land here the moment they save it, and can spot
/// teammates' pins without hunting around the map.
class _PinnedStrip extends StatelessWidget {
  const _PinnedStrip({required this.items, required this.onTap});

  final List<(Visit, Place)> items;
  final void Function(Place) onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No pins yet — drop the first one with the + button.'),
          ),
        ),
      );
    }
    return SizedBox(
      height: 88,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (visit, place) = items[index];
          final style = styleFor(place.category);
          final isRecent = DateTime.now().difference(visit.createdAt) < const Duration(hours: 2);

          return Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onTap(place),
              child: Container(
                width: 240,
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    UserAvatar(userId: visit.userId, radius: 18, ringColor: style.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(place.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          Text(
                            '${visit.authorName ?? 'A rep'} • ${DateFormat.jm().format(visit.createdAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isRecent)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(8)),
                              child: Text('Recent', style: TextStyle(color: Colors.green.shade800, fontSize: 10)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
