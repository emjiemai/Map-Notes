import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/location_point.dart';
import '../services/visits_repository.dart';

/// Today's movement trail for a rep, for transportation reimbursement —
/// points are only logged when the device actually moves (see
/// LocationTracker), so the distance shown here isn't inflated by GPS
/// jitter while someone's stationary.
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key, required this.repository});

  final VisitsRepository repository;

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  List<(String userId, String name)> _reps = [];
  String? _selectedUserId;
  List<LocationPoint> _route = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReps();
  }

  Future<void> _loadReps() async {
    final reps = await widget.repository.fetchRepsWithLocationData();
    if (!mounted) return;
    final defaultUserId =
        reps.any((r) => r.$1 == widget.repository.currentUserId)
            ? widget.repository.currentUserId
            : (reps.isEmpty ? null : reps.first.$1);
    setState(() {
      _reps = reps;
      _selectedUserId = defaultUserId;
      _loading = false;
    });
    if (defaultUserId != null) _loadRoute(defaultUserId);
  }

  Future<void> _loadRoute(String userId) async {
    setState(() => _loading = true);
    final route = await widget.repository.fetchRoute(userId);
    if (!mounted) return;
    setState(() {
      _route = route;
      _loading = false;
    });
  }

  double get _totalDistanceMeters {
    var total = 0.0;
    for (var i = 1; i < _route.length; i++) {
      total += Geolocator.distanceBetween(
        _route[i - 1].lat,
        _route[i - 1].lng,
        _route[i].lat,
        _route[i].lng,
      );
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    const fallbackCenter = LatLng(41.2995, 69.2401); // Tashkent
    final points = _route.map((p) => LatLng(p.lat, p.lng)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Routes"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _selectedUserId == null
                ? _loadReps()
                : _loadRoute(_selectedUserId!),
          ),
        ],
      ),
      body: _reps.isEmpty && !_loading
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No location data logged yet.')))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedUserId,
                    decoration: const InputDecoration(
                        labelText: 'Rep', border: OutlineInputBorder()),
                    items: _reps
                        .map((r) =>
                            DropdownMenuItem(value: r.$1, child: Text(r.$2)))
                        .toList(),
                    onChanged: (userId) {
                      if (userId == null) return;
                      setState(() => _selectedUserId = userId);
                      _loadRoute(userId);
                    },
                  ),
                ),
                if (!_loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _route.isEmpty
                            ? 'No points logged today.'
                            : '${(_totalDistanceMeters / 1000).toStringAsFixed(1)} km today • ${_route.length} points',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : FlutterMap(
                          options: MapOptions(
                            initialCenter: points.isNotEmpty
                                ? points.last
                                : fallbackCenter,
                            initialZoom: 13,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.mapnotes.app',
                            ),
                            if (points.length > 1)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                      points: points,
                                      strokeWidth: 4,
                                      color: Colors.blue)
                                ],
                              ),
                            MarkerLayer(
                              markers: [
                                if (points.isNotEmpty)
                                  Marker(
                                    point: points.first,
                                    width: 32,
                                    height: 32,
                                    child: const Icon(Icons.trip_origin,
                                        color: Colors.green, size: 28),
                                  ),
                                if (points.length > 1)
                                  Marker(
                                    point: points.last,
                                    width: 32,
                                    height: 32,
                                    child: const Icon(Icons.location_on,
                                        color: Colors.red, size: 32),
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}
