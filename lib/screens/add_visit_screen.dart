import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/group.dart';
import '../models/place.dart';
import '../services/visits_repository.dart';
import '../widgets/category_style.dart';

const _maxPhotos = 4;
const _fallbackCenter = LatLng(41.2995, 69.2401); // Tashkent

/// Mirrors the "Add Pin" flow. The map starts centered on GPS but stays
/// fully interactive with a fixed center pin (like Uber/Google Maps' "drop
/// pin" pattern) — reps confirm/nudge the exact spot by panning instead of
/// silently trusting raw GPS, which is what made pins easy to forget or
/// mis-place before.
class AddVisitScreen extends StatefulWidget {
  const AddVisitScreen({super.key, required this.repository});

  final VisitsRepository repository;

  @override
  State<AddVisitScreen> createState() => _AddVisitScreenState();
}

class _AddVisitScreenState extends State<AddVisitScreen> {
  final _nameController = TextEditingController();
  final _commentController = TextEditingController();
  final _mapController = MapController();

  LatLng _pinLatLng = _fallbackCenter;
  bool _locating = true;
  bool _saving = false;
  bool _usedFallbackLocation = false;
  String? _error;

  PlaceCategory _category = PlaceCategory.other;
  List<Group> _groups = [];
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _locate();
    _loadGroups();
  }

  // Falls back to a default map center on any failure (permission denied,
  // GPS unavailable, browser blocking it, whatever) rather than leaving the
  // pin position unset — that used to leave Save silently disabled with no
  // obvious reason why. The rep can always drag the map to the right spot
  // regardless of how the initial center was chosen.
  Future<void> _locate() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() {
          _usedFallbackLocation = true;
          _locating = false;
        });
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _pinLatLng = LatLng(position.latitude, position.longitude);
        _locating = false;
      });
    } catch (e) {
      setState(() {
        _usedFallbackLocation = true;
        _locating = false;
      });
    }
  }

  Future<void> _loadGroups() async {
    final groups = await widget.repository.fetchGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _selectedGroupId = groups.isEmpty ? null : groups.first.id;
    });
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Give the place a name first.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Photo attachments are visible but disabled for now — see README.
      await widget.repository.logVisit(
        lat: _pinLatLng.latitude,
        lng: _pinLatLng.longitude,
        name: _nameController.text.trim(),
        comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
        category: _category,
        groupId: _selectedGroupId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save pin: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Pin'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 220,
              child: _locating
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _pinLatLng,
                            initialZoom: 17,
                            onPositionChanged: (camera, hasGesture) {
                              if (hasGesture) setState(() => _pinLatLng = camera.center);
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.mapnotes.app',
                            ),
                          ],
                        ),
                        // Fixed center pin — the map moves under it, not the other way round.
                        const IgnorePointer(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 32),
                            child: Icon(Icons.location_pin, size: 44, color: Colors.blue),
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Move the map to place your pin exactly',
                              style: TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (_usedFallbackLocation && !_locating)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Couldn't get your location — pan the map above to your actual spot before posting.",
                      style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Place name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('CATEGORY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: PlaceCategory.values.map((category) {
              final style = styleFor(category);
              return ChoiceChip(
                avatar: Icon(style.icon, size: 18, color: _category == category ? Colors.white : style.color),
                label: Text(style.label),
                selected: _category == category,
                selectedColor: style.color,
                labelStyle: TextStyle(color: _category == category ? Colors.white : null),
                onSelected: (_) => setState(() => _category = category),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text('DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Add your comment...', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('PHOTOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              Text('Coming soon', style: TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: 0.5,
            child: IgnorePointer(
              child: SizedBox(
                height: 72,
                child: Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add_photo_alternate_outlined, color: Colors.grey),
                    ),
                    const SizedBox(width: 8),
                    const Text('0/$_maxPhotos', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
          if (_groups.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('POST TO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedGroupId,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
              items: _groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
              onChanged: (value) => setState(() => _selectedGroupId = value),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_saving || _locating) ? null : _save,
            child: Text(_saving ? 'Posting...' : 'Post to Group'),
          ),
        ],
      ),
    );
  }
}
