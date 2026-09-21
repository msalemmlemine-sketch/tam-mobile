-- TAM Mobile — central cloud database for the three phones.
-- Run in Supabase SQL Editor after creating a project.
--
-- ============================================================
-- تحديث 2026-09 (تدقيق أمني وهيكلي):
-- 1) عمود legacy_id على كل جدول مشترك: يربط الصف السحابي (uuid)
--    بمعرّفه المحلي الثابت في SQLite (INTEGER)، ليتمكن التطبيق من
--    عمل upsert مباشر (on_conflict=legacy_id) دون جدول ترجمة
--    معرّفات منفصل. انظر lib/services/cloud_service.dart.
-- 2) أدوار جديدة: admin (وصول كامل لكل الدوائر) و district_manager
--    (يُقصر وصوله على دائرته فقط عبر profiles.district_id) — بالإضافة
--    للأدوار القديمة (organization_secretary/finance_secretary/
--    regional_captain/administrator) المُبقاة للتوافق الخلفي مع
--    الحسابات المُنشأة مسبقًا (CLOUD_SETUP.md). "administrator"
--    و"admin" متكافئان في كل الدوال أدناه.
-- 3) subscription_payments أصبح غير قابل للتعديل أو الحذف نهائيًا على
--    مستوى قاعدة البيانات (لا توجد سياسة UPDATE ولا DELETE إطلاقًا،
--    وهو ما يعادل USING(false) لأن الرفض هو السلوك الافتراضي بدون
--    سياسة مطابقة). أي تصحيح مالي يجب أن يكون سطر دفعة جديد (موجب أو
--    سالب) وليس تعديلًا للسطر الأصلي.
-- 4) سجل تدقيق مالي حقيقي عبر Triggers على subscription_payments —
--    وليس فقط سياسة INSERT تعتمد على أن العميل "يتطوع" بتسجيل
--    العملية بنفسه (وهي طريقة يسهل لعميل معطوب أو خبيث تجاوزها).
-- 5) institutions: سياسة UPDATE منفصلة تمنح regional_captain حق
--    تعديل مؤسسة موجودة (أرقام الطاقم/الإحصائيات) دون INSERT أو
--    DELETE — يطابق Permission.editInstitutionStats الجديد في تطبيق
--    Flutter (كان قبل هذا التحديث محصورًا في سياسة FOR ALL واحدة لا
--    تمنح regional_captain أي وصول كتابة إطلاقًا، مما كان يمنعه من
--    تنفيذ الصلاحية الممنوحة له في المواصفة حتى لو تجاوز واجهة
--    التطبيق مباشرة).
-- ============================================================

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  display_name text not null,
  role text not null check (role in (
    'organization_secretary','finance_secretary','regional_captain',
    'administrator','admin','district_manager','member'
  )),
  -- دائرة مشرف الفرع (district_manager) — يُقصر RLS وصوله عليها فقط.
  -- تبقى NULL لبقية الأدوار (لا معنى للتقييد بدائرة لدور admin مثلًا).
  -- ملاحظة: عمود بلا قيد FK هنا عمدًا لأن جدول districts يُنشأ بعده
  -- أدناه (تفاديًا لمشكلة الترتيب الدائري بين الجدولين)؛ القيد
  -- يُضاف صراحة بعد إنشاء districts مباشرة.
  district_id uuid,
  member_id integer,
  member_sync_uuid uuid,
  is_active boolean not null default true,
  must_change_password boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.districts (
  id uuid primary key default gen_random_uuid(),
  sync_uuid uuid unique default gen_random_uuid(),
  legacy_id integer unique,
  name text not null unique,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- profiles.district_id يُشير لـ districts التي أُنشئت للتو أعلاه؛
-- أضِف القيد بعد إنشاء الجدولين لتفادي مشكلة الترتيب الدائري.
alter table public.profiles
  drop constraint if exists profiles_district_id_fkey;
alter table public.profiles
  add constraint profiles_district_id_fkey
  foreign key (district_id) references public.districts(id);

create table if not exists public.institutions (
  id uuid primary key default gen_random_uuid(),
  sync_uuid uuid unique default gen_random_uuid(),
  legacy_id integer unique,
  district_id uuid not null references public.districts(id) on delete restrict,
  name text not null,
  total_staff integer not null default 0,
  sipes_members integer not null default 0,
  snes_members integer not null default 0,
  other_union_members integer not null default 0,
  non_union_staff integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(district_id, name)
);

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  sync_uuid uuid unique default gen_random_uuid(),
  legacy_id integer unique,
  district_id uuid not null references public.districts(id) on delete restrict,
  institution_id uuid not null references public.institutions(id) on delete restrict,
  name text not null,
  guide text,
  card_no text,
  phone text,
  notes text,
  membership_status text not null default 'active',
  status_date date,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subscription_payments (
  id uuid primary key default gen_random_uuid(),
  sync_uuid uuid unique default gen_random_uuid(),
  legacy_id integer unique,
  member_id uuid references public.members(id) on delete restrict,
  member_name text,
  financial_guide text,
  card_no text,
  payment_year integer not null,
  payment_month integer,
  payment_date date,
  subscription_amount numeric not null default 0,
  card_fee numeric not null default 0,
  total_amount numeric not null default 0,
  source text,
  source_name text,
  payment_method text not null default 'cash' check (payment_method in ('cash','banking_app','masrifi','bankily','sedad','bim_bank')),
  payment_reference text,
  matched_by text,
  direct_to_executive boolean not null default false,
  import_batch_id text,
  row_hash text unique,
  notes text,
  -- correction_of_id: يشير لسطر دفعة سابق تُصحِّحه هذه الحركة. أي
  -- تسوية (نقص/زيادة/إلغاء) تُسجَّل كسطر جديد مستقل يشير لأصله عبر
  -- هذا العمود بدل تعديل السطر الأصلي مباشرة — لا وجود لسياسة UPDATE
  -- على هذا الجدول أصلًا (انظر أسفله)، فهذا العمود هو الآلية الوحيدة
  -- المتاحة للتصحيح.
  correction_of_id uuid references public.subscription_payments(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id bigint generated by default as identity primary key,
  actor_id uuid references auth.users(id),
  actor_role text,
  action text not null,
  entity text not null,
  entity_id text,
  details jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.current_role() returns text
language sql stable security definer set search_path = public
as $$ select case when coalesce(is_active,false) then role else null end from public.profiles where id = auth.uid() $$;

create or replace function public.current_district_id() returns uuid
language sql stable security definer set search_path = public
as $$ select district_id from public.profiles where id = auth.uid() $$;

-- admin/administrator متكافئان في كل مكان.
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public
as $$ select public.current_role() in ('admin','administrator') $$;

-- ==================== سجل تدقيق آلي عبر Triggers ====================
-- يُسجَّل تلقائيًا من قاعدة البيانات نفسها (وليس بثقة بالعميل) لأي
-- INSERT/UPDATE/DELETE على subscription_payments، مع هوية المستخدم
-- الفعلي (auth.uid()) والتوقيت الدقيق (now()) ومحتوى الصف كـ jsonb.
create or replace function public.log_subscription_payment_change() returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.audit_logs(actor_id, actor_role, action, entity, entity_id, details)
  values (
    auth.uid(),
    public.current_role(),
    lower(tg_op),
    'subscription_payment',
    coalesce(new.id, old.id)::text,
    case tg_op
      when 'DELETE' then to_jsonb(old)
      else to_jsonb(new)
    end
  );
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_audit_subscription_payments on public.subscription_payments;
create trigger trg_audit_subscription_payments
  after insert or update or delete on public.subscription_payments
  for each row execute function public.log_subscription_payment_change();

alter table public.profiles enable row level security;
alter table public.districts enable row level security;
alter table public.institutions enable row level security;
alter table public.members enable row level security;
alter table public.subscription_payments enable row level security;
alter table public.audit_logs enable row level security;

-- Profiles: a user may read only their own profile.
drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self on public.profiles for select using (id = auth.uid());

-- Reference data readable by all three phones; only organization/admin may change it.
drop policy if exists districts_select on public.districts;
create policy districts_select on public.districts for select using (auth.uid() is not null);
drop policy if exists districts_write on public.districts;
create policy districts_write on public.districts for all
  using (public.is_admin() or public.current_role() = 'organization_secretary')
  with check (public.is_admin() or public.current_role() = 'organization_secretary');

drop policy if exists institutions_select on public.institutions;
create policy institutions_select on public.institutions for select using (auth.uid() is not null);

-- تحديث 2026-09: institutions_write المُوحَّدة (FOR ALL) استُبدلت
-- بثلاث سياسات منفصلة حسب العملية. السبب: النقيب/المنسق الجهوي
-- (regional_captain) يملك صلاحية تعديل أرقام الطاقم والإحصائيات على
-- مؤسسة موجودة فعلًا (Permission.editInstitutionStats في التطبيق)،
-- لكن لا يضيف مؤسسة جديدة ولا يحذفها — تلك محصورة بأمين
-- التنظيم/المدير فقط (Permission.manageInstitutions). سياسة واحدة
-- FOR ALL لا تستطيع التمييز بين هذين المستويين من الصلاحية.
drop policy if exists institutions_write on public.institutions;
drop policy if exists institutions_insert on public.institutions;
create policy institutions_insert on public.institutions for insert
  with check (
    public.is_admin()
    or public.current_role() = 'organization_secretary'
    or (public.current_role() = 'district_manager' and district_id = public.current_district_id())
  );
drop policy if exists institutions_update on public.institutions;
create policy institutions_update on public.institutions for update
  using (
    public.is_admin()
    or public.current_role() in ('organization_secretary','regional_captain')
    or (public.current_role() = 'district_manager' and district_id = public.current_district_id())
  )
  with check (
    public.is_admin()
    or public.current_role() in ('organization_secretary','regional_captain')
    or (public.current_role() = 'district_manager' and district_id = public.current_district_id())
  );
drop policy if exists institutions_delete on public.institutions;
create policy institutions_delete on public.institutions for delete
  using (
    public.is_admin()
    or public.current_role() = 'organization_secretary'
    or (public.current_role() = 'district_manager' and district_id = public.current_district_id())
  );

-- Members: admin يرى/يعدّل كل شيء. district_manager مقصور على دائرته
-- فقط (قراءة وكتابة). organization_secretary يدير كل الدوائر (كما
-- كان). finance/captain قراءة فقط لأغراض الاختيار/التصدير.
drop policy if exists members_select on public.members;
create policy members_select on public.members for select
  using (
    public.is_admin()
    or public.current_role() in ('organization_secretary','finance_secretary','regional_captain')
    or (public.current_role() = 'member' and sync_uuid = (select member_sync_uuid from public.profiles where id = auth.uid()))
    or (public.current_role() = 'district_manager' and district_id = public.current_district_id())
  );
drop policy if exists members_insert on public.members;
create policy members_insert on public.members for insert
  with check (
    public.is_admin()
    or public.current_role() = 'organization_secretary'
    or (public.current_role() = 'district_manager' and district_id = public.current_district_id())
  );
drop policy if exists members_update on public.members;
create policy members_update on public.members for update
  using (
    public.is_admin()
    or public.current_role() = 'organization_secretary'
    or (public.current_role() = 'district_manager' and district_id = public.current_district_id())
  )
  with check (
    public.is_admin()
    or public.current_role() = 'organization_secretary'
    or (public.current_role() = 'district_manager' and district_id = public.current_district_id())
  );
drop policy if exists members_delete on public.members;
create policy members_delete on public.members for delete
  using (public.is_admin() or public.current_role() = 'organization_secretary');

-- Payments: عمدًا لا توجد أي سياسة UPDATE ولا DELETE على هذا الجدول
-- — الرفض هو السلوك الافتراضي في RLS لأي عملية بلا سياسة مطابقة،
-- وهو ما يعادل USING(false) صراحة. أي "تصحيح" يجب أن يكون INSERT
-- لسطر جديد يشير عبر correction_of_id للسطر الأصلي.
drop policy if exists payments_select on public.subscription_payments;
create policy payments_select on public.subscription_payments for select
  using (
    public.is_admin()
    or public.current_role() in ('organization_secretary','finance_secretary','regional_captain')
    or (
      public.current_role() = 'member' and sync_uuid = (select member_sync_uuid from public.profiles where id = auth.uid())
    )
    or (
      public.current_role() = 'district_manager'
      and member_id in (select id from public.members where district_id = public.current_district_id())
    )
  );
drop policy if exists payments_insert on public.subscription_payments;
create policy payments_insert on public.subscription_payments for insert
  with check (
    public.is_admin()
    or public.current_role() in ('organization_secretary','finance_secretary')
    or (
      public.current_role() = 'district_manager'
      and member_id in (select id from public.members where district_id = public.current_district_id())
    )
  );
drop policy if exists payments_update on public.subscription_payments;
drop policy if exists payments_delete on public.subscription_payments;
-- (لا سياسات UPDATE/DELETE — ممنوعتان كليًا لكل الأدوار بما فيها admin.)

-- Audit is append-only, and only ever written by the trigger above
-- (security definer) — لا سياسة INSERT للعملاء أصلًا، فلا يمكن لأي
-- عميل (مهما كان دوره) أن يكتب أو يزوّر سجل تدقيق مباشرة.
drop policy if exists audit_insert on public.audit_logs;
drop policy if exists audit_select on public.audit_logs;
create policy audit_select on public.audit_logs for select
  using (public.is_admin() or public.current_role() = 'organization_secretary');


-- ============================================================
-- Auth profile bootstrap / account metadata
-- ============================================================
-- ينشئ ملف صلاحيات تلقائيًا عند إنشاء مستخدم من لوحة Authentication.
-- لا يمنح المستخدم صلاحيات إدارية من metadata؛ الدور الافتراضي آمن،
-- ويمكن للمشرف تغييره لاحقًا من SQL أو وظيفة الإدارة الموثوقة.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(coalesce(new.email,''),'@',1)),
    coalesce(new.raw_user_meta_data->>'display_name', split_part(coalesce(new.email,''),'@',1)),
    'organization_secretary'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- يجعل إعادة تشغيل هذا الملف آمنة حتى لو كانت الجداول موجودة مسبقًا.
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists member_id integer;
alter table public.profiles add column if not exists member_sync_uuid uuid;
alter table public.profiles add column if not exists is_active boolean not null default true;
alter table public.profiles add column if not exists must_change_password boolean not null default false;
alter table public.districts add column if not exists sync_uuid uuid default gen_random_uuid();
alter table public.institutions add column if not exists sync_uuid uuid default gen_random_uuid();
alter table public.members add column if not exists sync_uuid uuid default gen_random_uuid();
alter table public.subscription_payments add column if not exists sync_uuid uuid default gen_random_uuid();
create unique index if not exists districts_sync_uuid_key on public.districts(sync_uuid);
create unique index if not exists institutions_sync_uuid_key on public.institutions(sync_uuid);
create unique index if not exists members_sync_uuid_key on public.members(sync_uuid);
create unique index if not exists subscription_payments_sync_uuid_key on public.subscription_payments(sync_uuid);
create unique index if not exists profiles_username_key on public.profiles(username) where username is not null;

-- مهم: شغّل تأكيد البريد معطّلًا من Authentication > Providers > Email
-- لأن أسماء المستخدمين في التطبيق تتحول إلى username@tam.local.
