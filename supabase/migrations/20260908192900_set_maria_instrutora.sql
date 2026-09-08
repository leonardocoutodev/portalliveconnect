update public.profiles
set role='instrutora'::public.user_role,
    updated_at=now()
where id='bcff953e-61b8-42e8-a46e-e1b967291991';

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','public'
as $$
  select exists(
    select 1 from public.profiles p
    where p.id=auth.uid() and p.active=true
      and p.role in (
        'master_admin'::public.user_role,
        'coadmin'::public.user_role,
        'diretoria'::public.user_role,
        'admin_comercial'::public.user_role,
        'secretaria'::public.user_role,
        'instrutora'::public.user_role,
        'readonly'::public.user_role
      )
  )
$$;

create or replace function public.school_my_access()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $$
declare r public.user_role; a boolean; own boolean;
begin
  select role,active into r,a from public.profiles where id=auth.uid();
  own:=public.is_owner();
  if r is null or coalesce(a,false)=false then
    return jsonb_build_object('ok',false,'role',coalesce(r::text,'none'));
  end if;
  return jsonb_build_object(
    'ok',true,'role',r::text,'owner',own,
    'coadmin',r='coadmin'::public.user_role,
    'instrutora',r='instrutora'::public.user_role,
    'approval_required',false,
    'master',r in ('master_admin'::public.user_role,'coadmin'::public.user_role),
    'secretaria',r in ('master_admin'::public.user_role,'coadmin'::public.user_role,'secretaria'::public.user_role),
    'comercial',r in ('master_admin'::public.user_role,'coadmin'::public.user_role,'admin_comercial'::public.user_role),
    'diretoria',r in ('master_admin'::public.user_role,'coadmin'::public.user_role,'diretoria'::public.user_role),
    'readonly',r='readonly'::public.user_role
  );
end
$$;
