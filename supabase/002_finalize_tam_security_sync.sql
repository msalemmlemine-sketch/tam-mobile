-- TAM Mobile final security/sync alignment.
-- Run after 001_tam_schema_and_rls.sql.

-- Canonical application roles.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in (
  'organization_secretary','finance_secretary','regional_captain','administrator','member'
));

-- Shared financial tables.
create table if not exists public.regional_expenses (
  id uuid primary key default gen_random_uuid(),
  sync_uuid uuid unique not null default gen_random_uuid(),
  amount numeric not null default 0,
  expense_date date,
  category text not null default 'أخرى',
  description text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.fund_opening_overrides (
  id uuid primary key default gen_random_uuid(),
  sync_uuid uuid unique not null default gen_random_uuid(),
  year integer unique not null,
  amount numeric not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.regional_expenses add column if not exists sync_uuid uuid default gen_random_uuid();
alter table public.regional_expenses add column if not exists notes text;
alter table public.regional_expenses add column if not exists updated_at timestamptz not null default now();
update public.regional_expenses set sync_uuid=gen_random_uuid() where sync_uuid is null;
create unique index if not exists regional_expenses_sync_uuid_key on public.regional_expenses(sync_uuid);
alter table public.fund_opening_overrides add column if not exists sync_uuid uuid default gen_random_uuid();
alter table public.fund_opening_overrides add column if not exists updated_at timestamptz not null default now();
update public.fund_opening_overrides set sync_uuid=gen_random_uuid() where sync_uuid is null;
create unique index if not exists fund_opening_overrides_sync_uuid_key on public.fund_opening_overrides(sync_uuid);

create or replace function public.set_updated_at() returns trigger
language plpgsql security definer set search_path=public as $$
begin new.updated_at=now(); return new; end; $$;

drop trigger if exists trg_updated_districts on public.districts;
create trigger trg_updated_districts before update on public.districts for each row execute function public.set_updated_at();
drop trigger if exists trg_updated_institutions on public.institutions;
create trigger trg_updated_institutions before update on public.institutions for each row execute function public.set_updated_at();
drop trigger if exists trg_updated_members on public.members;
create trigger trg_updated_members before update on public.members for each row execute function public.set_updated_at();
drop trigger if exists trg_updated_payments on public.subscription_payments;
create trigger trg_updated_payments before update on public.subscription_payments for each row execute function public.set_updated_at();
drop trigger if exists trg_updated_expenses on public.regional_expenses;
create trigger trg_updated_expenses before update on public.regional_expenses for each row execute function public.set_updated_at();
drop trigger if exists trg_updated_opening on public.fund_opening_overrides;
create trigger trg_updated_opening before update on public.fund_opening_overrides for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.regional_expenses enable row level security;
alter table public.fund_opening_overrides enable row level security;


-- Members see only their own district/institution; management roles see all.
drop policy if exists districts_select on public.districts;
create policy districts_select on public.districts for select using (
  public.is_admin()
  or public.current_role() in ('organization_secretary','finance_secretary','regional_captain')
  or (public.current_role()='member' and id = (select m.district_id from public.members m where m.sync_uuid=(select member_sync_uuid from public.profiles where id=auth.uid())))
);
drop policy if exists institutions_select on public.institutions;
create policy institutions_select on public.institutions for select using (
  public.is_admin()
  or public.current_role() in ('organization_secretary','finance_secretary','regional_captain')
  or (public.current_role()='member' and id = (select m.institution_id from public.members m where m.sync_uuid=(select member_sync_uuid from public.profiles where id=auth.uid())))
);

-- Organization secretary may manage profiles/roles; users may still read themselves.
drop policy if exists profiles_admin_select on public.profiles;
create policy profiles_admin_select on public.profiles for select using (id=auth.uid() or public.is_admin() or public.current_role()='organization_secretary');
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update using (public.is_admin() or public.current_role()='organization_secretary') with check (public.is_admin() or public.current_role()='organization_secretary');

-- Finance can edit payments; only organization/admin can delete.
drop policy if exists payments_update on public.subscription_payments;
create policy payments_update on public.subscription_payments for update
using (public.is_admin() or public.current_role() in ('organization_secretary','finance_secretary'))
with check (public.is_admin() or public.current_role() in ('organization_secretary','finance_secretary'));
drop policy if exists payments_delete on public.subscription_payments;
create policy payments_delete on public.subscription_payments for delete
using (public.is_admin() or public.current_role()='organization_secretary');

-- Regional captain may update institution/member statistics only.
drop policy if exists members_update on public.members;
create policy members_update on public.members for update
using (public.is_admin() or public.current_role() in ('organization_secretary','regional_captain'))
with check (public.is_admin() or public.current_role() in ('organization_secretary','regional_captain'));

-- Fund data.
drop policy if exists expenses_select on public.regional_expenses;
create policy expenses_select on public.regional_expenses for select using (auth.uid() is not null);
drop policy if exists expenses_write on public.regional_expenses;
create policy expenses_write on public.regional_expenses for all
using (public.is_admin() or public.current_role()='organization_secretary')
with check (public.is_admin() or public.current_role()='organization_secretary');
drop policy if exists opening_select on public.fund_opening_overrides;
create policy opening_select on public.fund_opening_overrides for select using (auth.uid() is not null);
drop policy if exists opening_write on public.fund_opening_overrides;
create policy opening_write on public.fund_opening_overrides for all
using (public.is_admin() or public.current_role()='organization_secretary')
with check (public.is_admin() or public.current_role()='organization_secretary');

-- Audit fund changes through the same immutable database audit stream.
create or replace function public.log_financial_change() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into public.audit_logs(actor_id,actor_role,action,entity,entity_id,details)
  values(auth.uid(),public.current_role(),lower(tg_op),tg_table_name,coalesce(new.id,old.id)::text,case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end);
  return coalesce(new,old);
end; $$;
drop trigger if exists trg_audit_expenses on public.regional_expenses;
create trigger trg_audit_expenses after insert or update or delete on public.regional_expenses for each row execute function public.log_financial_change();
drop trigger if exists trg_audit_opening on public.fund_opening_overrides;
create trigger trg_audit_opening after insert or update or delete on public.fund_opening_overrides for each row execute function public.log_financial_change();

-- Realtime publication.
alter table public.districts replica identity full;
alter table public.institutions replica identity full;
alter table public.members replica identity full;
alter table public.subscription_payments replica identity full;
alter table public.regional_expenses replica identity full;
alter table public.fund_opening_overrides replica identity full;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='districts') then alter publication supabase_realtime add table public.districts; end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='institutions') then alter publication supabase_realtime add table public.institutions; end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='members') then alter publication supabase_realtime add table public.members; end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='subscription_payments') then alter publication supabase_realtime add table public.subscription_payments; end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='regional_expenses') then alter publication supabase_realtime add table public.regional_expenses; end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='fund_opening_overrides') then alter publication supabase_realtime add table public.fund_opening_overrides; end if;
end $$;

-- Remove all legacy district_manager policy branches; the canonical roles above are authoritative.
drop policy if exists institutions_insert on public.institutions;
create policy institutions_insert on public.institutions for insert
with check (public.is_admin() or public.current_role()='organization_secretary');
drop policy if exists institutions_update on public.institutions;
create policy institutions_update on public.institutions for update
using (public.is_admin() or public.current_role() in ('organization_secretary','regional_captain'))
with check (public.is_admin() or public.current_role() in ('organization_secretary','regional_captain'));
drop policy if exists institutions_delete on public.institutions;
create policy institutions_delete on public.institutions for delete
using (public.is_admin() or public.current_role()='organization_secretary');

drop policy if exists members_insert on public.members;
create policy members_insert on public.members for insert
with check (public.is_admin() or public.current_role()='organization_secretary');
drop policy if exists members_update on public.members;
create policy members_update on public.members for update
using (public.is_admin() or public.current_role() in ('organization_secretary','regional_captain'))
with check (public.is_admin() or public.current_role() in ('organization_secretary','regional_captain'));
drop policy if exists members_delete on public.members;
create policy members_delete on public.members for delete
using (public.is_admin() or public.current_role()='organization_secretary');

drop policy if exists payments_select on public.subscription_payments;
create policy payments_select on public.subscription_payments for select using (
  public.is_admin() or public.current_role() in ('organization_secretary','finance_secretary','regional_captain')
  or (public.current_role()='member' and sync_uuid=(select member_sync_uuid from public.profiles where id=auth.uid()))
);
drop policy if exists payments_insert on public.subscription_payments;
create policy payments_insert on public.subscription_payments for insert
with check (public.is_admin() or public.current_role() in ('organization_secretary','finance_secretary'));
