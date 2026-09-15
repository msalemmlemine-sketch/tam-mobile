# TAM Mobile — مزامنة Google Drive

هذه النسخة تستخدم Google Drive فقط كمخزن مركزي عبر Google Apps Script.

- لا يوجد Supabase.
- لا يوجد MySQL/PHP.
- SQLite على الهاتف يعمل كـ local cache للعمل دون اتصال.
- مصدر البيانات المشترك بين الأجهزة الثلاثة هو ملف `TAM_Mobile_shared_state.json` داخل Google Drive لمالك Apps Script.
- يوجد `revision` لمنع الكتابة فوق نسخة أحدث.
- يوجد `LockService` لمنع عمليتي Push متزامنتين من الكتابة في اللحظة نفسها.

ابدأ من `google_apps_script/README_AR.md`.


## التذكيرات الآلية

التذكيرات المحلية لا تعتمد على Google Drive. كل جهاز إداري يبرمج محليًا إشعارين يومي 24 و26، بينما يتم حساب قائمة المتأخرين من SQLite عند فتح التطبيق في يوم التذكير.
