# تثبيت TAM Mobile على iPhone أمين المالية — الدليل الكامل

هذا الملف يحدد **بالضبط** ما تحتاجه من Apple، وأين تضع كل معلومة في
GitHub، والطريقة العملية لتثبيت التطبيق على iPhone حقيقي.

## لماذا لا يكفي `flutter build ios`

Apple تمنع تشغيل أي تطبيق على iPhone حقيقي (خارج المحاكي) ما لم يكن
**موقَّعًا رقميًا** بشهادة صادرة عنها، ومرتبطًا بملف توفير
(Provisioning Profile) يُدرج جهاز أمين المالية بالتحديد (Ad Hoc). هذا
التوقيع **لا يمكن تزويره أو تجاوزه**.

## ما تحتاجه من Apple (لا بديل عنه)

| المتطلب | التفصيل |
|---|---|
| **Apple Developer Program** | حساب مدفوع، **99 دولار/سنة**. الحساب المجاني لا يكفي لأنه يحتاج Mac فعليًا لإعادة التوقيع كل 7 أيام. |
| **Team ID** | من عضوية Apple Developer (Membership Details على developer.apple.com). |
| **Bundle Identifier** | مضبوط في `tools/configure_ios.py` على: `com.tam.mobile.app`. سجّله بالحرف في Apple Developer Portal → Identifiers. |
| **Distribution Certificate (.p12)** | شهادة توزيع (Apple Distribution)، تُصدَّر من Keychain على أي Mac بصيغة `.p12` محمية بكلمة مرور. |
| **Provisioning Profile** | من نوع **Ad Hoc**، يتطلب تسجيل UDID جهاز أمين المالية مسبقًا في Apple Developer Portal. |

## طريقة التثبيت: Ad Hoc

مناسبة لمستخدم واحد (أمين المالية) دون تعقيد App Store Connect —
تثبيت مباشر لملف IPA على حتى 100 جهاز مسجَّل مسبقًا، بلا مراجعة من
Apple، ونتيجة فورية بعد كل بناء.

## خطوات الحصول على كل ملف (لمرة واحدة فقط)

تحتاج الوصول لأي جهاز Mac لمرة واحدة فقط (جهاز صديق، خدمة Mac-in-cloud،
أو مقهى إنترنت) — بعدها كل بناء لاحق يتم بالكامل عبر GitHub Actions
بلا Mac:

1. **UDID جهاز أمين المالية**: الإعدادات → عام → حول → مرِّر لأسفل
   لنسخ **Identifier (UDID)**، أو عبر توصيله بأي Mac وفتح Finder.
2. **تسجيل الجهاز**: developer.apple.com → Devices → أضف UDID.
3. **تسجيل الـ Identifier** (`com.tam.mobile.app`) في Identifiers.
4. **توليد Distribution Certificate**: Keychain Access على Mac →
   Certificate Assistant → Request a Certificate → ارفع الطلب في
   developer.apple.com → Certificates → نزّل الشهادة وثبّتها في
   Keychain → صدّرها بصيغة `.p12` مع كلمة مرور.
5. **توليد Ad Hoc Provisioning Profile**: developer.apple.com →
   Profiles → Ad Hoc → اختر الـ Identifier والشهادة وجهاز أمين
   المالية المسجَّل → نزّل ملف `.mobileprovision`.

## أين تضع كل شيء في GitHub (Secrets)

من صفحة المستودع: **Settings → Secrets and variables → Actions → New
repository secret**:

| اسم Secret | القيمة |
|---|---|
| `IOS_DISTRIBUTION_CERT_BASE64` | ناتج `base64 -i Certificate.p12 \| pbcopy` |
| `IOS_DISTRIBUTION_CERT_PASSWORD` | كلمة المرور التي وضعتها عند تصدير .p12 |
| `IOS_KEYCHAIN_PASSWORD` | أي كلمة مرور عشوائية جديدة (لـ Keychain مؤقت على الـ runner فقط) |
| `IOS_PROVISION_PROFILE_BASE64` | ناتج `base64 -i Profile.mobileprovision \| pbcopy` |
| `IOS_PROVISION_PROFILE_NAME` | الاسم الدقيق لملف التوفير كما كتبته عند إنشائه |
| `IOS_TEAM_ID` | Team ID (10 محارف) |
| `IOS_EXPORT_METHOD` | اتركه فارغًا أو اكتب `ad-hoc` |

`SUPABASE_URL` و`SUPABASE_PUBLISHABLE_KEY` موجودان مسبقًا (يستخدمهما
build-signed-apk.yml أيضًا) — لا حاجة لإضافتهما من جديد.

**لا تضع أبدًا** كلمة مرور Apple ID، أو أي ملف `.p12`/`.mobileprovision`
مباشرة في Git — فقط عبر GitHub Secrets.

## ماذا يحدث بعد إضافة الـ Secrets

1. أي `push` إلى `main` يشغّل `.github/workflows/build-ios.yml`
   تلقائيًا (تمامًا مثل build-signed-apk.yml).
2. `build-unsigned-verify` يعمل دائمًا — يتحقق أن الكود يبني على iOS.
3. `build-signed-ipa` يُتخطى تلقائيًا إن كانت Secrets ناقصة، وينتج
   IPA حقيقيًا إن كانت مكتملة — يظهر في تبويب **Releases** بنفس طريقة
   ظهور APK أندرويد.

## تثبيت IPA على iPhone أمين المالية (بدون Mac)

بما أن التوزيع Ad Hoc، لا يقبل iOS تثبيت IPA بالنقر المباشر. استخدم
**Diawi** (diawi.com):

1. نزّل ملف IPA من صفحة Releases في المستودع (من أي هاتف).
2. ارفعه إلى diawi.com (مجاني للاستخدام الأساسي).
3. افتح الرابط الناتج **من متصفح Safari على آيفون أمين المالية نفسه**
   (يجب أن يكون UDID هذا الجهاز مسجَّلًا في الخطوة 2 أعلاه) → اضغط
   تثبيت.
4. أول تشغيل: الإعدادات → عام → VPN وإدارة الجهاز → ثق بالمطوّر.
