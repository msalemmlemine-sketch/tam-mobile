"""يُدرج إعداد توقيع الإصدار (release signing) داخل ملف build.gradle
الذي يولّده أمر `flutter create` تلقائيًا — يدعم كلا الصيغتين:
Kotlin DSL (android/app/build.gradle.kts، الافتراضي في نسخ Flutter
الحديثة) والصيغة القديمة Groovy (android/app/build.gradle).

لماذا هذا الملف موجود بالأساس: لا نُضمِّن مجلد android/ الكامل في
المستودع (تجنّبًا لتضارب إصدارات Gradle/Kotlin مع نسخة Flutter التي
يستخدمها GitHub Actions لاحقًا) — بل نترك `flutter create` يولّده
طازجًا في كل مرة يعمل فيها الـ workflow، مطابقًا تمامًا لنسخة
Flutter المثبَّتة، ثم نحقن هذا السكربت إعداد التوقيع بداخله.

يفشل هذا السكربت بوضوح (exit code != 0) إن لم يجد الأنماط المتوقعة،
بدل إنتاج APK غير موقَّع بصمت.
"""
import os
import re
import sys

KTS_PATH = "android/app/build.gradle.kts"
GROOVY_PATH = "android/app/build.gradle"

KTS_SIGNING_BLOCK = """
    signingConfigs {
        create("release") {
            val keystorePropertiesFile = rootProject.file("key.properties")
            val keystoreProperties = java.util.Properties()
            if (keystorePropertiesFile.exists()) {
                keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
            }
            if (keystoreProperties["storeFile"] != null) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }
"""

GROOVY_SIGNING_BLOCK = """
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


def inject_kts():
    with open(KTS_PATH, encoding="utf-8") as f:
        content = f.read()

    if "signingConfigs {" in content:
        print("signingConfigs already present in build.gradle.kts — skipping.")
        return

    match = re.search(r"\n(\s*)buildTypes\s*\{", content)
    if not match:
        print("ERROR: couldn't find 'buildTypes {' in build.gradle.kts",
              file=sys.stderr)
        sys.exit(1)

    insert_at = match.start()
    content = content[:insert_at] + "\n" + KTS_SIGNING_BLOCK + content[insert_at:]

    content, count = re.subn(
        r'(release\s*\{[^}]*?signingConfig\s*=\s*signingConfigs\.getByName\()"debug"(\))',
        r'\1"release"\2',
        content,
        count=1,
        flags=re.DOTALL,
    )
    if count == 0:
        print("ERROR: couldn't find the debug signingConfig assignment inside "
              "the release buildType in build.gradle.kts", file=sys.stderr)
        sys.exit(1)

    with open(KTS_PATH, "w", encoding="utf-8") as f:
        f.write(content)
    print("✔ Release signing config injected into build.gradle.kts")


def inject_groovy():
    with open(GROOVY_PATH, encoding="utf-8") as f:
        content = f.read()

    if "signingConfigs {" in content:
        print("signingConfigs already present in build.gradle — skipping.")
        return

    match = re.search(r"\n(\s*)buildTypes\s*\{", content)
    if not match:
        print("ERROR: couldn't find 'buildTypes {' in build.gradle", file=sys.stderr)
        sys.exit(1)

    insert_at = match.start()
    content = content[:insert_at] + "\n" + GROOVY_SIGNING_BLOCK + content[insert_at:]

    content, count = re.subn(
        r"(release\s*\{[^}]*?signingConfig\s+)signingConfigs\.debug",
        r"\1signingConfigs.release",
        content,
        count=1,
        flags=re.DOTALL,
    )
    if count == 0:
        print("ERROR: couldn't find 'signingConfig signingConfigs.debug' inside "
              "the release buildType in build.gradle", file=sys.stderr)
        sys.exit(1)

    with open(GROOVY_PATH, "w", encoding="utf-8") as f:
        f.write(content)
    print("✔ Release signing config injected into build.gradle")


def main():
    if os.path.exists(KTS_PATH):
        inject_kts()
    elif os.path.exists(GROOVY_PATH):
        inject_groovy()
    else:
        print(f"ERROR: neither {KTS_PATH} nor {GROOVY_PATH} exists. "
              "Did `flutter create` run successfully before this step?",
              file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
