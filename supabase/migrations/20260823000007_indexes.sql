-- ============================================================
-- 000007: indexes
-- ============================================================

create index if not exists idx_children_father_id on public.children(father_id);
create index if not exists idx_children_stage_id on public.children(stage_id);
create index if not exists idx_children_birthday on public.children(birthday);

create index if not exists idx_confession_history_child_id on public.confession_history(child_id);
create index if not exists idx_confession_history_father_id on public.confession_history(father_id);
create index if not exists idx_confession_history_confession_at on public.confession_history(confession_at);

-- Optimized for "latest confession per child" lookups (used by the
-- reminder calculation function).
create index if not exists idx_confession_history_child_confession_at_desc
  on public.confession_history(child_id, confession_at desc);

create index if not exists idx_notifications_father_id on public.notifications(father_id);
create index if not exists idx_notifications_notification_date on public.notifications(notification_date);
create index if not exists idx_notifications_type on public.notifications(type);
create index if not exists idx_notifications_status on public.notifications(status);
create index if not exists idx_notifications_father_date_type
  on public.notifications(father_id, notification_date, type);
