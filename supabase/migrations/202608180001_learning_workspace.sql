begin;

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

alter table public.podcasts add column if not exists category_id text;

insert into public.categories (user_id, id, name, symbol_name, color_token, sort_order)
select distinct
  p.user_id,
  case lower(coalesce(p.category, 'General'))
    when 'self improvement' then 'self-improvement'
    else regexp_replace(lower(coalesce(p.category, 'General')), '[^a-z0-9]+', '-', 'g')
  end,
  coalesce(nullif(trim(p.category), ''), 'General'),
  'book.closed.fill',
  'blue',
  0
from public.podcasts p
where p.user_id is not null
on conflict (user_id, id) do nothing;

update public.podcasts
set category_id = case lower(coalesce(category, 'General'))
  when 'self improvement' then 'self-improvement'
  else regexp_replace(lower(coalesce(category, 'General')), '[^a-z0-9]+', '-', 'g')
end
where category_id is null;

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
  generated_at timestamptz not null default now(),
  transcript_source text not null,
  model text not null,
  action_plan_xp_granted boolean not null default false,
  primary key (user_id, podcast_id)
);

alter table public.categories enable row level security;
alter table public.daily_learning_activity enable row level security;
alter table public.podcast_summaries enable row level security;

drop policy if exists "categories_owner_all" on public.categories;
create policy "categories_owner_all" on public.categories for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "activity_owner_all" on public.daily_learning_activity;
create policy "activity_owner_all" on public.daily_learning_activity for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "summaries_owner_all" on public.podcast_summaries;
create policy "summaries_owner_all" on public.podcast_summaries for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.reassign_and_delete_category(
  category_to_delete text,
  replacement_category text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid := auth.uid();
  used_count integer;
  category_count integer;
begin
  if owner_id is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from categories where user_id = owner_id and id = category_to_delete) then
    raise exception 'Category not found';
  end if;
  select count(*) into category_count from categories where user_id = owner_id;
  if category_count <= 1 then raise exception 'The final category cannot be deleted'; end if;
  select count(*) into used_count from podcasts where user_id = owner_id and category_id = category_to_delete;
  if used_count > 0 then
    if replacement_category is null or replacement_category = category_to_delete or
       not exists (select 1 from categories where user_id = owner_id and id = replacement_category) then
      raise exception 'A valid replacement category is required';
    end if;
    update podcasts
      set category_id = replacement_category,
          category = (select name from categories where user_id = owner_id and id = replacement_category)
      where user_id = owner_id and category_id = category_to_delete;
  end if;
  delete from categories where user_id = owner_id and id = category_to_delete;
end;
$$;

revoke all on function public.reassign_and_delete_category(text, text) from public;
grant execute on function public.reassign_and_delete_category(text, text) to authenticated;

commit;
