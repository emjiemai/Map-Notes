import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Name + 6-digit PIN, no email/SMS — a stable identity a rep can re-enter
/// from any device, unlike plain anonymous sign-in (which mints a *new*
/// identity every time a session is lost — trivial on web: clearing
/// cookies, incognito, a different browser). Under the hood this is
/// ordinary Supabase phone/password auth: the name is hashed into a
/// synthetic, unreachable phone number purely as a stable account key.
///
/// Phone rather than email deliberately — Supabase validates that an
/// email's *domain* can actually receive mail (rejects `.internal`, even
/// `example.com`), so a synthetic email never gets past sign-up. Phone
/// numbers only get format-checked, and password-based phone auth never
/// sends an SMS (that only happens for OTP, which this doesn't use), so no
/// SMS provider is needed either.
///
/// First attempt tries signing in; if that fails, it tries creating the
/// account instead — so the same "Continue" button covers both a
/// returning rep and a brand-new one. If an account already exists and the
/// PIN was simply wrong, both attempts fail and that's reported clearly.
///
/// Requires the **Phone** provider enabled in Supabase: Authentication →
/// Providers → Phone.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();

  bool _loading = false;
  String? _error;

  String _phoneFor(String name) {
    final normalized = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    var hash = 0;
    for (final unit in normalized.codeUnits) {
      hash = (hash * 31 + unit) % 900000000;
    }
    final digits = (100000000 + hash).toString();
    return '+998$digits';
  }

  Future<void> _start() async {
    final name = _nameController.text.trim();
    final pin = _pinController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    if (pin.length != 6) {
      setState(() => _error = 'PIN must be exactly 6 digits.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    final phone = _phoneFor(name);
    try {
      try {
        await client.auth.signInWithPassword(phone: phone, password: pin);
      } on AuthException {
        // Not a returning rep with this name/PIN — try creating the
        // account instead. If this *also* fails, the account exists and
        // the PIN was just wrong (phone is already registered).
        await client.auth.signUp(phone: phone, password: pin, data: {'full_name': name});
      }
      await client.from('profiles').update({'full_name': name}).eq('id', client.auth.currentUser!.id);
      // AuthGate in main.dart picks up the new session automatically.
    } catch (e) {
      setState(() => _error = "Couldn't sign in — if you've used this name before, double check your PIN.");
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
              const Text('Enter your name and a 6-digit PIN. First time picks it; after that, use the same one.'),
              const SizedBox(height: 32),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: '6-digit PIN', border: OutlineInputBorder(), counterText: ''),
                onSubmitted: (_) => _start(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _start,
                child: Text(_loading ? 'Please wait...' : 'Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
