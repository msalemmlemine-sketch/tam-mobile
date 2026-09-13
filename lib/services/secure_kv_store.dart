import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// واجهة تخزين آمن مجرَّدة — تفصل [AuthService] عن التفاصيل الفعلية
/// لـ flutter_secure_storage، حتى يمكن حقن بديل وهمي (in-memory) في
/// اختبارات التكامل بدل الاعتماد على قنوات المنصّة (Platform
/// Channels) غير المتوفرة في بيئة `flutter test` العادية.
abstract class SecureKvStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// التنفيذ الفعلي المستخدم في التطبيق الحقيقي على الجهاز.
class FlutterSecureKvStore implements SecureKvStore {
  FlutterSecureKvStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// تنفيذ وهمي في الذاكرة — يُستخدم في اختبارات التكامل فقط
/// (test/*_test.dart) لمحاكاة نفس سلوك التخزين الآمن بدون قنوات
/// منصّة حقيقية.
class InMemorySecureKvStore implements SecureKvStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}
