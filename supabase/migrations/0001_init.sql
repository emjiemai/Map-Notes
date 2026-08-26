-- Map Notes: initial schema
-- Places = canonical locations (deduped). Visits = one row per rep's pin, never deduped.

create extension if not exists postgis;

-- ---------------------------------------------------------------------------
-- profiles: public-readable display info for auth.users (auth.users itself
-- isn't queryable by other users, so we mirror what the feed needs to show).
-- ---------------------------------------------------------------------------
create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now()
);

alter table profiles enable row level security;

create policy "profiles are readable by any authenticated user"
  on profiles for select
  to authenticated
  using (true);

create policy "users can update their own profile"
  on profiles for update
  to authenticated
  using (auth.uid() = id);

-- auto-create a profile row whenever someone signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.phone, new.email));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- places: canonical locations. lat/lng are the columns the app reads/writes;
-- `location` is a generated geography column kept only for spatial indexing
-- and the dedupe query in log_visit() below.
-- ---------------------------------------------------------------------------
create table places (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text,
  lat double precision not null,
  lng double precision not null,
  location geography(point, 4326)
    generated always as (st_setsrid(st_makepoint(lng, lat), 4326)::geography) stored,
  created_by uuid references auth.users (id) default auth.uid(),
  created_at timestamptz not null default now()
);

create index places_location_idx on places using gist (location);

alter table places enable row level security;

create policy "places are readable by any authenticated user"
  on places for select
  to authenticated
  using (true);

-- Direct inserts are allowed as a safety net, but the app should always go
-- through log_visit() below so the dedupe check actually runs.
create policy "users can insert places they own"
  on places for insert
  to authenticated
  with check (auth.uid() = created_by);

-- ---------------------------------------------------------------------------
-- visits: one row per rep visit/pin. Always insert, never dedupe these.
-- ---------------------------------------------------------------------------
create table visits (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references places (id) on delete cascade,
  user_id uuid not null references auth.users (id) default auth.uid(),
  comment text,
  photo_url text,
  created_at timestamptz not null default now()
);

create index visits_place_id_idx on visits (place_id);
create index visits_user_id_idx on visits (user_id);
create index visits_created_at_idx on visits (created_at desc);

alter table visits enable row level security;

create policy "visits are readable by any authenticated user"
  on visits for select
  to authenticated
  using (true);

create policy "users can insert their own visits"
  on visits for insert
  to authenticated
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- log_visit: the one function the app should call to record a pin.
--
-- Looks for an existing place within `p_radius_m` meters. If one exists,
-- the visit is attached to it instead of creating a near-duplicate place.
-- Otherwise a new place is created first. This is the dedupe strategy:
-- Places are deduped by proximity, Visits never are.
-- ---------------------------------------------------------------------------
create or replace function log_visit(
  p_lat double precision,
  p_lng double precision,
  p_name text,
  p_address text default null,
  p_comment text default null,
  p_photo_url text default null,
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
    insert into places (name, address, lat, lng, created_by)
    values (p_name, p_address, p_lat, p_lng, auth.uid())
    returning id into v_place_id;
    v_was_new := true;
  end if;

  insert into visits (place_id, user_id, comment, photo_url)
  values (v_place_id, auth.uid(), p_comment, p_photo_url);

  return query select v_place_id, v_was_new;
end;
$$;

grant execute on function log_visit to authenticated;
