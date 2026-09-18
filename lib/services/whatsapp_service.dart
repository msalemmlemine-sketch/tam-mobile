import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/database/app_database.dart';
import 'secure_kv_store.dart';

class WhatsAppService {
  WhatsAppService({SecureKvStore? store}) : _store = store ?? FlutterSecureKvStore();
  final SecureKvStore _store;
  static const endpointKey = 'tam_whatsapp_endpoint';
  static const secretKey = 'tam_whatsapp_client_secret';

  Future<void> configure({required String endpoint, required String clientSecret}) async {
    await _store.write(endpointKey, endpoint.trim());
    await _store.write(secretKey, clientSecret.trim());
  }

  Future<bool> get enabled async => (await _store.read(endpointKey))?.trim().isNotEmpty == true;

  Future<Map<String, dynamic>> sendTemplate({required int memberId, required String phone, required String templateName, required String languageCode, required List<String> parameters}) async {
    final endpoint = await _store.read(endpointKey);
    final secret = await _store.read(secretKey);
    if (endpoint == null || endpoint.isEmpty || secret == null || secret.isEmpty) throw StateError('لم يتم إعداد WhatsApp API');
    final response = await http.post(Uri.parse(endpoint), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'action':'sendWhatsApp','clientSecret':secret,'memberId':memberId,'phone':phone,'templateName':templateName,'languageCode':languageCode,'parameters':parameters})).timeout(const Duration(seconds:30));
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 400 || body is! Map || body['ok'] != true) throw StateError(body is Map ? '${body['error'] ?? 'فشل الإرسال'}' : 'استجابة غير صالحة');
    return Map<String,dynamic>.from(body);
  }

  Future<int> queueOverdueMessages(List<Map<String,dynamic>> rows) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    var count = 0;
    for (final row in rows) {
      final memberId = row['member_id'] as int?;
      final phone = row['phone'] as String?;
      if (memberId == null || phone == null || phone.trim().isEmpty) continue;
      await db.insert('whatsapp_messages', {'member_id':memberId,'phone':phone,'message_type':'overdue','debt_amount':row['remaining'] ?? 0,'months_due':row['months_due'] ?? '','scheduled_at':now,'status':'pending','created_at':now});
      count++;
    }
    return count;
  }
}
