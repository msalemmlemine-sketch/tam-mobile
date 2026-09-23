"""يُشغَّل داخل GitHub Actions (macos-latest) مباشرة بعد:

    flutter create --platforms=ios --org com.tam.mobile .

تمامًا كما يفعل tools/configure_notifications_android.py لمجلد
android/ المولَّد، هذا السكربت يعدّل مجلد ios/ المولَّد حديثًا ليطابق
احتياجات التطبيق الفعلية: اسم العرض، الصلاحيات المستخدمة فعليًا فقط،
والحد الأدنى لإصدار iOS.

لا نخزّن ios/ في المستودع (نفس منطق .gitignore الحالي لـ android/)
حتى لا تتعارض نسخته مع تحديثات Flutter لاحقًا.
"""

from pathlib import Path
import plistlib
import re

root = Path("ios")
info_plist_path = root / "Runner" / "Info.plist"
pbxproj_path = root / "Runner.xcodeproj" / "project.pbxproj"
podfile_path = root / "Podfile"

# ==============================================================
# 1) Info.plist — اسم العرض + الصلاحيات المستخدمة فعليًا فقط
# ==============================================================
if not info_plist_path.exists():
    raise SystemExit(f"لم يُعثر على {info_plist_path} — تأكد من تشغيل "
                      "flutter create --platforms=ios قبل هذا السكربت.")

with open(info_plist_path, "rb") as f:
    plist = plistlib.load(f)

plist["CFBundleDisplayName"] = "TAM Mobile"
plist["CFBundleName"] = "TAM Mobile"

# file_picker مستخدم بوضع FileType.image في
# lib/screens/settings/organization_settings_screen.dart (اختيار شعار
# المنظمة من مكتبة الصور). لا يُستخدم أي التقاط كاميرا مباشر في أي
# مكان بالتطبيق (لا وجود لحزمة image_picker أو ImagePicker.camera).
# نُضيف مفتاح مكتبة الصور دومًا كشبكة أمان: نسخ file_picker الحديثة
# تستخدم PHPickerViewController على iOS 14+ الذي لا يفرضه النظام
# صراحة، لكن Apple توصي بوجوده، وقد يُطلب في مراجعة App Store أو على
# مسارات احتياطية أقدم.
plist["NSPhotoLibraryUsageDescription"] = (
    "يحتاج التطبيق الوصول إلى مكتبة الصور لاختيار شعار المنظمة."
)

# flutter_local_notifications: تذكيرات محلية مجدولة (يومي 24 و26). لا
# حاجة لأي مفتاح Info.plist إضافي لهذا الاستخدام (ليست Push
# Notifications)، الإذن يُطلب وقت التشغيل عبر requestPermissions().

# file_picker (FileType.custom/.any) يستخدم UIDocumentPickerViewController
# عبر نظام iOS مباشرة، ولا يحتاج مفتاح صلاحية في Info.plist.

# share_plus (مشاركة النسخ الاحتياطي وملفات PDF/CSV) لا يحتاج مفاتيح
# Info.plist؛ لكنه يتطلب على iPad تحديد نقطة انطلاق للقائمة المنبثقة،
# وهو ما تتولاه الحزمة تلقائيًا.

# يمنع سؤال "تصدير التشفير" التلقائي عند رفع Build إلى App Store
# Connect/TestFlight (التطبيق يستخدم فقط HTTPS/TLS القياسي عبر
# supabase_flutter، وهو مستثنى من قواعد ITAR/EAR الأمريكية):
plist.setdefault("ITSAppUsesNonExemptEncryption", False)

with open(info_plist_path, "wb") as f:
    plistlib.dump(plist, f)

print(f"تم تحديث {info_plist_path}")

# ==============================================================
# 2) Deployment target — إصدار iOS حديث يدعم كل الحزم المستخدمة
#    (flutter_local_notifications 18.x وsupabase_flutter 2.x يتطلبان
#    iOS 13 على الأقل؛ نستخدم 13.0 كحد أدنى آمن وحديث).
# ==============================================================
MIN_IOS = "13.0"

# Bundle Identifier ثابت وصريح، بدل الاعتماد على تحويل Flutter التلقائي
# لاسم "tam_mobile" (قد يتغيّر شكله بين نسخ Flutter). هذا هو نفس
# المعرّف الذي يجب تسجيله في Apple Developer Portal — انظر IOS_SIGNING.md.
BUNDLE_ID = "com.tam.mobile.app"

if pbxproj_path.exists():
    text = pbxproj_path.read_text()

    text, deploy_n = re.subn(
        r"IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;",
        f"IPHONEOS_DEPLOYMENT_TARGET = {MIN_IOS};",
        text,
    )
    if deploy_n == 0:
        raise SystemExit(
            "ERROR: لم يُعثر على IPHONEOS_DEPLOYMENT_TARGET في "
            "project.pbxproj."
        )

    # يوجد هذا المفتاح عادة 3 مرات لهدف Runner (Debug/Release/Profile)
    # ومرات إضافية لهدف RunnerTests بلاحقة ".RunnerTests" — نستبدل
    # الجميع بنفس القيمة الثابتة عبر Regex (بدل نص حرفي متوقَّع) حتى لا
    # يعتمد هذا على شكل التحويل الدقيق الذي يولّده أمر flutter create
    # لاسم "tam_mobile"، والذي قد يختلف بين نسخ Flutter.
    def _replace_bundle_id(match: "re.Match[str]") -> str:
        suffix = ".RunnerTests" if match.group(1) else ""
        return f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}{suffix};"

    text, bundle_n = re.subn(
        r"PRODUCT_BUNDLE_IDENTIFIER = [\w.]+?(\.RunnerTests)?;",
        _replace_bundle_id,
        text,
    )
    if bundle_n == 0:
        raise SystemExit(
            "ERROR: لم يُعثر على أي سطر PRODUCT_BUNDLE_IDENTIFIER في "
            "project.pbxproj — تأكد من أن flutter create نجح فعلًا قبل "
            "تشغيل هذا السكربت."
        )

    pbxproj_path.write_text(text)
    print(f"تم ضبط IPHONEOS_DEPLOYMENT_TARGET = {MIN_IOS} و "
          f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID} في project.pbxproj")

if podfile_path.exists():
    text = podfile_path.read_text()
    new_line = f"platform :ios, '{MIN_IOS}'"
    text, podfile_n = re.subn(
        r"#?\s*platform :ios, '[\d.]+'",
        new_line,
        text,
        count=1,
    )
    if podfile_n == 0:
        text = new_line + "\n" + text
        print("تنبيه: لم يُعثر على سطر platform :ios المتوقَّع في Podfile؛ "
              "تمت إضافته يدويًا في أول الملف.")
    podfile_path.write_text(text)
    print(f"تم ضبط platform :ios, '{MIN_IOS}' في Podfile")

print("تهيئة iOS اكتملت.")
