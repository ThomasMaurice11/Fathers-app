-- ============================================================
-- 000012: operations
-- Tracks father interactions with a child (call, visit, etc.)
-- ============================================================

create table if not exists public.operations (
  id              uuid primary key default gen_random_uuid(),
  father_id       uuid not null references public.profiles(id) on delete cascade,
  child_id        uuid not null references public.children(id) on delete cascade,
  type            text not null,
  note            text,
  operation_date  date not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint operations_type_not_blank check (btrim(type) <> '')
);

drop trigger if exists trg_operations_updated_at on public.operations;
create trigger trg_operations_updated_at
before update on public.operations
for each row execute function public.set_updated_at();

create index if not exists idx_operations_child_id on public.operations(child_id);
create index if not exists idx_operations_father_id on public.operations(father_id);
create index if not exists idx_operations_operation_date on public.operations(operation_date);
create index if not exists idx_operations_child_operation_date_desc
  on public.operations(child_id, operation_date desc);

-- ---------------- RLS ----------------
alter table public.operations enable row level security;

drop policy if exists operations_select_own on public.operations;
create policy operations_select_own
  on public.operations for select
  using (father_id = auth.uid());

drop policy if exists operations_insert_own on public.operations;
create policy operations_insert_own
  on public.operations for insert
  with check (
    father_id = auth.uid()
    and exists (
      select 1 from public.children c
      where c.id = child_id and c.father_id = auth.uid()
    )
  );

drop policy if exists operations_update_own on public.operations;
create policy operations_update_own
  on public.operations for update
  using (father_id = auth.uid())
  with check (
    father_id = auth.uid()
    and exists (
      select 1 from public.children c
      where c.id = child_id and c.father_id = auth.uid()
    )
  );

drop policy if exists operations_delete_own on public.operations;
create policy operations_delete_own
  on public.operations for delete
  using (father_id = auth.uid());
