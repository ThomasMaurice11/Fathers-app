-- ============================================================
-- 000026: general events "this week" = today .. today+6 (rolling)
-- Birthdays keep calendar Mon–Sun via week_bounds.
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
  ),
  event_window as (
    select
      current_date as window_start,
      (current_date + interval '6 days')::date as window_end
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
      cross join event_window w
      where n.father_id = auth.uid()
        and n.type = 'GENERAL'
        and n.notification_date >= w.window_start
        and n.notification_date <= w.window_end
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
        cross join event_window w
        where n.father_id = auth.uid()
          and n.type = 'GENERAL'
          and n.notification_date >= w.window_start
          and n.notification_date <= w.window_end
        order by n.notification_date asc, n.created_at desc
      ) n
    )
  );
$$;
