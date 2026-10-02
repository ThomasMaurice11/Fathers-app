-- ============================================================
-- 000030: remember which birthday occurrence was marked read
--
-- birthday_acknowledged_on stores the calendar date of this year's
-- birthday (for example 2026-10-03), not a permanent boolean.
-- Next year's occurrence is a different date, so the reminder shows again.
-- ============================================================

alter table public.children
  add column if not exists birthday_acknowledged_on date null;

comment on column public.children.birthday_acknowledged_on is
  'Calendar date of the birthday occurrence marked read. A later year is a different date, so the reminder returns.';

create or replace function public.is_birthday_on(p_birthday date, p_on date)
returns boolean
language sql
immutable
as $$
  select p_birthday is not null
    and p_on is not null
    and extract(month from p_birthday) = extract(month from p_on)
    and extract(day from p_birthday) = extract(day from p_on);
$$;

-- Hide an occurrence that was already marked read. p_date is that occurrence
-- (yesterday, today, or tomorrow in the dashboard), not the birth year.
create or replace function public.get_birthdays(p_date date default current_date)
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
    and public.is_birthday_on(c.birthday, p_date)
    and c.birthday_acknowledged_on is distinct from p_date;
$$;

create or replace function public.mark_birthday_acknowledged(p_child_id uuid)
returns public.children
language plpgsql
as $$
declare
  v_row public.children;
  v_today date := (timezone('Africa/Cairo', now()))::date;
  v_occurrence date;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  select d.day::date
    into v_occurrence
  from public.children c
  cross join generate_series(v_today - 1, v_today + 1, interval '1 day') as d(day)
  where c.id = p_child_id
    and c.father_id = auth.uid()
    and public.is_birthday_on(c.birthday, d.day::date)
  limit 1;

  if v_occurrence is null then
    if not exists (
      select 1
      from public.children c
      where c.id = p_child_id
        and c.father_id = auth.uid()
    ) then
      raise exception 'Child not found or not owned by the current father' using errcode = '42501';
    end if;

    raise exception 'No birthday in the current reminder window' using errcode = '22023';
  end if;

  update public.children
     set birthday_acknowledged_on = v_occurrence
   where id = p_child_id
     and father_id = auth.uid()
  returning * into v_row;

  return v_row;
end;
$$;

create or replace function public.get_dashboard()
returns json
language sql
stable
as $$
  with local_today as (
    select (timezone('Africa/Cairo', now()))::date as d
  ),
  week_bounds as (
    select
      date_trunc('week', t.d)::date as week_start,
      (date_trunc('week', t.d) + interval '6 days')::date as week_end
    from local_today t
  ),
  event_window as (
    select
      t.d as window_start,
      (t.d + interval '6 days')::date as window_end
    from local_today t
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
          where public.is_birthday_on(c.birthday, d.day::date)
            and c.birthday_acknowledged_on is distinct from d.day::date
        )
    ),
    'general_events_this_week_count', (
      select count(*)::integer
      from public.notifications n
      cross join event_window w
      where n.father_id = auth.uid()
        and n.type = 'GENERAL'
        and n.notification_date >= w.window_start
        and n.notification_date <= w.window_end
    ),
    'birthdays_yesterday', (
      select coalesce(json_agg(b), '[]'::json)
      from local_today t
      cross join lateral public.get_birthdays(t.d - 1) b
    ),
    'birthdays_today', (
      select coalesce(json_agg(b), '[]'::json)
      from local_today t
      cross join lateral public.get_birthdays(t.d) b
    ),
    'birthdays_tomorrow', (
      select coalesce(json_agg(b), '[]'::json)
      from local_today t
      cross join lateral public.get_birthdays(t.d + 1) b
    ),
    'confession_reminders', (
      select coalesce(json_agg(r), '[]'::json)
      from public.get_confession_reminders() r
    ),
    'general_events_this_week', (
      select coalesce(
        json_agg(n order by n.notification_date asc, n.event_time asc nulls last, n.created_at desc),
        '[]'::json
      )
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
          n.event_time,
          n.status,
          n.is_read,
          n.created_at
        from public.notifications n
        join public.profiles p on p.id = n.father_id
        left join public.children c on c.id = n.child_id
        cross join event_window w
        where n.father_id = auth.uid()
          and n.type = 'GENERAL'
          and n.notification_date >= w.window_start
          and n.notification_date <= w.window_end
        order by n.notification_date asc, n.event_time asc nulls last, n.created_at desc
      ) n
    )
  );
$$;
