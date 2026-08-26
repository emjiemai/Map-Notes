import 'package:flutter/material.dart';

import '../services/visits_repository.dart';
import 'add_visit_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';

/// Hosts the bottom nav (Map / Add / Profile) shown in the mockup. "Add" is
/// a tab for discoverability, but also reachable via the FAB on the map —
/// same screen either way.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repository});

  final VisitsRepository repository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _mapKey = GlobalKey<MapScreenState>();

  Future<void> _openAddPin() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddVisitScreen(repository: widget.repository)),
    );
    if (saved == true) _mapKey.currentState?.reload();
    setState(() => _tab = 0);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      MapScreen(key: _mapKey, repository: widget.repository, onAddPin: _openAddPin),
      const SizedBox.shrink(), // Add tab has no page of its own — see onTap below.
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
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Add'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
