create or replace function public.school_commercial_eusousim_reconcile()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  result jsonb;
begin
  if not public.is_admin_comercial() then raise exception 'not_authorized'; end if;

  update public.followups f
  set status='concluido', completed_at=coalesce(f.completed_at,now())
  from public.eusousim_followup_links x
  where x.followup_id=f.id and x.status='completed' and f.status<>'concluido';

  update public.eusousim_followup_links x
  set status='completed', updated_at=now()
  from public.followups f
  where f.id=x.followup_id and f.status='concluido' and x.status<>'completed';

  result=public.school_commercial_eusousim_status()
    || jsonb_build_object('reconciled_at',now());
  return result;
end $$;

revoke all on function public.school_commercial_eusousim_reconcile() from public,anon;
grant execute on function public.school_commercial_eusousim_reconcile() to authenticated;
