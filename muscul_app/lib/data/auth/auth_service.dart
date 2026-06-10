import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';

/// Wraps the Supabase auth client with the surface area we need.
class AuthService {
  AuthService();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser =>
      SupabaseConfig.isConfigured ? _client.auth.currentUser : null;

  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get onAuthChange =>
      SupabaseConfig.isConfigured
          ? _client.auth.onAuthStateChange
          : const Stream.empty();

  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signUp(email: email, password: password);
    if (res.user == null) {
      throw const AuthException('Compte non créé');
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth
        .signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    if (!SupabaseConfig.isConfigured) return;
    await _client.auth.signOut();
  }

  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  /// Supprime DÉFINITIVEMENT le compte courant et, par cascade côté Postgres
  /// (FK `on delete cascade` vers auth.users), toutes ses données cloud — puis
  /// déconnecte. Le client ne pouvant pas supprimer sa propre ligne auth, on
  /// appelle la fonction SECURITY DEFINER `delete_current_user`
  /// (cf. supabase/schema.sql). Le nettoyage de la base LOCALE est fait par
  /// l'appelant (AppDatabase.wipeUserData).
  Future<void> deleteAccount() async {
    if (!SupabaseConfig.isConfigured) return;
    await _client.rpc('delete_current_user');
    await _client.auth.signOut();
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Reactive auth state — emits whenever the user signs in / out.
final authChangesProvider = StreamProvider<AuthState?>((ref) {
  final svc = ref.watch(authServiceProvider);
  if (!SupabaseConfig.isConfigured) {
    return Stream<AuthState?>.value(null);
  }
  return svc.onAuthChange.cast<AuthState?>();
});

final currentUserProvider = Provider<User?>((ref) {
  // Re-evaluate whenever the auth stream pulses.
  ref.watch(authChangesProvider);
  return ref.watch(authServiceProvider).currentUser;
});
