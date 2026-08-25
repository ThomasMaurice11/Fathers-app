-- ============================================================
-- 000006: notifications
-- Used ONLY for general events. Confession reminders are
-- calculated dynamically and are never stored here.
-- ============================================================

create table if not exists public.notifications (
  id                  uuid primary key default gen_random_uuid(),
  father_id           uuid not null references public.profiles(id) on delete cascade,
  child_id            uuid null references public.children(id) on delete set null,
  type                notification_type not null default 'GENERAL',
  title               text not null,
  message             text,
  notification_date   date not null,
  status              notification_status not null default 'SCHEDULED',
  is_read             boolean not null default false,
  created_at          timestamptz not null default now(),
  delivered_at        timestamptz null,
  read_at             timestamptz null,

  constraint notifications_title_not_blank check (btrim(title) <> '')
);
