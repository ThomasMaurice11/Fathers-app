-- ============================================================
-- 000018: confession reminders default to unread-only
--
-- Ensures get_confession_reminders defaults to unread-only, and
-- updates get_dashboard to stop passing false (which bypassed the
-- default and returned read reminders too).
-- ============================================================

drop function if exists public.get_confession_reminders(boolean);

create function public.get_confession_reminders(p_unread_only boolean default true)
returns table (
  child_id uuid,
  name text,
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
          id,
          father_id,
          child_id,
          type,
          title,
          message,
          notification_date,
          status,
          is_read,
          created_at
        from public.notifications n
        cross join week_bounds w
        where n.father_id = auth.uid()
          and n.type = 'GENERAL'
          and n.notification_date >= w.week_start
          and n.notification_date <= w.week_end
        order by notification_date asc, created_at desc
      ) n
    )
  );
$$;
