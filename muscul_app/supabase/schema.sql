-- ===========================================================================
-- Muscul — Supabase schema (Postgres)
-- Mirror of the local Drift tables, scoped per user via RLS.
-- Paste this entire file into Supabase Dashboard → SQL Editor → Run.
-- ===========================================================================

-- ----------------------------- exercises -----------------------------------
create table if not exists public.exercises (
  id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  category text not null,
  primary_muscle text not null,
  secondary_muscles text not null default '[]',
  equipment text not null,
  is_custom boolean not null default true,
  default_increment_kg double precision,
  default_rest_seconds integer,
  progression_strategy text not null default 'doubleProgression',
  target_rep_range_min integer not null default 8,
  target_rep_range_max integer not null default 12,
  starting_weight_kg double precision not null default 20.0,
  use_bodyweight boolean not null default false,
  notes text,
  machine_brand_model text,
  machine_settings text,
  photo_path text,
  updated_at timestamptz not null,
  remote_id text,
  deleted_at timestamptz,
  primary key (user_id, id)
);

-- ---------------------------- workout_templates ----------------------------
create table if not exists public.workout_templates (
  id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  notes text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  remote_id text,
  deleted_at timestamptz,
  primary key (user_id, id)
);

-- ----------------------- workout_template_exercises ------------------------
create table if not exists public.workout_template_exercises (
  id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  template_id text not null,
  exercise_id text not null,
  order_index integer not null,
  target_sets integer not null default 3,
  rest_seconds integer,
  primary key (user_id, id)
);
alter table public.workout_template_exercises
  add column if not exists rest_seconds integer;

-- ------------------------ template_exercise_sets ---------------------------
create table if not exists public.template_exercise_sets (
  id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  template_exercise_id text not null,
  set_index integer not null,
  planned_reps integer not null,
  planned_weight_kg double precision,
  primary key (user_id, id)
);

-- ---------------------------- workout_sessions -----------------------------
create table if not exists public.workout_sessions (
  id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  template_id text,
  started_at timestamptz not null,
  ended_at timestamptz,
  notes text,
  planned_for timestamptz,
  updated_at timestamptz not null,
  remote_id text,
  deleted_at timestamptz,
  primary key (user_id, id)
);

-- ---------------------------- session_exercises ----------------------------
create table if not exists public.session_exercises (
  id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id text not null,
  exercise_id text not null,
  order_index integer not null,
  rest_seconds integer,
  superset_group_id text,
  note text,
  replaced_from_session_exercise_id text,
  -- Used to detect updates from another device.
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

-- ------------------------------- set_entries -------------------------------
create table if not exists public.set_entries (
  id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_exercise_id text not null,
  set_index integer not null,
  reps integer not null,
  weight_kg double precision not null,
  rpe integer,
  rir integer,
  rest_seconds integer not null default 0,
  is_warmup boolean not null default false,
  is_failure boolean not null default false,
  completed_at timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

-- ------------------------------- user_settings -----------------------------
create table if not exists public.user_settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  default_increment_kg double precision not null default 2.5,
  weight_unit text not null default 'kg',
  default_rest_seconds integer not null default 120,
  use_rir_instead_of_rpe boolean not null default false,
  user_bodyweight_kg double precision,
  theme_mode text not null default 'system',
  updated_at timestamptz not null default now(),
  primary key (user_id)
);

-- ---------------------------- bodyweight_entries ---------------------------
create table if not exists public.bodyweight_entries (
  user_id uuid not null references auth.users(id) on delete cascade,
  date text not null,        -- 'YYYY-MM-DD'
  weight_kg double precision not null,
  note text,
  updated_at timestamptz not null,
  primary key (user_id, date)
);

-- ===========================================================================
-- Row-Level Security: each user can only touch their own rows.
-- ===========================================================================

alter table public.exercises enable row level security;
alter table public.workout_templates enable row level security;
alter table public.workout_template_exercises enable row level security;
alter table public.template_exercise_sets enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.session_exercises enable row level security;
alter table public.set_entries enable row level security;
alter table public.user_settings enable row level security;
alter table public.bodyweight_entries enable row level security;

do $$
declare
  t text;
  policy_kinds text[] := array['select', 'insert', 'update', 'delete'];
  k text;
begin
  for t in
    select unnest(array[
      'exercises',
      'workout_templates',
      'workout_template_exercises',
      'template_exercise_sets',
      'workout_sessions',
      'session_exercises',
      'set_entries',
      'user_settings',
      'bodyweight_entries'
    ])
  loop
    foreach k in array policy_kinds
    loop
      execute format(
        'drop policy if exists %I on public.%I',
        format('%s_own_%s', t, k),
        t
      );
      if k = 'insert' then
        execute format(
          'create policy %I on public.%I for %s with check (user_id = auth.uid())',
          format('%s_own_%s', t, k),
          t,
          k
        );
      else
        execute format(
          'create policy %I on public.%I for %s using (user_id = auth.uid())%s',
          format('%s_own_%s', t, k),
          t,
          k,
          case
            when k = 'update' then ' with check (user_id = auth.uid())'
            else ''
          end
        );
      end if;
    end loop;
  end loop;
end$$;

-- ===========================================================================
-- Helpful indexes for sync queries.
-- ===========================================================================

create index if not exists exercises_user_updated_idx
  on public.exercises (user_id, updated_at desc);
create index if not exists templates_user_updated_idx
  on public.workout_templates (user_id, updated_at desc);
create index if not exists template_exercises_user_idx
  on public.workout_template_exercises (user_id, template_id);
create index if not exists sessions_user_updated_idx
  on public.workout_sessions (user_id, updated_at desc);
create index if not exists session_exercises_user_idx
  on public.session_exercises (user_id, session_id);
create index if not exists set_entries_user_idx
  on public.set_entries (user_id, session_exercise_id);
create index if not exists bodyweight_user_idx
  on public.bodyweight_entries (user_id, date);
