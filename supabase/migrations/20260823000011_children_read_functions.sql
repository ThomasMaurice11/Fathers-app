-- ============================================================
-- 000011: get_children() / get_child_detail()
-- Back the `children` Edge Function so it never needs raw
-- .from('children') calls — every read goes through a function
-- that already includes the computed API-contract fields
-- (age, stage name, latest confession, days_since, needs_confession).
-- ============================================================

create or replace function public.get_children()
returns table (
  id uuid,
  first_name text,
  last_name text,
  birthday date,
  age integer,
  stage_id integer,
  stage text,
  latest_confession_at timestamptz,
  days_since_last_confession integer,
  needs_confession boolean,
  confession_status text,
  reminder_is_read boolean,
  reminder_snoozed_until date
)
language sql
stable
as $$
  with latest as (
    select c.id as child_id, max(ch.confession_at) as latest_confession_at
    from public.children c
    left join public.confession_history ch on ch.child_id = c.id
    where c.father_id = auth.uid()
    group by c.id
  )
  select
    c.id, c.first_name, c.last_name, c.birthday,
    public.calculate_age(c.birthday),
    c.stage_id, s.name,
    l.latest_confession_at,
    case when l.latest_confession_at is null then null
         else extract(day from (now() - l.latest_confession_at))::integer end,
    (l.latest_confession_at is null
       or extract(day from (now() - l.latest_confession_at)) > 27),
    case
      when l.latest_confession_at is null then 'NO_CONFESSION_RECORDED'
      when extract(day from (now() - l.latest_confession_at)) > 27 then 'OVERDUE'
      else 'UP_TO_DATE'
    end,
    c.reminder_is_read,
    c.reminder_snoozed_until
  from public.children c
  join public.stages s on s.id = c.stage_id
  left join latest l on l.child_id = c.id
  where c.father_id = auth.uid()
  order by c.first_name;
$$;

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
