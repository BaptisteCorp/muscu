# Supabase setup

Steps to enable cloud sync for the app.

## 1. Create the project

1. Go to https://supabase.com and sign up (free).
2. Create a new project. Pick a region close to you (Frankfurt for FR users).
3. Wait ~2 min for Postgres to provision.

## 2. Apply the schema

1. In the Supabase dashboard, go to **SQL Editor**.
2. Open `schema.sql` from this folder, copy its full content into the editor, hit **Run**.
3. You should see "Success. No rows returned." — the tables, RLS and indexes are now in place.

## 3. Configure auth

1. Sidebar → **Authentication → Providers**: keep **Email** enabled.
2. **Authentication → Settings**:
   - For dev simplicity, you can disable "Confirm email" so accounts are usable immediately.
   - Add the deep-link redirect URL if you later add Google/Apple sign-in.

## 4. Get the credentials

1. Sidebar → **Project Settings → API**.
2. Copy:
   - **Project URL** → used as `SUPABASE_URL`
   - **anon public** key → used as `SUPABASE_ANON_KEY`
   - Never expose the `service_role` key in the app.

## 5. Build the app with credentials

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
```

Or, easier, create `lib/.env.json`:

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "eyJhbGciOi..."
}
```

Then build with:
```bash
flutter build apk --release --dart-define-from-file=lib/.env.json
```

## 6. First run

- Launch the app → tap the cloud icon in the home settings → **Créer un compte**.
- After login, hit **Synchroniser maintenant** to push your existing local data
  to the server.
- On a second device, sign in with the same account → tap **Synchroniser
  maintenant** → it pulls everything down.

## Privacy note

Each user can only read and write their own rows thanks to Row-Level Security
policies (see end of `schema.sql`). The `anon` key is safe to ship in the
client — it has zero permissions until a user signs in.
