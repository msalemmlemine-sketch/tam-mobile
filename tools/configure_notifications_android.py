from pathlib import Path

root = Path('android')
app = root / 'app'
manifest = app / 'src' / 'main' / 'AndroidManifest.xml'

# Android permissions needed for scheduled local notifications and Android 13+ runtime notifications.
if manifest.exists():
    text = manifest.read_text()
    marker = '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />'
    if marker not in text:
        text = text.replace('<manifest ', '<manifest ', 1)
        insert_at = text.find('>') + 1
        text = text[:insert_at] + f'\n    {marker}\n    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />' + text[insert_at:]
        manifest.write_text(text)

# flutter_local_notifications 18.x uses Java time APIs for zoned scheduling.
# Enable core library desugaring in either Gradle DSL used by generated Flutter projects.
groovy = app / 'build.gradle'
kotlin = app / 'build.gradle.kts'

if groovy.exists():
    text = groovy.read_text()
    if 'coreLibraryDesugaringEnabled true' not in text:
        if 'compileOptions {' in text:
            text = text.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
        else:
            text += '\nandroid {\n    compileOptions {\n        coreLibraryDesugaringEnabled true\n        sourceCompatibility JavaVersion.VERSION_17\n        targetCompatibility JavaVersion.VERSION_17\n    }\n}\n'
    if 'coreLibraryDesugaring' not in text:
        if '\ndependencies {' in text:
            text = text.replace('\ndependencies {', '\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"', 1)
        else:
            text += '\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"\n}\n'
    groovy.write_text(text)
elif kotlin.exists():
    text = kotlin.read_text()
    if 'isCoreLibraryDesugaringEnabled = true' not in text:
        if 'compileOptions {' in text:
            text = text.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
        else:
            text += '\nandroid {\n    compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n        sourceCompatibility = JavaVersion.VERSION_17\n        targetCompatibility = JavaVersion.VERSION_17\n    }\n}\n'
    if 'coreLibraryDesugaring(' not in text:
        if '\ndependencies {' in text:
            text = text.replace('\ndependencies {', '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")', 1)
        else:
            text += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    kotlin.write_text(text)

print('Android notification configuration applied.')
