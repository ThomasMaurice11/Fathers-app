-- ============================================================
-- 000013: extend get_child_detail() with operations[]
-- ============================================================

create or replace function public.get_child_detail(p_child_id uuid)
returns json
language plpgsql
stable
as $$
declare
  v_result json;
begin
  if not exists (
    select 1 from public.children c
    where c.id = p_child_id and c.father_id = auth.uid()
  ) then
    return null;
  end if;

  select json_build_object(
    'id', c.id,
    'first_name', c.first_name,
    'last_name', c.last_name,
    'birthday', c.birthday,
    'age', public.calculate_age(c.birthday),
    'stage_id', c.stage_id,
    'stage', s.name,
    'reminder_is_read', c.reminder_is_read,
    'reminder_snoozed_until', c.reminder_snoozed_until,
    'latest_confession_at', l.latest_confession_at,
    'days_since_last_confession', case
      when l.latest_confession_at is null then null
      else extract(day from (now() - l.latest_confession_at))::integer end,
    'needs_confession', (
      l.latest_confession_at is null
      or extract(day from (now() - l.latest_confession_at)) > 27
    ),
    'confession_status', case
      when l.latest_confession_at is null then 'NO_CONFESSION_RECORDED'
      when extract(day from (now() - l.latest_confession_at)) > 27 then 'OVERDUE'
      else 'UP_TO_DATE'
    end,
    'confession_history', (
      select coalesce(json_agg(ch order by ch.confession_at desc), '[]'::json)
      from (
        select id, confession_at, notes, created_at
        from public.confession_history
        where child_id = c.id
        order by confession_at desc
      ) ch
    ),
    'operations', (
      select coalesce(json_agg(op order by op.operation_date desc), '[]'::json)
      from (
        select id, type, note, operation_date, created_at, updated_at
        from public.operations
        where child_id = c.id
        order by operation_date desc
      ) op
    )
  )
  into v_result
  from public.children c
  join public.stages s on s.id = c.stage_id
  left join (
    select child_id, max(confession_at) as latest_confession_at
    from public.confession_history
    where child_id = p_child_id
    group by child_id
  ) l on l.child_id = c.id
  where c.id = p_child_id and c.father_id = auth.uid();

  return v_result;
end;
$$;
