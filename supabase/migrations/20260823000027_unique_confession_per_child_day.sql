-- ============================================================
-- 000027: one confession per child per calendar day (Africa/Cairo)
-- ============================================================

-- Keep the latest row per (child_id, Cairo date); drop older duplicates.
delete from public.confession_history ch
using (
  select id
  from (
    select id,
           row_number() over (
             partition by child_id, (confession_at at time zone 'Africa/Cairo')::date
             order by confession_at desc, created_at desc
           ) as rn
    from public.confession_history
  ) d
  where d.rn > 1
) dup
where ch.id = dup.id;

create unique index if not exists idx_confession_history_child_day_unique
  on public.confession_history (
    child_id,
    ((confession_at at time zone 'Africa/Cairo')::date)
  );
