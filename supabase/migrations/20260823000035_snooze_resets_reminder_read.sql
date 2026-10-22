-- ============================================================
-- 000035: snoozing a confession reminder also marks it unread
-- ============================================================
-- Previously snooze only set reminder_snoozed_until. If the reminder had
-- been marked read, it stayed read after the snooze expired, so
-- get_confession_reminders() (unread_only = true by default, used by the
-- dashboard) never returned the child again.
-- Now snoozing resets reminder_is_read = false. During the snooze the
-- reminder stays hidden via reminder_snoozed_until > current_date.

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
     set reminder_snoozed_until = p_snoozed_until,
         reminder_is_read = false
   where id = p_child_id
     and father_id = auth.uid()
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Child not found or not owned by the current father' using errcode = '42501';
  end if;

  return v_row;
end;
$$;

-- One-time cleanup: children whose snooze already expired but are stuck as read
update public.children
   set reminder_is_read = false
 where reminder_snoozed_until is not null
   and reminder_snoozed_until <= current_date
   and reminder_is_read = true;
