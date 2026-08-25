-- ============================================================
-- 000008: Row Level Security
-- ============================================================

alter table public.profiles enable row level security;
alter table public.stages enable row level security;
alter table public.children enable row level security;
alter table public.confession_history enable row level security;
alter table public.notifications enable row level security;

-- ---------------- profiles ----------------
-- A father can read/update only his own profile row.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
  on public.profiles for select
  using (id = auth.uid());

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
  on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- Inserts happen via the handle_new_user trigger (security definer),
-- so no direct insert policy is granted to end users.

-- ---------------- stages ----------------
-- Readable by any authenticated user. No insert/update/delete policies
-- exist for regular users -> RLS blocks all writes from the client.
drop policy if exists stages_select_authenticated on public.stages;
create policy stages_select_authenticated
  on public.stages for select
  to authenticated
  using (true);

-- ---------------- children ----------------
drop policy if exists children_select_own on public.children;
create policy children_select_own
  on public.children for select
  using (father_id = auth.uid());

drop policy if exists children_insert_own on public.children;
create policy children_insert_own
  on public.children for insert
  with check (father_id = auth.uid());

drop policy if exists children_update_own on public.children;
create policy children_update_own
  on public.children for update
  using (father_id = auth.uid())
  with check (father_id = auth.uid());

drop policy if exists children_delete_own on public.children;
create policy children_delete_own
  on public.children for delete
  using (father_id = auth.uid());

-- ---------------- confession_history ----------------
drop policy if exists confession_history_select_own on public.confession_history;
create policy confession_history_select_own
  on public.confession_history for select
  using (father_id = auth.uid());

drop policy if exists confession_history_insert_own on public.confession_history;
create policy confession_history_insert_own
  on public.confession_history for insert
  with check (
    father_id = auth.uid()
    and exists (
      select 1 from public.children c
      where c.id = child_id and c.father_id = auth.uid()
    )
  );

-- No update/delete policies -> confession history is append-only from
-- the client's perspective (nobody can edit or delete past records).

-- ---------------- notifications ----------------
drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own
  on public.notifications for select
  using (father_id = auth.uid());

drop policy if exists notifications_insert_own on public.notifications;
create policy notifications_insert_own
  on public.notifications for insert
  with check (father_id = auth.uid());

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own
  on public.notifications for update
  using (father_id = auth.uid())
  with check (father_id = auth.uid());

drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own
  on public.notifications for delete
  using (father_id = auth.uid());
