import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:tracelet/tracelet.dart' as tl;

import 'visits_repository.dart';

/// How far the device has to move since the last *logged* point before a
/// new one is written.
const _minMoveMeters = 10;

/// Only track during working hours reps are actually out finding
/// customers — not all day. Adjust these two lines to change the window;
/// in minutes-since-midnight so non-whole-hour boundaries (11:30, say)
/// work too, not just whole hours.
const _windowStartMinutes = 8 * 60; // 08:00 — widened temporarily for testing
const _windowEndMinutes = 16 * 60; // 16:00

/// Logs the current user's movement trail — but only during the working
/// window above, and only when the device has actually moved, never on a
/// fixed timer. That's what keeps a stationary rep from accumulating
/// GPS-jitter "distance": no real movement means no new point, so nothing
/// to sum.
///
/// Two different engines back this, chosen at runtime via `kIsWeb`:
///
/// - **Web**: a plain geolocator position stream, manually distance-filtered
///   against the last logged point. Browsers have no background-tracking
///   concept at all — a closed tab is simply gone — so this only ever runs
///   while the tab is open, same as before. (`distanceFilter` on the stream
///   itself isn't honored by geolocator's web implementation — confirmed via
///   ~450 points logged for someone mostly stationary — hence the manual
///   check on top of it.)
/// - **Android/iOS**: `tracelet`, a real native background-geolocation
///   plugin (Kotlin/Swift foreground service under the hood), so tracking
///   survives the screen locking or the app being backgrounded — not just
///   foregrounded. Its own `distanceFilter` is honored natively, no manual
///   check needed. Deliberately configured with `stopOnTerminate: true`:
///   tracking stops the instant the app process is actually killed, so the
///   11:00-16:00 window can't run past its end on a day nothing ever
///   reopens the app. The gap this leaves — a rep force-closing the app
///   specifically to dodge tracking — is a narrower, more deliberate case
///   than the screen-lock/backgrounding gap this was built to close.
///   iOS isn't wired up on the native-project side yet (no ios/ directory,
///   no Apple Developer Program access) — this path is Android-only until
///   that changes; the tracelet calls themselves are already
///   platform-neutral, so enabling iOS later needs no Dart changes here.
class LocationTracker {
  LocationTracker(this._repository);

  final VisitsRepository _repository;

  // Web engine.
  StreamSubscription<Position>? _webSubscription;
  Position? _lastLogged;

  // Mobile engine.
  bool _traceletReady = false;
  bool _mobileTracking = false;

  Timer? _scheduleTimer;

  /// Fires if starting/stopping tracking throws — e.g. a permission denial
  /// or a plugin-level failure on the tracelet path. Without this, a
  /// failure here is completely silent: no crash, no visible error,
  /// tracking just never starts and nobody can tell why. Set from the UI
  /// (see HomeShell) so a real device failure actually surfaces instead of
  /// requiring a debugger attached to reproduce.
  void Function(Object error)? onTrackingError;

  static bool isWithinTrackingWindow([DateTime? at]) {
    final now = at ?? DateTime.now();
    final minutesSinceMidnight = now.hour * 60 + now.minute;
    return minutesSinceMidnight >= _windowStartMinutes &&
        minutesSinceMidnight < _windowEndMinutes;
  }

  bool get isActive => kIsWeb ? _webSubscription != null : _mobileTracking;

  /// Starts checking, once a minute, whether the working window is open —
  /// starting/stopping actual GPS tracking to match. Returns whether
  /// tracking is active right now (useful for a one-time "we're tracking"
  /// notice — no point showing it outside the window).
  Future<bool> startScheduled() async {
    await _evaluateSchedule();
    _scheduleTimer?.cancel();
    _scheduleTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _evaluateSchedule());
    return isActive;
  }

  Future<void> _evaluateSchedule() async {
    try {
      if (isWithinTrackingWindow()) {
        await _start();
      } else {
        await _stop();
      }
    } catch (e) {
      onTrackingError?.call(e);
    }
  }

  Future<void> _start() => kIsWeb ? _startWeb() : _startMobile();

  Future<void> _stop() => kIsWeb ? _stopWeb() : _stopMobile();

  // ---- Web engine ----

  Future<void> _startWeb() async {
    if (_webSubscription != null) return;

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
    _webSubscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onWebPosition);
  }

  void _onWebPosition(Position position) {
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

  Future<void> _stopWeb() async {
    _webSubscription?.cancel();
    _webSubscription = null;
    _lastLogged = null;
  }

  // ---- Mobile engine ----

  Future<void> _startMobile() async {
    if (_mobileTracking) return;

    if (!_traceletReady) {
      await tl.Tracelet.ready(tl.Config.balanced().copyWith(
        geo: tl.GeoConfig(
          desiredAccuracy: tl.DesiredAccuracy.high,
          distanceFilter: _minMoveMeters.toDouble(),
        ),
        app: const tl.AppConfig(
          stopOnTerminate: true,
          startOnBoot: false,
        ),
        // `Config.balanced()`'s default motion detection tries to be
        // battery-smart: it powers GPS down once it *thinks* the device
        // stopped moving (via accelerometer/activity-recognition), and only
        // reactivates on its own motion cues — not on GPS movement itself.
        // Confirmed on a real device: it logged exactly one point, then
        // never logged again despite real movement — motion detection
        // never recognized "moving" and GPS just stayed parked. This app's
        // window is already capped to 5 hours/day, and correctness matters
        // more here than squeezing out extra battery life, so disable that
        // state machine entirely and let the plain distanceFilter above
        // (checked against real GPS fixes, not inferred motion) be the only
        // thing deciding when a new point gets logged.
        motion: const tl.MotionConfig(
          disableStopDetection: true,
          stopOnStationary: false,
        ),
        // Not strictly required for the service to run — tracelet's own
        // defaults already produce a working foreground service — but this
        // is what tracelet's own background-tracking guide documents as
        // the expected setup, and it means the persistent notification
        // reads "Map Notes" instead of the library's own default
        // "Tracelet" branding.
        android: const tl.AndroidConfig(
          foregroundService: tl.ForegroundServiceConfig(
            notificationTitle: 'Map Notes',
            notificationText: "Logging today's route",
          ),
        ),
      ));
      tl.Tracelet.onLocation(_onMobileLocation);
      _traceletReady = true;
    }

    // Android 13+ hides the foreground-service notification without this —
    // a hidden notification can look like a non-genuine foreground service
    // to some OEMs' battery managers, inviting a kill.
    await tl.Tracelet.requestNotificationAuthorization();

    // A single requestLocationAuthorization() call only ever advances one
    // permission tier per invocation (confirmed against tracelet's own
    // documented escalation logic): a fresh grant lands on `whenInUse`
    // (foreground only), and a second, separate call is needed to prompt
    // for background access.
    var authResult = await tl.Tracelet.requestLocationAuthorization();
    if (authResult == tl.AuthorizationStatus.whenInUse) {
      authResult = await tl.Tracelet.requestLocationAuthorization();
    }
    debugPrint('LocationTracker: authorization result = $authResult');
    await tl.Tracelet.start();
    _mobileTracking = true;
    debugPrint('LocationTracker: tracelet started');
  }

  void _onMobileLocation(tl.Location location) {
    debugPrint(
        'LocationTracker: onLocation fired (tracking=$_mobileTracking) '
        '${location.coords.latitude}, ${location.coords.longitude}');
    if (!_mobileTracking) return;
    _repository.logLocationPoint(
        lat: location.coords.latitude, lng: location.coords.longitude);
  }

  Future<void> _stopMobile() async {
    if (!_mobileTracking) return;
    _mobileTracking = false;
    await tl.Tracelet.stop();
  }

  /// Sends the rep straight to the OS battery-optimization settings for
  /// this app. Not gated behind a "should we ask" check — some Android
  /// OEMs (Xiaomi, Huawei, etc.) kill background services despite the
  /// foreground-service notification unless the app is manually
  /// whitelisted, and there's no reliable way to detect that in advance.
  /// Surfaced as an optional one-time nudge from the UI, not forced.
  Future<void> openBatterySettings() => tl.Tracelet.openBatterySettings();

  void stopScheduled() {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    unawaited(_stop());
  }
}
