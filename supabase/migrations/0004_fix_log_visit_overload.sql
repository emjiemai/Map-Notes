-- 0002's `drop function if exists log_visit(double precision, double
-- precision, text, text, text, text, double precision)` had a mismatched
-- signature (7 args listed; the actual 0001 function took 6), so IF EXISTS
-- silently no-opped instead of dropping it. That left the old 6-arg
-- log_visit() sitting alongside the new 9-arg one. Drop every overload by
-- name (whatever its exact signature turned out to be) and recreate the one
-- correct version.

do $$
declare
  r record;
begin
  for r in
    select oid::regprocedure::text as sig
    from pg_proc
    where proname = 'log_visit' and pronamespace = 'public'::regnamespace
  loop
    execute format('drop function %s', r.sig);
  end loop;
end $$;

create function log_visit(
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
