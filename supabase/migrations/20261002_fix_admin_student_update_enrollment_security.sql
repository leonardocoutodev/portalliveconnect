-- Fix enrollment editor permission chain.
-- admin_student_update_enrollment validates school_has_permission('edit_students')
-- before doing any write, but it also calls the internal privileged helper
-- ensure_free_registration_form_internal. Running as SECURITY INVOKER caused
-- authenticated Admin users to fail at that internal call with SQLSTATE 42501.

alter function public.admin_student_update_enrollment(uuid, jsonb) security definer;

revoke all on function public.admin_student_update_enrollment(uuid, jsonb) from public;
revoke all on function public.admin_student_update_enrollment(uuid, jsonb) from anon;
grant execute on function public.admin_student_update_enrollment(uuid, jsonb) to authenticated;
grant execute on function public.admin_student_update_enrollment(uuid, jsonb) to service_role;
