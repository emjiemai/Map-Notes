import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Name-only entry, no email/SMS — right fit for a small, known team (a
/// handful of reps) where real verification is overkill. Signs in
/// anonymously (still a real, distinct auth.uid() per rep — RLS, dedupe,
/// and per-rep deletion all still work exactly as before) and stores the
/// typed name on their profile.
///
/// Requires "Allow anonymous sign-ins" enabled in Supabase: Authentication
/// → Providers → Anonymous Sign-Ins.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();

  bool _loading = false;
  String? _error;

  Future<void> _start() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name to continue.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      await client.auth.signInAnonymously(data: {'full_name': name});
      // Belt-and-suspenders: don't rely solely on the signup trigger
      // picking up metadata correctly — set it explicitly too.
      await client.from('profiles').update({'full_name': name}).eq('id', client.auth.currentUser!.id);
      // AuthGate in main.dart picks up the new session automatically.
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Map Notes', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text('Enter your name to start.'),
              const SizedBox(height: 32),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder()),
                onSubmitted: (_) => _start(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _start,
                child: Text(_loading ? 'Please wait...' : 'Start'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
