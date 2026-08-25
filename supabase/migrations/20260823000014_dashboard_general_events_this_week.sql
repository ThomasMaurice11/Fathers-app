-- ============================================================
-- 000014: dashboard general events — today -> this week
-- Week range: Monday through Sunday (PostgreSQL ISO week).
-- ============================================================

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
        from public.notifications
        where father_id = auth.uid()
          and type = 'GENERAL'
          and notification_date >= date_trunc('week', current_date)::date
          and notification_date < (date_trunc('week', current_date) + interval '7 days')::date
        order by notification_date asc, created_at desc
      ) n
    )
  );
$$;
