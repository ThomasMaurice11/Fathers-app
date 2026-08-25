-- ============================================================
-- 000016: dashboard summary counts
-- Week range: Monday through Sunday (PostgreSQL ISO week).
-- ============================================================

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
      from public.get_confession_reminders(false) r
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
      from public.get_confession_reminders(false) r
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
