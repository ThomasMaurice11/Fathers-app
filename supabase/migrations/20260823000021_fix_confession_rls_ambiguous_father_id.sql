-- Fix ambiguous father_id in RLS policies that join children in EXISTS subqueries.
-- Affects POST /children/:id/confessions via create_confession() insert into confession_history.

-- ---------------- confession_history ----------------
drop policy if exists confession_history_insert_own on public.confession_history;
create policy confession_history_insert_own
  on public.confession_history for insert
  with check (
    confession_history.father_id = auth.uid()
    and confession_history.child_id in (
      select c.id
      from public.children c
      where c.father_id = auth.uid()
    )
  );

-- ---------------- operations (same pattern) ----------------
drop policy if exists operations_insert_own on public.operations;
create policy operations_insert_own
  on public.operations for insert
  with check (
    operations.father_id = auth.uid()
    and operations.child_id in (
      select c.id
      from public.children c
      where c.father_id = auth.uid()
    )
  );

drop policy if exists operations_update_own on public.operations;
create policy operations_update_own
  on public.operations for update
  using (operations.father_id = auth.uid())
  with check (
    operations.father_id = auth.uid()
    and operations.child_id in (
      select c.id
      from public.children c
      where c.father_id = auth.uid()
    )
  );

-- Qualify columns in create_confession() UPDATE for consistency.
drop function if exists public.create_confession(uuid, timestamptz, text);
create function public.create_confession(
  p_child_id uuid,
  p_confession_at timestamptz,
  p_notes text default null
)
returns table (
  child_id uuid,
  child_name text,
  father_id uuid,
  father_name text,
  confession_id uuid,
  confession_at timestamptz,
  reminder_is_read boolean,
  reminder_snoozed_until date
)
language plpgsql
as $$
declare
  v_father_id uuid := auth.uid();
  v_new_confession_id uuid;
  v_child_name text;
  v_father_name text;
begin
  if v_father_id is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  select c.name, p.full_name
    into v_child_name, v_father_name
  from public.children c
  join public.profiles p on p.id = c.father_id
  where c.id = p_child_id and c.father_id = v_father_id;

  if v_child_name is null then
    raise exception 'Child not found or not owned by the current father' using errcode = '42501';
  end if;

  insert into public.confession_history (father_id, child_id, confession_at, notes)
  values (v_father_id, p_child_id, p_confession_at, p_notes)
  returning id into v_new_confession_id;

  update public.children ch
     set reminder_is_read = false,
         reminder_snoozed_until = null
   where ch.id = p_child_id
     and ch.father_id = v_father_id;

  return query
    select
      p_child_id,
      v_child_name,
      v_father_id,
      v_father_name,
      v_new_confession_id,
      p_confession_at,
      false,
      null::date;
end;
$$;
