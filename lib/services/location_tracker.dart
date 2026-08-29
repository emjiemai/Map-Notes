import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'visits_repository.dart';

/// How far the device has to move since the last *logged* point before a
/// new one is written.
const _minMoveMeters = 25;

/// Logs the current user's movement trail while running — but only when
/// the device has actually moved, never on a fixed timer. That's what
/// keeps a stationary rep from accumulating GPS-jitter "distance": no real
/// movement means no new point, so nothing to sum.
///
/// Filtering happens twice: `distanceFilter` on the position stream asks
/// the platform to only emit updates after real movement, but on web that
/// request isn't actually honored — the browser Geolocation API has no
/// native distance-filter concept, so geolocator's web implementation ends
/// up emitting on nearly every raw GPS update regardless (confirmed: ~450
/// points for what should have been a handful, from someone stationary
/// most of the time). So this also checks distance from the last *logged*
/// point itself before writing anything, which works correctly on every
/// platform regardless of whether the stream-level filter is honored.
///
/// Scope: this tracks while the app process is alive — foreground, or
/// briefly backgrounded (screen off, quick app-switch). It does **not**
/// reliably keep tracking for hours with the app fully closed — both
/// Android and iOS aggressively suspend a plain app's location access once
/// truly backgrounded. Surviving that needs a persistent Android
/// foreground service (with a mandatory visible notification) and iOS
/// "Always" permission with a background mode — a separate, larger piece
/// of work, deliberately not built here.
class LocationTracker {
  LocationTracker(this._repository);

  final VisitsRepository _repository;
  StreamSubscription<Position>? _subscription;
  Position? _lastLogged;

  Future<void> start() async {
    if (_subscription != null) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    const settings = LocationSettings(
        accuracy: LocationAccuracy.high, distanceFilter: _minMoveMeters);
    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition);
  }

  void _onPosition(Position position) {
    final last = _lastLogged;
    if (last != null) {
      final moved = Geolocator.distanceBetween(
          last.latitude, last.longitude, position.latitude, position.longitude);
      if (moved < _minMoveMeters) return;
    }
    _lastLogged = position;
    _repository.logLocationPoint(
        lat: position.latitude, lng: position.longitude);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _lastLogged = null;
  }
}
