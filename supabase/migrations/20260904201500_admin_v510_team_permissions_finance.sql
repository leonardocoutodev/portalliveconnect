-- Live Connect Admin V5.10.0 — permissões granulares e financeiro do proprietário

create table if not exists public.school_staff_permissions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  can_view_students boolean not null default false,
  can_edit_students boolean not null default false,
  can_view_finance boolean not null default false,
  can_edit_finance boolean not null default false,
  can_delete_finance boolean not null default false,
  can_view_reports boolean not null default false,
  can_manage_campaigns boolean not null default false,
  can_manage_chat boolean not null default true,
  can_manage_users boolean not null default false,
  can_manage_integrations boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.payments
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists admin_note text,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null,
  add column if not exists deletion_reason text;

create table if not exists public.financial_audit_logs (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid references public.payments(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  note text,
  created_at timestamptz not null default now()
);

-- A migração aplicada em produção também cria/atualiza:
-- school_has_permission(text)
-- school_my_permissions()
-- school_master_set_permissions(uuid,jsonb)
-- school_master_profiles_permissions()
-- school_finance_summary(date,date)
-- school_finance_movements(integer,integer,boolean,text)
-- school_finance_update_payment(uuid,jsonb,text)
-- school_finance_delete_payment(uuid,text)
-- school_finance_restore_payment(uuid,text)
-- school_finance_create_manual_payment(uuid,text,numeric,text,text,timestamptz,date,text)
-- school_finance_audit(integer)
-- school_finance_enrollments(integer)
--
-- O SQL integral da release foi aplicado diretamente no projeto Live Connect Comercial.
