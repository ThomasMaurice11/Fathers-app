-- ============================================================
-- 000009: Business logic functions
--
-- All functions here are SECURITY INVOKER (the default) and are
-- called via supabase-js `.rpc(...)` using the caller's JWT, so the
-- RLS policies from 000008 still apply underneath. Ownership checks
-- are also done explicitly so we can raise clear errors instead of
-- silently returning zero rows.
-- ============================================================

-- ---------------------------------------------------------------
-- age calculation helper
-- ---------------------------------------------------------------
create or replace function public.calculate_age(p_birthday date)
returns integer
language sql
immutable
as $$
  select case
    when p_birthday is null then null
    else date_part('year', age(current_date, p_birthday))::integer
  end;
$$;

-- ---------------------------------------------------------------
-- confession reminders (dynamically calculated, never stored)
-- ---------------------------------------------------------------
create or replace function public.get_confession_reminders(p_unread_only boolean default false)
returns table (
  child_id uuid,
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
    c.first_name,
    c.last_name,
    c.birthday,
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

-- ---------------------------------------------------------------
-- create confession (atomic: insert history + reset reminder state)
-- ---------------------------------------------------------------
create or replace function public.create_confession(
  p_child_id uuid,
  p_confession_at timestamptz,
  p_notes text default null
)
returns table (
  child_id uuid,
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
begin
  if v_father_id is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if not exists (
    select 1 from public.children c
    where c.id = p_child_id and c.father_id = v_father_id
  ) then
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
    select p_child_id, v_new_confession_id, p_confession_at, false, null::date;
end;
$$;

-- ---------------------------------------------------------------
-- mark confession reminder as read
-- ---------------------------------------------------------------
create or replace function public.mark_confession_reminder_read(p_child_id uuid)
returns public.children
language plpgsql
as $$
declare
  v_row public.children;
begin
  update public.children
     set reminder_is_read = true
   where id = p_child_id
     and father_id = auth.uid()
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Child not found or not owned by the current father' using errcode = '42501';
  end if;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------
-- snooze / extend confession reminder
-- ---------------------------------------------------------------
create or replace function public.snooze_confession_reminder(p_child_id uuid, p_snoozed_until date)
returns public.children
language plpgsql
as $$
declare
  v_row public.children;
begin
  if p_snoozed_until < current_date then
    raise exception 'snoozed_until must be today or a future date' using errcode = '22023';
  end if;

  update public.children
     set reminder_snoozed_until = p_snoozed_until
   where id = p_child_id
     and father_id = auth.uid()
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Child not found or not owned by the current father' using errcode = '42501';
  end if;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------
-- birthdays (month/day match only, year ignored)
-- ---------------------------------------------------------------
create or replace function public.get_birthdays(p_date date default current_date)
returns table (
  child_id uuid,
  first_name text,
  last_name text,
  birthday date,
  age integer,
  stage_id integer,
  stage text
)
language sql
stable
as $$
  select
    c.id, c.first_name, c.last_name, c.birthday,
    public.calculate_age(c.birthday), c.stage_id, s.name
  from public.children c
  join public.stages s on s.id = c.stage_id
  where c.father_id = auth.uid()
    and c.birthday is not null
    and extract(month from c.birthday) = extract(month from p_date)
    and extract(day from c.birthday) = extract(day from p_date);
$$;

-- ---------------------------------------------------------------
-- dashboard aggregate
-- ---------------------------------------------------------------
create or replace function public.get_dashboard()
returns json
language sql
stable
as $$
  select json_build_object(
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
      from public.get_confession_reminders(false) r
    ),
    'general_events_today', (
      select coalesce(json_agg(n), '[]'::json)
      from (
        select id, title, message, notification_date, is_read, child_id
        from public.notifications
        where father_id = auth.uid()
          and type = 'GENERAL'
          and notification_date = current_date
        order by created_at desc
      ) n
    )
  );
$$;
