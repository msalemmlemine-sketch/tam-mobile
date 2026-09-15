# مزامنة TAM Mobile عبر Google Drive فقط

هذه النسخة لا تستخدم Supabase ولا PHP ولا MySQL ولا خادمًا تقليديًا.

المعمارية:

Flutter SQLite (ذاكرة/نسخة محلية للعمل دون إنترنت)
→ HTTP
→ Google Apps Script Web App
→ ملف JSON واحد في Google Drive الخاص بمالك السكربت

## 1. إنشاء Apps Script

1. افتح Google Drive بحسابك.
2. أنشئ مشروع Google Apps Script جديد.
3. انسخ محتوى `Code.gs`.
4. افتح Project Settings/Script Properties أو شغّل الدالة `setApiKey` من المحرر.
5. شغّل مرة واحدة:

```javascript
function init() {
  setApiKey('ضع_مفتاحًا_سريًا_طويلًا_هنا');
}
```

6. وافق على صلاحيات Drive عند أول تشغيل.
7. Deploy → New deployment → Web app.
8. Execute as: Me.
9. Who has access: Anyone.
10. انسخ رابط `/exec`.

## 2. بناء Flutter

```bash
flutter pub get
flutter build apk --release \
  --dart-define=DRIVE_SYNC_URL=https://script.google.com/macros/s/XXXXXXXX/exec \
  --dart-define=DRIVE_SYNC_API_KEY=ضع_نفس_المفتاح
```

ضع نفس الرابط والمفتاح في الهواتف الثلاثة.

## 3. طريقة العمل

- **سحب**: يستبدل بيانات الأعمال المحلية بالنسخة الموجودة في Drive.
- **رفع**: يرفع النسخة المحلية إذا كانت مبنية على نفس `revision` الموجودة في Drive.
- **مزامنة الآن**: Pull ثم Push.

إذا عدّل جهاز آخر البيانات بعد آخر Pull، يرفض Apps Script عملية Push بدل أن يمحو التعديل الجديد. عند ظهور تعارض: اسحب النسخة الجديدة أولًا، ثم أعد إدخال التغييرات المحلية غير المحفوظة.

## تنبيه أمني

API Key البسيط مناسب كحماية أولية، لكنه ليس مصادقة قوية؛ المفتاح موجود في تطبيق الهاتف ويمكن استخراجه من APK. البيانات نفسها تبقى في Google Drive الخاص بمالك Apps Script، لكن رابط Web App إذا كان عامًا مع مفتاح صحيح يمكن الوصول إليه. للحماية المصرفية/الحساسة جدًا، الأفضل لاحقًا استخدام OAuth أو هوية Google لكل جهاز بدل مفتاح مشترك.
