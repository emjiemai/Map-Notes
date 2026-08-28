-- Replaces the generic starting categories (retail/horeca/distributor)
-- with what actually matters for targeting: hotel, medical, restaurant.
-- "Other" stays as the catch-all for everything else — the whole point is
-- that those aren't priority targets.

do $$
declare
  v_conname text;
begin
  select conname into v_conname
  from pg_constraint
  where conrelid = 'places'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%category%';
  if v_conname is not null then
    execute format('alter table places drop constraint %I', v_conname);
  end if;
end $$;

update places set category = 'restaurant' where category = 'horeca';
update places set category = 'other' where category in ('retail', 'distributor');

alter table places
  add constraint places_category_check
  check (category in ('hotel', 'medical', 'restaurant', 'other'));
