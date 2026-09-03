begin;

-- Bring the original podcasts table up to the contract used by every client.
-- The project started with user_id as text; UUID ownership is required for
-- reliable auth.uid() RLS checks on macOS, iOS, and Android.
alter table public.podcasts
  alter column user_id type uuid using nullif(user_id, '')::uuid;

alter table public.podcasts add column if not exists category_id text;
alter table public.podcasts add column if not exists completed_at timestamptz;
alter table public.podcasts add column if not exists scheduled_at timestamptz;
alter table public.podcasts add column if not exists collection_ids uuid[] not null default '{}';
alter table public.podcasts add column if not exists duration double precision;

alter table public.podcasts enable row level security;
drop policy if exists "podcasts_owner_all" on public.podcasts;
create policy "podcasts_owner_all" on public.podcasts for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);

create table if not exists public.categories (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null check (length(trim(name)) > 0),
  symbol_name text not null,
  color_token text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, id),
  unique (user_id, name)
);

create table if not exists public.daily_learning_activity (
  user_id uuid not null references auth.users(id) on delete cascade,
  date_key text not null,
  watched_seconds double precision not null default 0,
  sessions integer not null default 0,
  goal_minutes double precision not null,
  goal_completed boolean not null default false,
  xp_earned integer not null default 0,
  completed_podcast_ids uuid[] not null default '{}',
  xp_awarded_minutes integer not null default 0,
  daily_goal_xp_awarded boolean not null default false,
  weekly_goal_xp_awarded boolean not null default false,
  primary key (user_id, date_key)
);

create table if not exists public.podcast_summaries (
  user_id uuid not null references auth.users(id) on delete cascade,
  podcast_id uuid not null,
  brief text not null,
  key_topics jsonb not null default '[]'::jsonb,
  major_takeaways jsonb not null default '[]'::jsonb,
  action_plan jsonb not null default '[]'::jsonb,
  dynamic_sections jsonb not null default '[]'::jsonb,
  generated_at timestamptz not null default now(),
  transcript_source text not null,
  model text not null,
  action_plan_xp_granted boolean not null default false,
  primary key (user_id, podcast_id)
);

create table if not exists public.podcast_collections (
  user_id uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  title text not null check (length(trim(title)) > 0),
  source_playlist_id text not null,
  source_url text not null,
  date_added timestamptz not null default now(),
  sort_order integer not null default 0,
  video_ids text[] not null default '{}',
  primary key (user_id, id),
  unique (user_id, source_playlist_id)
);

alter table public.categories enable row level security;
alter table public.daily_learning_activity enable row level security;
alter table public.podcast_summaries enable row level security;
alter table public.podcast_collections enable row level security;

drop policy if exists "categories_owner_all" on public.categories;
create policy "categories_owner_all" on public.categories for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "activity_owner_all" on public.daily_learning_activity;
create policy "activity_owner_all" on public.daily_learning_activity for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "summaries_owner_all" on public.podcast_summaries;
create policy "summaries_owner_all" on public.podcast_summaries for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "podcast_collections_owner_all" on public.podcast_collections;
create policy "podcast_collections_owner_all" on public.podcast_collections for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);

commit;
