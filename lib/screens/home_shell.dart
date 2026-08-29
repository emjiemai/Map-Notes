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

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _mapKey = GlobalKey<MapScreenState>();
  late final LocationTracker _locationTracker;

  @override
  void initState() {
    super.initState();
    _locationTracker = LocationTracker(widget.repository);
    _locationTracker.start();
    // One-time notice rather than a permanent banner — transparency without
    // permanently eating screen space. See LocationTracker's doc comment
    // for exactly what this does and doesn't cover.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Logging today's route for transportation records.")),
      );
    });
  }

  @override
  void dispose() {
    _locationTracker.stop();
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
