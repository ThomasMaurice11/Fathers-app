-- ============================================================
-- 000017: replace first_name + last_name with single name field
-- Enforce unique name per father (case-insensitive, trimmed).
-- ============================================================

alter table public.children add column if not exists name text;

update public.children
set name = trim(
  btrim(first_name)
  || case
       when last_name is not null and btrim(last_name) <> '' then ' ' || btrim(last_name)
       else ''
     end
)
where name is null;

alter table public.children alter column name set not null;

alter table public.children drop constraint if exists children_first_name_not_blank;
alter table public.children drop column if exists first_name;
alter table public.children drop column if exists last_name;

alter table public.children
  add constraint children_name_not_blank check (btrim(name) <> '');

create unique index if not exists idx_children_father_name_unique
  on public.children (father_id, lower(btrim(name)));

-- get_birthdays() — return type changed
drop function if exists public.get_birthdays(date);

create function public.get_birthdays(p_date date default current_date)
returns table (
  child_id uuid,
  name text,
  birthday date,
  age integer,
  stage_id integer,
  stage text
)
language sql
stable
as $$
  select
    c.id, c.name, c.birthday,
    public.calculate_age(c.birthday), c.stage_id, s.name
  from public.children c
  join public.stages s on s.id = c.stage_id
  where c.father_id = auth.uid()
    and c.birthday is not null
    and extract(month from c.birthday) = extract(month from p_date)
    and extract(day from c.birthday) = extract(day from p_date);
$$;

-- get_children()
drop function if exists public.get_children();

create function public.get_children()
returns table (
  id uuid,
  name text,
  birthday date,
  marriage_contract date,
  age integer,
  stage_id integer,
  stage text,
  latest_confession_at timestamptz,
  days_since_last_confession integer,
  needs_confession boolean,
  confession_status text,
  reminder_is_read boolean,
  reminder_snoozed_until date
)
language sql
stable
as $$
  with latest as (
    select c.id as child_id, max(ch.confession_at) as latest_confession_at
    from public.children c
    left join public.confession_history ch on ch.child_id = c.id
    where c.father_id = auth.uid()
    group by c.id
  )
  select
    c.id, c.name, c.birthday, c.marriage_contract,
    public.calculate_age(c.birthday),
    c.stage_id, s.name,
    l.latest_confession_at,
    case when l.latest_confession_at is null then null
         else extract(day from (now() - l.latest_confession_at))::integer end,
    (l.latest_confession_at is null
       or extract(day from (now() - l.latest_confession_at)) > 27),
    case
      when l.latest_confession_at is null then 'NO_CONFESSION_RECORDED'
      when extract(day from (now() - l.latest_confession_at)) > 27 then 'OVERDUE'
      else 'UP_TO_DATE'
    end,
    c.reminder_is_read,
    c.reminder_snoozed_until
  from public.children c
  join public.stages s on s.id = c.stage_id
  left join latest l on l.child_id = c.id
  where c.father_id = auth.uid()
  order by c.name;
$$;

-- get_confession_reminders()
drop function if exists public.get_confession_reminders(boolean);

create function public.get_confession_reminders(p_unread_only boolean default false)
returns table (
  child_id uuid,
  name text,
  birthday date,
  marriage_contract date,
  age integer,
  stage_id integer,
  stage text,
  latest_confession_at timestamptz,
  days_since_last_confession integer,
  needs_confession boolean,
  confession_status text,
  reminder_is_read boolean,
  reminder_snoozed_until date
)
language sql
stable
as $$
  with latest as (
    select
      c.id as child_id,
      max(ch.confession_at) as latest_confession_at
    from public.children c
    left join public.confession_history ch on ch.child_id = c.id
    where c.father_id = auth.uid()
    group by c.id
  )
  select
    c.id,
    c.name,
    c.birthday,
    c.marriage_contract,
    public.calculate_age(c.birthday),
    c.stage_id,
    s.name,
    l.latest_confession_at,
    case
      when l.latest_confession_at is null then null
      else extract(day from (now() - l.latest_confession_at))::integer
    end as days_since_last_confession,
    (
      l.latest_confession_at is null
      or extract(day from (now() - l.latest_confession_at)) > 27
    ) as needs_confession,
    case
      when l.latest_confession_at is null then 'NO_CONFESSION_RECORDED'
      when extract(day from (now() - l.latest_confession_at)) > 27 then 'OVERDUE'
      else 'UP_TO_DATE'
    end as confession_status,
    c.reminder_is_read,
    c.reminder_snoozed_until
  from public.children c
  join public.stages s on s.id = c.stage_id
  left join latest l on l.child_id = c.id
  where c.father_id = auth.uid()
    and (
      l.latest_confession_at is null
      or extract(day from (now() - l.latest_confession_at)) > 27
    )
    and (c.reminder_snoozed_until is null or c.reminder_snoozed_until <= current_date)
    and (p_unread_only = false or c.reminder_is_read = false)
  order by l.latest_confession_at asc nulls first;
$$;

-- get_child_detail()
create or replace function public.get_child_detail(p_child_id uuid)
returns json
language plpgsql
stable
as $$
declare
  v_result json;
begin
  if not exists (
    select 1 from public.children c
    where c.id = p_child_id and c.father_id = auth.uid()
  ) then
    return null;
  end if;

  select json_build_object(
    'id', c.id,
    'name', c.name,
    'birthday', c.birthday,
    'marriage_contract', c.marriage_contract,
    'age', public.calculate_age(c.birthday),
    'stage_id', c.stage_id,
    'stage', s.name,
    'reminder_is_read', c.reminder_is_read,
    'reminder_snoozed_until', c.reminder_snoozed_until,
    'latest_confession_at', l.latest_confession_at,
    'days_since_last_confession', case
      when l.latest_confession_at is null then null
      else extract(day from (now() - l.latest_confession_at))::integer end,
    'needs_confession', (
      l.latest_confession_at is null
      or extract(day from (now() - l.latest_confession_at)) > 27
    ),
    'confession_status', case
      when l.latest_confession_at is null then 'NO_CONFESSION_RECORDED'
      when extract(day from (now() - l.latest_confession_at)) > 27 then 'OVERDUE'
      else 'UP_TO_DATE'
    end,
    'confession_history', (
      select coalesce(json_agg(ch order by ch.confession_at desc), '[]'::json)
      from (
        select id, confession_at, notes, created_at
        from public.confession_history
        where child_id = c.id
        order by confession_at desc
      ) ch
    ),
    'operations', (
      select coalesce(json_agg(op order by op.operation_date desc), '[]'::json)
      from (
        select id, type, note, operation_date, created_at, updated_at
        from public.operations
        where child_id = c.id
        order by operation_date desc
      ) op
    )
  )
  into v_result
  from public.children c
  join public.stages s on s.id = c.stage_id
  left join (
    select child_id, max(confession_at) as latest_confession_at
    from public.confession_history
    where child_id = p_child_id
    group by child_id
  ) l on l.child_id = c.id
  where c.id = p_child_id and c.father_id = auth.uid();

  return v_result;
end;
$$;
