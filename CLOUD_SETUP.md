# TAM Mobile — المزامنة المشتركة بين الهواتف

## الحالة المعتمدة

- **Supabase PostgreSQL**: مصدر الحقيقة للبيانات المشتركة.
- **Supabase Auth**: تسجيل الدخول المركزي والصلاحيات.
- **SQLite**: نسخة محلية للعمل السريع وبدون إنترنت.
- **sync_outbox**: يضمن رفع العمليات المؤجلة عند عودة الاتصال.
- **Google Drive**: أرشيف التقارير/النسخ الاحتياطية، وليس قاعدة البيانات الحية.

### الهوية المشتركة للبيانات

لا تعتمد المزامنة على أرقام SQLite المحلية؛ كل سجل مشترك يملك `sync_uuid` عالميًا.
وهذا يمنع تصادم المعرّفات عندما ينشئ هاتفان سجلات في الوقت نفسه.

الجداول المشتركة حاليًا:
- `districts`
- `institutions`
- `members`
- `subscription_payments`

## إعداد Supabase مرة واحدة

1. افتح SQL Editor في مشروع Supabase.
2. شغّل كامل الملف:

`supabase/001_tam_schema_and_rls.sql`

3. في Authentication > Providers > Email عطّل **Confirm email** للحسابات الداخلية.
4. أنشئ حسابات الموظفين من Authentication > Users. استخدم بريدًا من الشكل:
   - `organization@tam.local`
   - `finance@tam.local`
   - `captain@tam.local`

   وفي التطبيق يمكن الدخول بكتابة `organization` أو البريد الكامل.
5. بعد إنشاء كل مستخدم، عدّل صفه في `public.profiles` ليحمل الدور المناسب:
   - `organization_secretary`
   - `finance_secretary`
   - `regional_captain`
   - `administrator` أو `admin`

مثال:

```sql
update public.profiles
set username='organization', display_name='أمين التنظيم', role='organization_secretary', is_active=true
where id = 'UUID_المستخدم';
```

لا تضع **Secret key / service_role key** داخل التطبيق.

## البناء

القيم الافتراضية مضمنة في `lib/services/cloud_config.dart` لأن الـ Publishable key مصمم للاستخدام في تطبيق العميل. ويمكن تجاوزها عند البناء:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://bgimwyrnzujnnumdgpvi.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

## المزامنة

عند فتح التطبيق:

1. يسحب آخر حالة من Supabase إلى SQLite.
2. يرفع العمليات الموجودة في `sync_outbox`.
3. يسحب الحالة النهائية مرة أخرى.

إذا انقطع الإنترنت، تستمر الكتابة محليًا وتبقى العملية في `sync_outbox` حتى تنجح المزامنة.

## الدفعات المالية

`subscription_payments` لا يسمح لها RLS بالتعديل أو الحذف في Supabase. تصحيح الحركة المالية يجب أن يكون حركة جديدة/تصحيحية بدل تغيير السجل الأصلي.
