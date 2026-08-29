import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'visits_repository.dart';

/// Logs the current user's movement trail while running — but only when
/// the device has actually moved (distanceFilter), never on a fixed timer.
/// That's what keeps a stationary rep from accumulating GPS-jitter
/// "distance": no movement means no new point, so nothing to sum.
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

    const settings =
        LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25);
    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen((position) {
      _repository.logLocationPoint(
          lat: position.latitude, lng: position.longitude);
    });
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }
}
