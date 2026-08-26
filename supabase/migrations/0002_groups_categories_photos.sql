-- Adds: groups (teams reps post to), place categories (for filter chips),
-- and multi-photo support on visits. Extends log_visit() accordingly.

-- ---------------------------------------------------------------------------
-- groups: lightweight teams. Membership is used for "post to group" / feed
-- display, not as a hard visibility boundary — every rep can still see every
-- pin (duplicates being the enemy matters company-wide, not per-team).
-- ---------------------------------------------------------------------------
create table groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid references auth.users (id) default auth.uid(),
  created_at timestamptz not null default now()
);

create table group_members (
  group_id uuid not null references groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

alter table groups enable row level security;
alter table group_members enable row level security;

create policy "groups are readable by any authenticated user"
  on groups for select to authenticated using (true);

create policy "users can create groups"
  on groups for insert to authenticated with check (auth.uid() = created_by);

create policy "group membership is readable by any authenticated user"
  on group_members for select to authenticated using (true);

create policy "users can join groups"
  on group_members for insert to authenticated with check (auth.uid() = user_id);

-- creator auto-joins their own group
create or replace function public.handle_new_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.group_members (group_id, user_id) values (new.id, new.created_by);
  return new;
end;
$$;

create trigger on_group_created
  after insert on groups
  for each row execute function public.handle_new_group();

-- every new user gets a starter group so "post to group" always has an option
create or replace function public.handle_new_user_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
begin
  insert into public.groups (name, created_by) values ('My Team', new.id) returning id into v_group_id;
  return new;
end;
$$;

create trigger on_auth_user_created_group
  after insert on auth.users
  for each row execute function public.handle_new_user_group();

-- ---------------------------------------------------------------------------
-- places: category for filter chips
-- ---------------------------------------------------------------------------
alter table places
  add column category text not null default 'other'
    check (category in ('retail', 'horeca', 'distributor', 'other'));

-- ---------------------------------------------------------------------------
-- visits: which group it was posted to, and up to a handful of photo URLs
-- ---------------------------------------------------------------------------
alter table visits add column group_id uuid references groups (id);
alter table visits add column photo_urls text[] not null default '{}';

-- old single photo_url column is superseded by photo_urls
alter table visits drop column photo_url;

-- ---------------------------------------------------------------------------
-- storage: a public bucket for visit photos
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('visit-photos', 'visit-photos', true)
on conflict (id) do nothing;

create policy "authenticated users can upload visit photos"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'visit-photos');

create policy "anyone can view visit photos"
  on storage.objects for select
  using (bucket_id = 'visit-photos');

-- ---------------------------------------------------------------------------
-- log_visit: extended with category, group, and photos. Same dedupe logic.
-- ---------------------------------------------------------------------------
drop function if exists log_visit(double precision, double precision, text, text, text, text, double precision);

create or replace function log_visit(
  p_lat double precision,
  p_lng double precision,
  p_name text,
  p_address text default null,
  p_comment text default null,
  p_category text default 'other',
  p_group_id uuid default null,
  p_photo_urls text[] default '{}',
  p_radius_m double precision default 50
)
returns table (place_id uuid, was_new_place boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_place_id uuid;
  v_was_new boolean := false;
  v_point geography := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
begin
  select id into v_place_id
  from places
  where st_dwithin(location, v_point, p_radius_m)
  order by st_distance(location, v_point)
  limit 1;

  if v_place_id is null then
    insert into places (name, address, lat, lng, category, created_by)
    values (p_name, p_address, p_lat, p_lng, p_category, auth.uid())
    returning id into v_place_id;
    v_was_new := true;
  end if;

  insert into visits (place_id, user_id, comment, group_id, photo_urls)
  values (v_place_id, auth.uid(), p_comment, p_group_id, p_photo_urls);

  return query select v_place_id, v_was_new;
end;
$$;

grant execute on function log_visit to authenticated;
