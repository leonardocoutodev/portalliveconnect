alter table public.leads
  add column if not exists whatsapp_normalized text
  generated always as (regexp_replace(coalesce(whatsapp,''),'\D','','g')) stored;

create unique index if not exists leads_whatsapp_normalized_uidx
  on public.leads (whatsapp_normalized)
  where whatsapp_normalized <> '';

create table if not exists public.eusousim_integration_endpoints (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'eusousim' check (provider='eusousim'),
  name text not null unique,
  endpoint_key_hash text not null unique check (endpoint_key_hash ~ '^[a-f0-9]{64}$'),
  source_label text not null default 'Eu Sou SIM',
  stage_mapping jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.eusousim_events (
  id uuid primary key default gen_random_uuid(),
  endpoint_id uuid not null references public.eusousim_integration_endpoints(id) on delete cascade,
  dedupe_key text not null,
  provider_event_id text,
  event_type text not null default 'unknown',
  external_lead_id text,
  payload_sha256 text not null check (payload_sha256 ~ '^[a-f0-9]{64}$'),
  payload jsonb not null,
  status text not null default 'received' check (status in ('received','processed','ignored','failed')),
  lead_id uuid references public.leads(id) on delete set null,
  error_code text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique(endpoint_id,dedupe_key)
);

create table if not exists public.eusousim_lead_links (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'eusousim',
  external_lead_id text not null,
  lead_id uuid not null references public.leads(id) on delete cascade,
  last_event_type text,
  last_synced_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(provider,external_lead_id)
);

create table if not exists public.eusousim_followup_links (
  id uuid primary key default gen_random_uuid(),
  endpoint_id uuid not null references public.eusousim_integration_endpoints(id) on delete cascade,
  external_lead_id text not null,
  lead_id uuid not null references public.leads(id) on delete cascade,
  followup_id uuid not null references public.followups(id) on delete cascade,
  scheduled_at timestamptz,
  status text not null default 'scheduled' check(status in ('scheduled','needs_time','completed','cancelled')),
  last_event_type text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(endpoint_id,external_lead_id)
);

create index if not exists eusousim_events_received_idx on public.eusousim_events(received_at desc);
create index if not exists eusousim_events_status_idx on public.eusousim_events(status,received_at desc);
create index if not exists eusousim_lead_links_lead_idx on public.eusousim_lead_links(lead_id);
create index if not exists eusousim_followup_links_lead_idx on public.eusousim_followup_links(lead_id);

alter table public.eusousim_integration_endpoints enable row level security;
alter table public.eusousim_events enable row level security;
alter table public.eusousim_lead_links enable row level security;
alter table public.eusousim_followup_links enable row level security;

revoke all on public.eusousim_integration_endpoints from anon,authenticated;
revoke all on public.eusousim_events from anon,authenticated;
revoke all on public.eusousim_lead_links from anon,authenticated;
revoke all on public.eusousim_followup_links from anon,authenticated;
grant all on public.eusousim_integration_endpoints to service_role;
grant all on public.eusousim_events to service_role;
grant all on public.eusousim_lead_links to service_role;
grant all on public.eusousim_followup_links to service_role;

insert into public.eusousim_integration_endpoints
  (name,endpoint_key_hash,source_label,stage_mapping,is_active)
values (
  'Eu Sou SIM - Live Connect',
  '4a48b8fa0d6b48bab6bcefc8cee2e9f2d7ff1d8a2951d0a4fdaaed67aa25d6fb',
  'Eu Sou SIM',
  '{
    "17576":"novo_lead",
    "17577":"contato_realizado",
    "17578":"retorno_agendado",
    "17579":"em_atendimento",
    "17580":"retorno_agendado",
    "17581":"matricula_confirmada",
    "LEADS":"novo_lead",
    "EM CONTATO":"contato_realizado",
    "VISITA AGENDADA":"retorno_agendado",
    "COMPARECEU":"em_atendimento",
    "REAGENDAMENTO":"retorno_agendado",
    "MATRICULADO":"matricula_confirmada"
  }'::jsonb,
  true
)
on conflict(name) do update set
  endpoint_key_hash=excluded.endpoint_key_hash,
  stage_mapping=excluded.stage_mapping,
  source_label=excluded.source_label,
  is_active=true,
  updated_at=now();

create or replace function public.school_commercial_eusousim_status()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  result jsonb;
begin
  if not public.is_staff() then raise exception 'not_authorized'; end if;
  select jsonb_build_object(
    'active',coalesce((select bool_or(is_active) from public.eusousim_integration_endpoints),false),
    'events_total',(select count(*) from public.eusousim_events),
    'events_today',(select count(*) from public.eusousim_events where received_at::date=(now() at time zone 'America/Bahia')::date),
    'failed',(select count(*) from public.eusousim_events where status='failed'),
    'leads_linked',(select count(distinct lead_id) from public.eusousim_lead_links),
    'appointments_open',(select count(*) from public.eusousim_followup_links where status in ('scheduled','needs_time')),
    'last_event_at',(select max(received_at) from public.eusousim_events)
  ) into result;
  return result;
end $$;

revoke all on function public.school_commercial_eusousim_status() from public,anon;
grant execute on function public.school_commercial_eusousim_status() to authenticated;
