import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/sync_service.dart';

/// Minimal sign-in screen. Cross-device sync needs the SAME account
/// signed in on both Android and desktop, so this uses real
/// email/password auth rather than anonymous sign-in (which ties to a
/// single device and can't be shared between them).
class LoginScreen extends StatefulWidget {
  final SyncService sync;
  const LoginScreen({super.key, required this.sync});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegistering = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter an email and password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isRegistering) {
        await widget.sync.registerWithEmail(email, password);
      } else {
        await widget.sync.signInWithEmail(email, password);
      }
      // On success, FirebaseAuth's authStateChanges() stream (listened
      // to in main.dart) fires automatically and swaps this screen out
      // for the task list — nothing else to do here.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in to sync')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isRegistering ? 'Create an account' : 'Sign in',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Use the same account on every device you want '
                  'your tasks to sync across.',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isRegistering ? 'Create account' : 'Sign in'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() => _isRegistering = !_isRegistering),
                  child: Text(_isRegistering
                      ? 'Already have an account? Sign in'
                      : "Don't have an account? Create one"),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}