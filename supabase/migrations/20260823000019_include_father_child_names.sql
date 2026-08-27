-- ============================================================
-- 000019: include father_name / child names with father_id / child_id
-- ============================================================

-- get_birthdays()
drop function if exists public.get_birthdays(date);

create function public.get_birthdays(p_date date default current_date)
returns table (
  child_id uuid,
  name text,
  father_id uuid,
  father_name text,
  birthday date,
  age integer,
  stage_id integer,
  stage text
)
language sql
stable
as $$
  select
    c.id,
    c.name,
    c.father_id,
    p.full_name,
    c.birthday,
    public.calculate_age(c.birthday),
    c.stage_id,
    s.name
  from public.children c
  join public.stages s on s.id = c.stage_id
  join public.profiles p on p.id = c.father_id
  where c.father_id = auth.uid()
    and c.birthday is not null
    and extract(month from c.birthday) = extract(month from p_date)
    and extract(day from c.birthday) = extract(day from p_date);
$$;

-- get_children()
drop function if exists public.get_children();

create function public.get_children()
returns table (
  id uuid,
  name text,
  father_id uuid,
  father_name text,
  birthday date,
  marriage_contract date,
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
    c.id,
    c.name,
    c.father_id,
    p.full_name,
    c.birthday,
    c.marriage_contract,
    public.calculate_age(c.birthday),
    c.stage_id,
    s.name,
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
  join public.profiles p on p.id = c.father_id
  left join latest l on l.child_id = c.id
  where c.father_id = auth.uid()
  order by c.name;
$$;

-- get_confession_reminders()
drop function if exists public.get_confession_reminders(boolean);

create function public.get_confession_reminders(p_unread_only boolean default true)
returns table (
  child_id uuid,
  name text,
  father_id uuid,
  father_name text,
  birthday date,
  marriage_contract date,
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
    select
      c.id as child_id,
      max(ch.confession_at) as latest_confession_at
    from public.children c
    left join public.confession_history ch on ch.child_id = c.id
    where c.father_id = auth.uid()
    group by c.id
  )
  select
    c.id,
    c.name,
    c.father_id,
    p.full_name,
    c.birthday,
    c.marriage_contract,
    public.calculate_age(c.birthday),
    c.stage_id,
    s.name,
    l.latest_confession_at,
    case
      when l.latest_confession_at is null then null
      else extract(day from (now() - l.latest_confession_at))::integer
    end as days_since_last_confession,
    (
      l.latest_confession_at is null
      or extract(day from (now() - l.latest_confession_at)) > 27
    ) as needs_confession,
    case
      when l.latest_confession_at is null then 'NO_CONFESSION_RECORDED'
      when extract(day from (now() - l.latest_confession_at)) > 27 then 'OVERDUE'
      else 'UP_TO_DATE'
    end as confession_status,
    c.reminder_is_read,
    c.reminder_snoozed_until
  from public.children c
  join public.stages s on s.id = c.stage_id
  join public.profiles p on p.id = c.father_id
  left join latest l on l.child_id = c.id
  where c.father_id = auth.uid()
    and (
      l.latest_confession_at is null
      or extract(day from (now() - l.latest_confession_at)) > 27
    )
    and (c.reminder_snoozed_until is null or c.reminder_snoozed_until <= current_date)
    and (p_unread_only = false or c.reminder_is_read = false)
  order by l.latest_confession_at asc nulls first;
$$;

-- get_child_detail()
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
    'name', c.name,
    'father_id', c.father_id,
    'father_name', p.full_name,
    'birthday', c.birthday,
    'marriage_contract', c.marriage_contract,
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
  join public.profiles p on p.id = c.father_id
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

-- create_confession(): also return names
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

  update public.children
     set reminder_is_read = false,
         reminder_snoozed_until = null
   where id = p_child_id
     and father_id = v_father_id;

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

-- get_dashboard(): general events include father_name + child_name
create or replace function public.get_dashboard()
returns json
language sql
stable
as $$
  with week_bounds as (
    select
      date_trunc('week', current_date)::date as week_start,
      (date_trunc('week', current_date) + interval '6 days')::date as week_end
  )
  select json_build_object(
    'children_count', (
      select count(*)::integer
      from public.children c
      where c.father_id = auth.uid()
    ),
    'children_needing_confession_count', (
      select count(*)::integer
      from public.get_confession_reminders() r
    ),
    'birthdays_this_week_count', (
      select count(*)::integer
      from public.children c
      cross join week_bounds w
      where c.father_id = auth.uid()
        and c.birthday is not null
        and exists (
          select 1
          from generate_series(w.week_start, w.week_end, interval '1 day') as d(day)
          where extract(month from c.birthday) = extract(month from d.day)
            and extract(day from c.birthday) = extract(day from d.day)
        )
    ),
    'general_events_this_week_count', (
      select count(*)::integer
      from public.notifications n
      cross join week_bounds w
      where n.father_id = auth.uid()
        and n.type = 'GENERAL'
        and n.notification_date >= w.week_start
        and n.notification_date <= w.week_end
    ),
    'birthdays_yesterday', (
      select coalesce(json_agg(b), '[]'::json)
      from public.get_birthdays(current_date - 1) b
    ),
    'birthdays_today', (
      select coalesce(json_agg(b), '[]'::json)
      from public.get_birthdays(current_date) b
    ),
    'birthdays_tomorrow', (
      select coalesce(json_agg(b), '[]'::json)
      from public.get_birthdays(current_date + 1) b
    ),
    'confession_reminders', (
      select coalesce(json_agg(r), '[]'::json)
      from public.get_confession_reminders() r
    ),
    'general_events_this_week', (
      select coalesce(json_agg(n order by n.notification_date asc, n.created_at desc), '[]'::json)
      from (
        select
          n.id,
          n.father_id,
          p.full_name as father_name,
          n.child_id,
          c.name as child_name,
          n.type,
          n.title,
          n.message,
          n.notification_date,
          n.status,
          n.is_read,
          n.created_at
        from public.notifications n
        join public.profiles p on p.id = n.father_id
        left join public.children c on c.id = n.child_id
        cross join week_bounds w
        where n.father_id = auth.uid()
          and n.type = 'GENERAL'
          and n.notification_date >= w.week_start
          and n.notification_date <= w.week_end
        order by n.notification_date asc, n.created_at desc
      ) n
    )
  );
$$;
