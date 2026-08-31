begin;

alter table public.podcasts add column if not exists completed_at timestamptz;
alter table public.podcasts add column if not exists scheduled_at timestamptz;
alter table public.podcasts add column if not exists collection_ids uuid[] not null default '{}';

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

alter table public.podcast_collections enable row level security;

drop policy if exists "podcast_collections_owner_all" on public.podcast_collections;
create policy "podcast_collections_owner_all" on public.podcast_collections for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);

commit;
