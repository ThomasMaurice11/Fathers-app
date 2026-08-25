-- ============================================================
-- 000004: children
-- ============================================================

create table if not exists public.children (
  id                      uuid primary key default gen_random_uuid(),
  father_id               uuid not null references public.profiles(id) on delete cascade,
  first_name              text not null,
  last_name               text,
  birthday                date,
  stage_id                integer not null references public.stages(id),
  reminder_is_read        boolean not null default false,
  reminder_snoozed_until  date null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),

  constraint children_first_name_not_blank check (btrim(first_name) <> '')
);

drop trigger if exists trg_children_updated_at on public.children;
create trigger trg_children_updated_at
before update on public.children
for each row execute function public.set_updated_at();
