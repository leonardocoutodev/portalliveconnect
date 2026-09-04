-- Live Connect V5.8.2 — Lico comercial + continuidade de sessão
alter table public.commercial_chat_sessions add column if not exists suggestion_requested boolean;
alter table public.commercial_chat_sessions add column if not exists commercial_mode text;
alter table public.commercial_chat_sessions add column if not exists preferred_payment_method text;
alter table public.commercial_chat_sessions add column if not exists resume_count integer not null default 0;
alter table public.commercial_chat_sessions add column if not exists last_resumed_at timestamptz;
alter table public.commercial_chat_sessions add column if not exists free_course_fallback_used boolean not null default false;
