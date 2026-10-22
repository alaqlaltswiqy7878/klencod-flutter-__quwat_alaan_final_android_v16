import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'settings_store.dart';

class AiAssistantException implements Exception {
  final String message;
  const AiAssistantException(this.message);
  @override String toString() => message;
}

class AiAssistantService {
  static const String model = 'gemini-2.5-flash';
  static const Duration timeout = Duration(seconds: 35);
  static bool get isConfigured => SettingsStore.geminiApiKey.trim().isNotEmpty;

  static Future<String> send({required List<Map<String, String>> messages, String? systemInstruction}) async {
    final key = SettingsStore.geminiApiKey.trim();
    if (key.isEmpty) throw const AiAssistantException('أدخل مفتاح Gemini من إعداد نيكو داخل التطبيق أولًا.');
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key');
    final contents = messages.map((m) => {'role': m['role'] == 'assistant' ? 'model' : 'user', 'parts': [{'text': m['text'] ?? ''}]}).toList();
    final body = <String, dynamic>{'contents': contents};
    if (systemInstruction != null && systemInstruction.trim().isNotEmpty) body['systemInstruction'] = {'parts': [{'text': systemInstruction}]};
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(timeout);
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 429) throw const AiAssistantException('تم تجاوز الحد المجاني مؤقتًا. حاول لاحقًا.');
        if (response.statusCode == 401 || response.statusCode == 403) throw const AiAssistantException('مفتاح نيكو غير صالح أو غير مسموح لهذا النموذج.');
        throw const AiAssistantException('تعذر الوصول إلى خدمة نيكو حاليًا.');
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      final content = candidates != null && candidates.isNotEmpty ? (candidates.first as Map)['content'] : null;
      final parts = content is Map ? content['parts'] as List? : null;
      final first = parts?.isNotEmpty == true ? parts!.first : null;
      final text = first is Map && first['text'] is String ? first['text'] as String : null;
      if (text == null || text.trim().isEmpty) throw const AiAssistantException('وصل رد فارغ من نيكو. حاول مرة أخرى.');
      return text.trim();
    } on SocketException { throw const AiAssistantException('لا يوجد اتصال بالإنترنت. تحقق من اتصالك ثم حاول مرة أخرى.'); }
    on HttpException { throw const AiAssistantException('تعذر الاتصال بخدمة نيكو.'); }
    on TimeoutException { throw const AiAssistantException('انتهت مهلة الاتصال. حاول مرة أخرى.'); }
    on AiAssistantException { rethrow; }
    catch (_) { throw const AiAssistantException('حدث خطأ غير متوقع أثناء الاتصال بنيكو.'); }
    finally { client.close(force: true); }
  }
  static Future<bool> testConnection() async { await send(messages: const [{'role': 'user', 'text': 'أجب بكلمة: جاهز'}]); return true; }
}
