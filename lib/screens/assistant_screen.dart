import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models/task_item.dart';
import '../services/ai_assistant_service.dart';
import '../services/task_store.dart';
import 'niko_setup_screen.dart';

enum AssistantMode { general, timeManagement }

class AssistantChooserScreen extends StatelessWidget {
  const AssistantChooserScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('اختر المساعد')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      _choice(context, AssistantMode.general, Icons.auto_awesome, 'نيكو العام', 'محادثة مفتوحة في الموضوعات المتنوعة.'),
      _choice(context, AssistantMode.timeManagement, Icons.schedule, 'مساعد تنظيم الوقت', 'يفهم جدولك المحلي ويقترح دون تعديل أي مهمة بلا موافقة.'),
    ],),
  );
  Widget _choice(BuildContext context, AssistantMode mode, IconData icon, String title, String subtitle) => Card(child: ListTile(contentPadding: const EdgeInsets.all(16), leading: CircleAvatar(child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AssistantScreen(mode: mode)))));
}

class AssistantScreen extends StatefulWidget {
  final AssistantMode mode;
  const AssistantScreen({super.key, this.mode = AssistantMode.general});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  final List<Map<String, String>> _messages = [];
  bool _sending = false, _listening = false, _ttsEnabled = false, _setupOpened = false;
  bool _speechReady = false;
  String? _localeId;
  String _speechBuffer = '';

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _messages.add({'role': 'assistant', 'text': widget.mode == AssistantMode.general ? 'أهلًا بك، أنا نيكو. كيف أستطيع مساعدتك؟' : 'أنا مساعد تنظيم الوقت. سأعتمد على جدولك المحلي دون اختراع مهام أو تعديلها دون موافقتك.'}); WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSetup()); }
  Future<void> _ensureSetup() async { if (_setupOpened || AiAssistantService.isConfigured || !mounted) return; _setupOpened = true; await Navigator.push(context, MaterialPageRoute(builder: (_) => const NikoSetupScreen())); }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); _speech.stop(); _tts.stop(); _controller.dispose(); _scroll.dispose(); super.dispose(); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if (state != AppLifecycleState.resumed && _listening) { _speech.stop(); if (mounted) setState(() => _listening = false); } }

  Future<void> _toggleMic() async {
    if (_listening) { await _speech.stop(); if (mounted) setState(() => _listening = false); return; }
    if (!_speechReady) { _speechReady = await _speech.initialize(onError: (_) { if (mounted) setState(() => _listening = false); }); if (_speechReady) { final locales = await _speech.locales(); for (final l in locales) { if (l.localeId.toLowerCase().startsWith('ar')) { _localeId = l.localeId; break; } } } }
    if (!_speechReady) { _error('لم تُمنح صلاحية الميكروفون أو التعرف الصوتي غير متاح.'); return; }
    _speechBuffer = _controller.text.trim();
    setState(() => _listening = true);
    await _speech.listen(localeId: _localeId, listenFor: const Duration(minutes: 5), pauseFor: const Duration(seconds: 2), listenMode: ListenMode.dictation, onResult: (r) { if (!mounted) return; final s = [_speechBuffer, r.recognizedWords.trim()].where((x) => x.isNotEmpty).join(' '); setState(() { _controller.text = s; _controller.selection = TextSelection.collapsed(offset: s.length); }); if (r.finalResult) _speechBuffer = s; });
  }

  Future<void> _send() async {
    if (_sending || _listening) return;
    final text = _controller.text.trim(); if (text.isEmpty) return;
    setState(() { _sending = true; _controller.clear(); _messages.add({'role': 'user', 'text': text}); }); _scrollEnd();
    try {
      final contextText = widget.mode == AssistantMode.timeManagement ? _timeContext() : null;
      final answer = await AiAssistantService.send(messages: _messages.map((m) => {'role': m['role']!, 'text': m['text']!}).toList(), systemInstruction: widget.mode == AssistantMode.general ? 'أنت نيكو، مساعد عربي عام. كن واضحًا ومختصرًا ولا تدّع تنفيذ شيء لم يحدث.' : 'أنت نيكو في وضع تنظيم الوقت. استخدم سياق الجدول المرفق فقط. لا تخترع مهامًا. اقترح التغييرات واطلب موافقة صريحة قبل التنفيذ. لا تعتبر انتهاء الوقت إنجازًا.\nالسياق المحلي:\n$contextText');
      if (!mounted) return; setState(() => _messages.add({'role': 'assistant', 'text': answer})); _scrollEnd(); if (_ttsEnabled) await _speak(answer);
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      if (mounted) setState(() => _messages.add({'role': 'assistant', 'text': message}));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  String _timeContext() {
    final now = DateTime.now(); final tasks = TaskStore.getAllTasks(); final lines = <String>[];
    for (final t in tasks) { if (t.occursOn(now) || t.nextOccurrenceAfter(now) != null) { final day = t.occursOn(now) ? now : t.nextOccurrenceAfter(now)!; lines.add('${t.title} | ${formatYmd(day)} ${formatHm(t.startOn(day))}-${formatHm(t.endOn(day))} | ${t.isDoneOn(day) ? 'مكتملة' : 'غير مكتملة'}'); } }
    return lines.isEmpty ? 'لا توجد مهام قادمة أو حالية في البيانات المحلية.' : lines.take(30).join('\n');
  }

  Future<void> _speak(String text) async { try { await _tts.setLanguage('ar-SA'); await _tts.setSpeechRate(0.48); await _tts.speak(text); } catch (_) {} }
  void _error(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }
  void _scrollEnd() => WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut); });

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.mode == AssistantMode.general ? 'نيكو' : 'تنظيم الوقت'), actions: [IconButton(tooltip: 'قراءة الردود', icon: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off), onPressed: () => setState(() => _ttsEnabled = !_ttsEnabled))]), body: Column(children: [Expanded(child: ListView.builder(controller: _scroll, padding: const EdgeInsets.all(12), itemCount: _messages.length, itemBuilder: (_, i) { final m = _messages[i]; final user = m['role'] == 'user'; return Align(alignment: user ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd, child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84), margin: const EdgeInsets.symmetric(vertical: 5), padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: user ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m['text']!, style: TextStyle(color: user ? Colors.white : null, height: 1.45)), if (!user) Align(alignment: AlignmentDirectional.centerEnd, child: IconButton(icon: const Icon(Icons.volume_up_outlined, size: 19), onPressed: () => _speak(m['text']!))) ]))); })), if (_sending) const Padding(padding: EdgeInsets.all(6), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('نيكو يفكر...')])), SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 8), child: Row(children: [IconButton(tooltip: _listening ? 'إيقاف التسجيل' : 'تسجيل صوتي', icon: Icon(_listening ? Icons.stop : Icons.mic_none, color: _listening ? Colors.red : Theme.of(context).colorScheme.primary), onPressed: _toggleMic), Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 5, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: _listening ? 'أستمع إليك...' : 'اكتب رسالتك...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(22))), onSubmitted: (_) => _send())), IconButton(tooltip: 'إرسال', icon: const Icon(Icons.send), onPressed: _sending ? null : _send)])))]));
}

class _SetupProxy extends StatelessWidget {
  const _SetupProxy();
  @override
  Widget build(BuildContext context) => const _SetupScreen();
}

class _SetupScreen extends StatefulWidget { const _SetupScreen(); @override State<_SetupScreen> createState() => _SetupScreenState(); }
class _SetupScreenState extends State<_SetupScreen> {
  bool busy = false; String? error;
  Future<void> test() async { setState(() { busy = true; error = null; }); try { await AiAssistantService.testConnection(); if (mounted) Navigator.pop(context); } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); } finally { if (mounted) setState(() => busy = false); } }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('إعداد نيكو')), body: Padding(padding: const EdgeInsets.all(24), child: Column(children: [const Icon(Icons.auto_awesome, size: 72, color: Color(0xFFC59D5F)), const SizedBox(height: 16), const Text('أضف المفتاح في lib/config/local_api_key.dart ثم اختبر الاتصال الحقيقي. لن يطلب نيكو مفتاحًا داخل التطبيق.'), const SizedBox(height: 24), FilledButton.icon(onPressed: busy ? null : test, icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi), label: Text(busy ? 'جارٍ الاختبار...' : 'اختبار الاتصال')), if (error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))])));
}
