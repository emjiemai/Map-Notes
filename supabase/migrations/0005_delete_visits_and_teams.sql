-- Lets reps delete their own mistaken pins (visits), auto-cleaning up a
-- place once its last visit is gone, and lets a team be deleted once every
-- *current* member has agreed to it (unanimous consensus, tracked server
-- side so it can't race or be gamed by a single member).

-- ---------------------------------------------------------------------------
-- Deleting your own visit
-- ---------------------------------------------------------------------------
create policy "users can delete their own visits"
  on visits for delete
  to authenticated
  using (auth.uid() = user_id);

-- a place only exists to anchor visits — once the last one is gone, remove it too
create or replace function public.cleanup_orphaned_place()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from visits where place_id = old.place_id) then
    delete from places where id = old.place_id;
  end if;
  return old;
end;
$$;

create trigger on_visit_deleted
  after delete on visits
  for each row execute function public.cleanup_orphaned_place();

-- ---------------------------------------------------------------------------
-- Deleting a team once every current member agrees
-- ---------------------------------------------------------------------------
create table group_delete_votes (
  group_id uuid not null references groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  voted_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

alter table group_delete_votes enable row level security;

create policy "members can see delete votes for their groups"
  on group_delete_votes for select
  to authenticated
  using (exists (
    select 1 from group_members gm
    where gm.group_id = group_delete_votes.group_id and gm.user_id = auth.uid()
  ));

create policy "members can vote to delete a group they belong to"
  on group_delete_votes for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from group_members gm
      where gm.group_id = group_delete_votes.group_id and gm.user_id = auth.uid()
    )
    and not exists (
      select 1 from groups g where g.id = group_delete_votes.group_id and g.is_default
    )
  );

create policy "members can retract their own delete vote"
  on group_delete_votes for delete
  to authenticated
  using (auth.uid() = user_id);

-- a deleted team shouldn't take visit history down with it — just unlink
do $$
declare
  v_conname text;
begin
  select conname into v_conname
  from pg_constraint
  where conrelid = 'visits'::regclass
    and confrelid = 'groups'::regclass
    and contype = 'f';
  if v_conname is not null then
    execute format('alter table visits drop constraint %I', v_conname);
  end if;
end $$;

alter table visits
  add constraint visits_group_id_fkey foreign key (group_id) references groups (id) on delete set null;

create or replace function public.check_group_delete_consensus()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member_count int;
  v_vote_count int;
  v_is_default boolean;
begin
  select is_default into v_is_default from groups where id = new.group_id;
  if coalesce(v_is_default, false) then
    return new; -- safety rail: the shared default team is never auto-deleted
  end if;

  select count(*) into v_member_count from group_members where group_id = new.group_id;
  select count(*) into v_vote_count from group_delete_votes where group_id = new.group_id;

  if v_member_count > 0 and v_vote_count >= v_member_count then
    delete from groups where id = new.group_id;
  end if;

  return new;
end;
$$;

create trigger on_group_delete_vote
  after insert on group_delete_votes
  for each row execute function public.check_group_delete_consensus();
