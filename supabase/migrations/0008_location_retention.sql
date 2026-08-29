-- Keep rep_locations to a rolling 14-day window — daily route history is
-- useful, an unbounded, ever-growing GPS log is not.

create extension if not exists pg_cron;

select cron.schedule(
  'purge-old-rep-locations',
  '0 3 * * *', -- daily at 03:00 UTC
  $$ delete from rep_locations where recorded_at < now() - interval '14 days' $$
);
