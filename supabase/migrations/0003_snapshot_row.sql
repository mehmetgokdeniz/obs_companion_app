-- Düzeltme: 0001_init snapshot satırını INSERT etmiyordu; kalıcılık PATCH ile
-- yapılıyor ve PostgREST satır yoksa200 dönüp PATCH'i sessizce yutuyordu.
-- Sonuç: snapshot DB'ye hiç yazılmıyordu (status'te lastRefresh: null, /all her
-- çağrıda yeniden tarama). Satır açılır; eski tarih bilinçlidir ki ilk /all
-- tazelemeyi tetiklesin.
insert into public.snapshot (id, payload, fetched_at)
values (true, '{}'::jsonb, timestamptz '1970-01-01T00:00:00Z')
on conflict (id) do nothing;
