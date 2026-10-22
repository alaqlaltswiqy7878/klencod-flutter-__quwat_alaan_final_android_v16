import 'package:flutter/material.dart';
import '../services/ai_assistant_service.dart';
import '../services/settings_store.dart';

class NikoSetupScreen extends StatefulWidget {
  const NikoSetupScreen({super.key});
  @override State<NikoSetupScreen> createState() => _NikoSetupScreenState();
}

class _NikoSetupScreenState extends State<NikoSetupScreen> {
  final _key = TextEditingController();
  bool _hidden = true;
  bool _testing = false;
  String? _error;
  @override void initState() { super.initState(); _key.text = SettingsStore.geminiApiKey; }
  @override void dispose() { _key.dispose(); super.dispose(); }

  Future<void> _test() async {
    final value = _key.text.trim();
    if (value.isEmpty) { setState(() => _error = 'أدخل مفتاح Gemini أولًا.'); return; }
    await SettingsStore.saveGeminiApiKey(value);
    setState(() { _testing = true; _error = null; });
    try {
      await AiAssistantService.testConnection();
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الاتصال بنيكو بنجاح'))); Navigator.pop(context, true); }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _testing = false); }
  }

  Future<void> _clear() async { await SettingsStore.clearGeminiApiKey(); if (mounted) { _key.clear(); setState(() {}); } }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعداد نيكو')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.auto_awesome, size: 72, color: Color(0xFFC59D5F)),
        const SizedBox(height: 16),
        const Text('الصق مفتاح Gemini هنا. سيُحفظ محليًا على الهاتف فقط، ولن يُكتب في ملفات المشروع أو يُرفع إلى GitHub.'),
        const SizedBox(height: 18),
        TextField(controller: _key, obscureText: _hidden, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: 'Gemini API Key', suffixIcon: IconButton(icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hidden = !_hidden)))),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _testing ? null : _test, icon: _testing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering), label: Text(_testing ? 'جارٍ الاختبار...' : 'حفظ واختبار الاتصال')),
        TextButton.icon(onPressed: _clear, icon: const Icon(Icons.delete_outline), label: const Text('حذف المفتاح من الهاتف')),
        if (_error != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
      ])),
    );
  }
}
