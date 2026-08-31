alter table public.podcast_summaries
  add column if not exists dynamic_sections jsonb not null default '[]'::jsonb;
