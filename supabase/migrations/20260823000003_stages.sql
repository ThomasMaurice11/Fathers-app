-- ============================================================
-- 000003: stages (predefined lookup table)
-- ============================================================

create table if not exists public.stages (
  id    integer primary key,
  name  text not null unique
);
