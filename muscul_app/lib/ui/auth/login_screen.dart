import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../data/auth/auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isSignup = false;
  bool _busy = false;
  bool _obscurePass = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.length < 6) {
      setState(() {
        _error = 'Email + mot de passe (6 caractères mini) requis';
        _info = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      if (_isSignup) {
        await auth.signUp(email: email, password: pass);
      } else {
        await auth.signIn(email: email, password: pass);
      }
      // If we now have an active session (instant signup or sign-in),
      // bounce back to the home screen with a success snack.
      if (auth.isLoggedIn) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connecté ✓'),
              duration: Duration(seconds: 2),
            ),
          );
          context.pop();
        }
        return;
      }
      // Email-confirmation flow: signup succeeded but session pending.
      setState(() => _info =
          'Compte créé. Vérifie ta boîte mail pour confirmer, '
          'puis reviens te connecter.');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Erreur: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Saisis ton email pour recevoir le lien');
      return;
    }
    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      setState(() {
        _info = 'Email de réinitialisation envoyé à $email';
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Erreur: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignup ? 'Créer un compte' : 'Connexion'),
      ),
      body: !SupabaseConfig.isConfigured
          ? const _NotConfigured()
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isSignup
                          ? "Tes données restent locales tant que tu n'es pas connecté. "
                              "Crée un compte pour les sauvegarder dans le cloud."
                          : "Connecte-toi pour synchroniser tes séances entre appareils.",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _emailCtrl,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      autofillHints: const [AutofillHints.password],
                      obscureText: _obscurePass,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePass
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscurePass ? 'Afficher' : 'Masquer',
                          onPressed: () => setState(
                              () => _obscurePass = !_obscurePass),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _info!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isSignup ? 'Créer le compte' : 'Se connecter'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _isSignup = !_isSignup;
                            _error = null;
                            _info = null;
                          }),
                          child: Text(_isSignup
                              ? "J'ai déjà un compte"
                              : "Créer un compte"),
                        ),
                        if (!_isSignup)
                          TextButton(
                            onPressed: _resetPassword,
                            child: const Text('Mot de passe oublié'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          "L'app n'a pas encore été configurée pour le cloud.\n\n"
          "Tu peux continuer à l'utiliser en local. Pour activer la "
          "synchronisation, rebuild l'APK avec --dart-define SUPABASE_URL et "
          "--dart-define SUPABASE_ANON_KEY (voir supabase/README.md).",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
