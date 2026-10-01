-- Academic360 Web Push / PWA
-- Production VAPID key material is provisioned separately and MUST NOT be committed.

alter table public.ga_push_subscriptions
  add column if not exists institution_id uuid references public.ga_institutions(id) on delete cascade,
  add column if not exists active boolean not null default true,
  add column if not exists last_success_at timestamptz,
  add column if not exists last_error text,
  add column if not exists failure_count integer not null default 0;

create index if not exists ga_push_subscriptions_user_active_idx
  on public.ga_push_subscriptions(user_id, active);
create index if not exists ga_push_subscriptions_institution_idx
  on public.ga_push_subscriptions(institution_id);

create table if not exists public.ga_push_config (
  id smallint primary key default 1 check (id = 1),
  vapid_public_key text not null,
  vapid_private_key text not null,
  vapid_subject text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.ga_push_config enable row level security;
revoke all on table public.ga_push_config from anon, authenticated;
grant all on table public.ga_push_config to service_role;

create table if not exists public.ga_push_history (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.ga_institutions(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  source_id text,
  title text not null,
  body text,
  endpoint text,
  status text not null check (status in ('delivered','gone','failed','skipped')),
  error text,
  created_at timestamptz not null default now()
);
alter table public.ga_push_history enable row level security;
revoke all on table public.ga_push_history from anon, authenticated;
grant all on table public.ga_push_history to service_role;

create index if not exists ga_push_history_institution_created_idx
  on public.ga_push_history(institution_id, created_at desc);
create index if not exists ga_push_history_user_created_idx
  on public.ga_push_history(user_id, created_at desc);
