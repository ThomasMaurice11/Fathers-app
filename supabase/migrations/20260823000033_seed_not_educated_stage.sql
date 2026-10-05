-- ============================================================
-- 000033: Seed "Not Educated" stage
-- Continues after Graduated (id 19).
-- ============================================================

insert into public.stages (id, name) values
  (20, 'Not Educated')
on conflict (id) do update set name = excluded.name;
