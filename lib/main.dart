import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/visits_repository.dart';

// Map screens currently use flutter_map + free OpenStreetMap tiles (no API
// key, no native setup) so the app is testable without a Yandex account.
// When switching to Yandex MapKit for release, its key is set natively, not
// here — see README "Switching to Yandex MapKit".

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    publishableKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  runApp(const MapNotesApp());
}

class MapNotesApp extends StatelessWidget {
  const MapNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Map Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: AuthGate(repository: VisitsRepository(Supabase.instance.client)),
    );
  }
}

/// Routes to LoginScreen or MapScreen based on current auth state, and keeps
/// following auth changes (e.g. after OTP verification, or on sign out).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.repository});

  final VisitsRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return HomeShell(repository: repository);
        }
        return const LoginScreen();
      },
    );
  }
}
