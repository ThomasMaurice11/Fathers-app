-- ============================================================
-- 000005: confession_history
-- Append-only. Never update/overwrite a row after insert.
-- ============================================================

create table if not exists public.confession_history (
  id             uuid primary key default gen_random_uuid(),
  father_id      uuid not null references public.profiles(id) on delete cascade,
  child_id       uuid not null references public.children(id) on delete cascade,
  confession_at  timestamptz not null,
  notes          text,
  created_at     timestamptz not null default now()
);
