-- pg_cron: worker'ı 15 dakikada bir çağır.
-- keep-alive + snapshot tazelemesi + heartbeat (free plan pause önlemi).
--
-- NOT: Bu dosya projeye özeldir (ref + anon anahtar gömülüdür). anon anahtar
-- Supabase tarafından istemcilere dağıtılmak üzere tasarlanmıştır (public).
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'obs-worker',
  '*/15 * * * *',
  $$
  select net.http_post(
    url := 'https://mqfnecoswcobbwlecmlf.supabase.co/functions/v1/worker',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1xZm5lY29zd2NvYmJ3bGVjbWxmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE2NTMyNzMsImV4cCI6MjEwNzIyOTI3M30.zdQYsvaC48DcBQUOgvH9ewBYf3FOdNbabqX80qtLKY8"}'::jsonb,
    body := '{}',
    timeout_milliseconds := 30000
  );
  $$
);
