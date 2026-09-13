"""يُدرج إعداد توقيع الإصدار (release signing) داخل ملف
android/app/build.gradle الذي يولّده أمر `flutter create` تلقائيًا.

لماذا هذا الملف موجود بالأساس: لا نُضمِّن مجلد android/ الكامل في
المستودع (تجنّبًا لتضارب إصدارات Gradle/Kotlin مع نسخة Flutter التي
يستخدمها GitHub Actions لاحقًا) — بل نترك `flutter create` يولّده
طازجًا في كل مرة يعمل فيها الـ workflow، مطابقًا تمامًا لنسخة
Flutter المثبَّتة، ثم نحقن هذا السكربت إعداد التوقيع بداخله.

يفشل هذا السكربت بوضوح (exit code != 0) إن لم يجد الأنماط المتوقعة،
بدل إنتاج APK غير موقَّع بصمت.
"""
import re
import sys

GRADLE_PATH = "android/app/build.gradle"

SIGNING_CONFIG_BLOCK = """
    signingConfigs {
        release {
            def keystorePropertiesFile = rootProject.file("key.properties")
            def keystoreProperties = new Properties()
            if (keystorePropertiesFile.exists()) {
                keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
            }
            if (keystoreProperties["storeFile"]) {
                storeFile file(keystoreProperties["storeFile"])
                storePassword keystoreProperties["storePassword"]
                keyAlias keystoreProperties["keyAlias"]
                keyPassword keystoreProperties["keyPassword"]
            }
        }
    }
"""


def main():
    with open(GRADLE_PATH, encoding="utf-8") as f:
        content = f.read()

    if "signingConfigs {" in content:
        print("signingConfigs already present — skipping injection (idempotent).")
        return

    # ندرج signingConfigs قبل أول buildTypes { — هذا الترتيب موجود
    # دائمًا في قالب Flutter الافتراضي المُولَّد بواسطة flutter create.
    match = re.search(r"\n(\s*)buildTypes\s*\{", content)
    if not match:
        print("ERROR: couldn't find 'buildTypes {' block in build.gradle — "
              "Flutter's generated template may have changed. Aborting so we "
              "never silently ship an unsigned release APK.", file=sys.stderr)
        sys.exit(1)

    insert_at = match.start()
    content = content[:insert_at] + "\n" + SIGNING_CONFIG_BLOCK + content[insert_at:]

    # نستبدل التوقيع الافتراضي (debug) داخل buildTypes.release فقط.
    content, count = re.subn(
        r"(release\s*\{[^}]*?signingConfig\s+)signingConfigs\.debug",
        r"\1signingConfigs.release",
        content,
        count=1,
        flags=re.DOTALL,
    )
    if count == 0:
        print("ERROR: couldn't find 'signingConfig signingConfigs.debug' inside "
              "the release buildType — aborting for the same reason as above.",
              file=sys.stderr)
        sys.exit(1)

    with open(GRADLE_PATH, "w", encoding="utf-8") as f:
        f.write(content)

    print("✔ Release signing config injected successfully.")


if __name__ == "__main__":
    main()
