-- ============================================================
-- 000020: handle_new_user reads role from Auth user metadata
-- ============================================================
-- Admin-provisioned users pass role (FATHER | ADMIN) in
-- raw_user_meta_data. Invalid anything else / missing → FATHER.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta_role text := new.raw_user_meta_data->>'role';
  resolved_role public.user_role := 'FATHER';
begin
  if meta_role in ('FATHER', 'ADMIN') then
    resolved_role := meta_role::public.user_role;
  end if;

  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    new.email,
    resolved_role
  )
  on conflict (id) do nothing;

  return new;
end;
$$;
