create table if not exists public.ga_sso_links (
  id uuid primary key default gen_random_uuid(),
  source_project_ref text not null,
  source_user_id uuid not null,
  target_user_id uuid not null references auth.users(id) on delete cascade,
  active boolean not null default true,
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  unique (source_project_ref, source_user_id)
);

alter table public.ga_sso_links enable row level security;
revoke all on table public.ga_sso_links from anon, authenticated;
grant all on table public.ga_sso_links to service_role;

insert into public.ga_sso_links (source_project_ref, source_user_id, target_user_id, active)
values (
  'utfxjadpntvbrhnkghbf',
  '42126430-9593-40ee-9ef1-5380842f6fb0',
  '1708933f-cdfc-4867-8874-3e7abef42e4f',
  true
)
on conflict (source_project_ref, source_user_id)
do update set target_user_id = excluded.target_user_id, active = true;
