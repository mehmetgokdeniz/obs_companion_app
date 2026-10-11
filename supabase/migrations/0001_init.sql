-- OBS Companion Supabase şeması.
-- Tüm tablolar RLS açık + policy yok: yalnız service_role (edge function
-- içinden) okur/yazar; anon/authenticated anahtarlarla erişim yoktur.

create table if not exists public.session_state (
  id boolean primary key default true check (id),
  cookie text,
  saved_at timestamptz,
  session_alive boolean not null default false,
  needs_manual_captcha boolean not null default false,
  student_name text,
  last_error text,
  updated_at timestamptz not null default now()
);

create table if not exists public.snapshot (
  id boolean primary key default true check (id),
  payload jsonb not null,
  fetched_at timestamptz not null default now()
);

-- Free plan pause önleme: worker her çalıştırmada bu satırı tazeler.
create table if not exists public.heartbeat (
  id boolean primary key default true check (id),
  at timestamptz not null default now()
);

-- Tek işçi kilidi: worker, all?refresh=1 ve manel captcha girişi aynı anda
-- OBS'e ikinci oturum açmasın. Sunucusuz ortamda oturum kilidi yerine
-- süreli kira (lease) deseni kullanılır.
create table if not exists public.worker_lease (
  id boolean primary key default true check (id),
  owner text,
  expires_at timestamptz
);

-- Manuel captcha: OCR çözemezse hazırlanan giriş formunun gizli alanları,
-- o formun çerezi ve görseli birlikte saklanır (form ile cookie eşleşmek zorunda).
create table if not exists public.captcha_challenge (
  id uuid primary key default gen_random_uuid(),
  cookie text not null,
  view_state text not null default '',
  view_state_generator text not null default '',
  request_verification_token text not null default '',
  image_base64 text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);

alter table public.session_state enable row level security;
alter table public.snapshot enable row level security;
alter table public.heartbeat enable row level security;
alter table public.worker_lease enable row level security;
alter table public.captcha_challenge enable row level security;

insert into public.heartbeat (id) values (true) on conflict (id) do nothing;
insert into public.worker_lease (id) values (true) on conflict (id) do nothing;
insert into public.session_state (id) values (true) on conflict (id) do nothing;

-- Kiralama: boşsa veya süresi dolmuşsa kapar; sahibi yenilemek serbesttir.
create or replace function public.try_acquire_lease(p_owner text, p_seconds int)
returns boolean
language plpgsql
as $$
begin
  update public.worker_lease
     set owner = p_owner,
         expires_at = now() + make_interval(secs => p_seconds)
   where id = true
     and (owner = p_owner or owner is null or expires_at is null or expires_at < now());
  return found;
end;
$$;

create or replace function public.release_lease(p_owner text)
returns void
language sql
as $$
  update public.worker_lease
     set owner = null,
         expires_at = null
   where id = true and owner = p_owner;
$$;
