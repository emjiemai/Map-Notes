import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/location_point.dart';
import '../services/visits_repository.dart';

const _retentionDays = 14;

/// A rep's movement trail for one day, for transportation reimbursement —
/// points are only logged when the device actually moves (see
/// LocationTracker), so the distance shown here isn't inflated by GPS
/// jitter while someone's stationary. History goes back 14 days, matching
/// how long rep_locations retains data server-side (see migration 0008).
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key, required this.repository});

  final VisitsRepository repository;

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  List<(String userId, String name)> _reps = [];
  String? _selectedUserId;
  DateTime _day = DateTime.now();
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
    if (defaultUserId != null) _loadRoute();
  }

  Future<void> _loadRoute() async {
    final userId = _selectedUserId;
    if (userId == null) return;
    setState(() => _loading = true);
    final route = await widget.repository.fetchRoute(userId, day: _day);
    if (!mounted) return;
    setState(() {
      _route = route;
      _loading = false;
    });
  }

  bool get _isToday => _isSameDay(_day, DateTime.now());
  bool get _isOldestAllowed => _isSameDay(
      _day, DateTime.now().subtract(const Duration(days: _retentionDays - 1)));

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _shiftDay(int deltaDays) {
    setState(() => _day = _day.add(Duration(days: deltaDays)));
    _loadRoute();
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

  /// One point per 10-minute bucket the route touches — so the line can
  /// carry time labels ("09:10", "09:20"...) without a label per single
  /// GPS point, which would be unreadable.
  List<LocationPoint> get _timeMarkers {
    final markers = <LocationPoint>[];
    DateTime? lastBucket;
    for (final point in _route) {
      final t = point.recordedAt;
      final bucket =
          DateTime(t.year, t.month, t.day, t.hour, (t.minute ~/ 10) * 10);
      if (lastBucket == null || bucket.isAfter(lastBucket)) {
        markers.add(point);
        lastBucket = bucket;
      }
    }
    return markers;
  }

  /// Points broken into separate runs wherever consecutive points are more
  /// than 30m apart. Points log irregularly (only on real movement, or
  /// after a tracking gap), so a straight line drawn across a real gap
  /// would misrepresent a path that was never actually walked in a
  /// straight line — better to show a visible break than a wrong line.
  List<List<LatLng>> get _polylineSegments {
    if (_route.length < 2) return [];
    final segments = <List<LatLng>>[];
    var current = [LatLng(_route.first.lat, _route.first.lng)];
    for (var i = 1; i < _route.length; i++) {
      final prev = _route[i - 1];
      final point = _route[i];
      final gap = Geolocator.distanceBetween(
          prev.lat, prev.lng, point.lat, point.lng);
      if (gap > 30) {
        if (current.length > 1) segments.add(current);
        current = [LatLng(point.lat, point.lng)];
      } else {
        current.add(LatLng(point.lat, point.lng));
      }
    }
    if (current.length > 1) segments.add(current);
    return segments;
  }

  @override
  Widget build(BuildContext context) {
    const fallbackCenter = LatLng(41.2995, 69.2401); // Tashkent
    final points = _route.map((p) => LatLng(p.lat, p.lng)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Routes'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _selectedUserId == null ? _loadReps : _loadRoute),
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
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
                      _loadRoute();
                    },
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed:
                            _isOldestAllowed ? null : () => _shiftDay(-1),
                      ),
                      Text(DateFormat.yMMMd().format(_day),
                          style: Theme.of(context).textTheme.titleMedium),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _isToday ? null : () => _shiftDay(1),
                      ),
                    ],
                  ),
                ),
                if (!_loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _route.isEmpty
                            ? 'No points logged this day.'
                            : '${(_totalDistanceMeters / 1000).toStringAsFixed(1)} km • ${_route.length} points',
                        style: Theme.of(context).textTheme.bodyMedium,
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
                            if (_polylineSegments.isNotEmpty)
                              PolylineLayer(
                                polylines: [
                                  for (final segment in _polylineSegments)
                                    Polyline(
                                        points: segment,
                                        strokeWidth: 4,
                                        color: Colors.blue),
                                ],
                              ),
                            MarkerLayer(
                              markers: [
                                for (final point in _timeMarkers)
                                  Marker(
                                    point: LatLng(point.lat, point.lng),
                                    width: 48,
                                    height: 20,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        DateFormat.Hm()
                                            .format(point.recordedAt),
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 10),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
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
