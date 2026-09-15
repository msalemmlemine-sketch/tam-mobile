/// إعدادات مزامنة Google Drive عبر Google Apps Script.
///
/// مرر القيم عند البناء:
/// flutter build apk --dart-define=DRIVE_SYNC_URL=https://script.google.com/macros/s/.../exec --dart-define=DRIVE_SYNC_API_KEY=...
class DriveSyncConfig {
  static const url = String.fromEnvironment('DRIVE_SYNC_URL', defaultValue: '');
  static const apiKey = String.fromEnvironment('DRIVE_SYNC_API_KEY', defaultValue: '');
  static bool get enabled => url.trim().isNotEmpty && apiKey.trim().isNotEmpty;
}
