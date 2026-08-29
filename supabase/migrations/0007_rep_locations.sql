-- Real-time-ish location trail for transportation reimbursement: each rep's
-- device logs a point whenever it's moved a meaningful distance (not on a
-- fixed timer — see LocationTracker in the app), so a stationary rep never
-- accumulates GPS-jitter "distance". Points are never edited or deleted by
-- anyone from the client — this exists specifically to be a trustworthy
-- record, so unlike visits there's no self-service delete here.

create table rep_locations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  recorded_at timestamptz not null default now()
);

create index rep_locations_user_time_idx on rep_locations (user_id, recorded_at);

alter table rep_locations enable row level security;

-- readable by any authenticated user, same broad-visibility pattern as
-- places/visits/groups in this app — not just the rep who logged it
create policy "authenticated users can read location points"
  on rep_locations for select
  to authenticated
  using (true);

create policy "reps can log their own location points"
  on rep_locations for insert
  to authenticated
  with check (auth.uid() = user_id);

-- deliberately no update/delete policy at all
