-- Bug fix: every new signup was creating its OWN "My Team" group (via
-- handle_new_user_group in 0002), so reps never actually landed in the same
-- team as each other. This makes one shared default group that every new
-- user joins, and consolidates any per-user groups already created by the
-- old trigger into it.

alter table groups add column if not exists is_default boolean not null default false;

do $$
declare
  v_default_id uuid;
begin
  -- earliest-created group becomes the canonical shared team
  select id into v_default_id from groups order by created_at asc limit 1;

  if v_default_id is not null then
    update groups set is_default = true where id = v_default_id;

    -- point any visits posted to a duplicate group at the default instead
    update visits set group_id = v_default_id
      where group_id is not null and group_id <> v_default_id;

    -- merge memberships into the default group, skipping ones already there
    insert into group_members (group_id, user_id, joined_at)
    select v_default_id, user_id, min(joined_at)
    from group_members
    where group_id <> v_default_id
    group by user_id
    on conflict (group_id, user_id) do nothing;

    delete from group_members where group_id <> v_default_id;
    delete from groups where id <> v_default_id;
  end if;
end $$;

create or replace function public.handle_new_user_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
begin
  select id into v_group_id from groups where is_default = true limit 1;

  if v_group_id is null then
    insert into groups (name, created_by, is_default)
    values ('My Team', new.id, true)
    returning id into v_group_id;
  end if;

  insert into group_members (group_id, user_id)
  values (v_group_id, new.id)
  on conflict (group_id, user_id) do nothing;

  return new;
end;
$$;
