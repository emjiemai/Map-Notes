import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/location_tracker.dart';
import '../services/visits_repository.dart';
import 'add_visit_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'routes_screen.dart';

/// Hosts the bottom nav (Map / Add / Routes / Profile). "Add" is a tab for
/// discoverability, but also reachable via the FAB on the map — same
/// screen either way.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repository});

  final VisitsRepository repository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _mapKey = GlobalKey<MapScreenState>();
  late final LocationTracker _locationTracker;

  // Points recorded while the phone was asleep only reach the server once
  // something asks for them, and coming back to the app is the first moment
  // anything can — so drain here rather than waiting for the next tick.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _locationTracker.drainNow();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locationTracker = LocationTracker(widget.repository);
    _locationTracker.onPointsDrained = (count) {
      if (!mounted || count == 0) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploaded $count tracked points.')),
      );
      if (_tab == 2) setState(() {});
    };
    // Surfaces a failure that would otherwise be completely silent — no
    // crash, no visible sign tracking never started, just a rep's route
    // quietly missing later.
    _locationTracker.onTrackingError = (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location tracking failed to start: $error')),
      );
    };
    // startScheduled checks the working-window (11:00-16:00 by default —
    // see LocationTracker) once now and once a minute after, starting or
    // stopping actual GPS tracking to match. Only show the one-time notice
    // if tracking is genuinely active right now — showing it outside the
    // window would be misleading, nothing is being logged then.
    _locationTracker.startScheduled().then((active) {
      if (!mounted || !active) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              "Logging today's route for transportation records."),
          // Some phones (Xiaomi, Huawei, etc.) kill background tracking
          // despite the persistent notification unless the app is manually
          // exempted from battery optimization — offer that up front rather
          // than have it silently fail later.
          action: kIsWeb
              ? null
              : SnackBarAction(
                  label: 'Battery settings',
                  onPressed: _locationTracker.openBatterySettings,
                ),
        ),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationTracker.stopScheduled();
    super.dispose();
  }

  Future<void> _openAddPin() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => AddVisitScreen(repository: widget.repository)),
    );
    if (saved == true) _mapKey.currentState?.reload();
    setState(() => _tab = 0);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      MapScreen(
          key: _mapKey, repository: widget.repository, onAddPin: _openAddPin),
      const SizedBox
          .shrink(), // Add tab has no page of its own — see onTap below.
      RoutesScreen(repository: widget.repository),
      ProfileScreen(repository: widget.repository),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          if (index == 1) {
            _openAddPin();
            return;
          }
          setState(() => _tab = index);
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map'),
          NavigationDestination(
              icon: Icon(Icons.add_circle_outline), label: 'Add'),
          NavigationDestination(
              icon: Icon(Icons.route_outlined),
              selectedIcon: Icon(Icons.route),
              label: 'Routes'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}
