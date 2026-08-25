-- ============================================================
-- 000001: Extensions & Enums
-- ============================================================

create extension if not exists "pgcrypto";

do $$
begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type user_role as enum ('FATHER', 'ADMIN');
  end if;

  if not exists (select 1 from pg_type where typname = 'notification_type') then
    create type notification_type as enum ('GENERAL');
  end if;

  if not exists (select 1 from pg_type where typname = 'notification_status') then
    create type notification_status as enum ('SCHEDULED', 'DELIVERED', 'READ');
  end if;
end $$;
