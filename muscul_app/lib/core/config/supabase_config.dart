/// Supabase project credentials.
///
/// Override via `--dart-define=SUPABASE_URL=...` and
/// `--dart-define=SUPABASE_ANON_KEY=...` at build time, or just edit the
/// defaults below.
///
/// Find these on https://supabase.com/dashboard → your project → Project
/// Settings → API: copy "Project URL" and "anon public" key.
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// True when both URL and key are set; auth UI hides itself when false so
  /// the app keeps working as a pure local app for dev / before setup.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
