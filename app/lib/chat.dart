import 'package:material_ui/material_ui.dart';

import 'api.dart';

/// One-click AI: pressing the home button records consent (core + ai, stated on the button) and starts a
/// guided conversation. Every message is checked by the server policy before any AI call.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.api, required this.session, this.title});
  final Api api;
  final ChatSession session;
  final String? title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _Msg {
  _Msg(this.mine, this.text, {this.status, this.guard, this.actions = const []});
  final bool mine;
  final String text;
  final String? status, guard;
  final List<Map<String, dynamic>> actions;
}

const _guardLabel = {
  'injection': 'ขอเปลี่ยนกฎ', 'sensitive': 'ข้อมูลส่วนตัว', 'guarantee': 'ขอการรับประกัน',
  'scam': 'เสี่ยงมิจฉาชีพ/เงินกู้', 'off_topic': 'นอกเรื่อง', 'unclear': 'นอกขอบเขต',
};

String _who(_Msg m) {
  if (m.guard != null && _guardLabel.containsKey(m.guard)) return '🛡️ กฎของแอป: ${_guardLabel[m.guard]}';
  return switch (m.status) {
    'ok' => '🤖 AI',
    'guarded' => '🤖 ผู้ช่วย (ตามเช็คลิสต์)',
    'fallback_rules' => '🤖 ผู้ช่วย (AI ไม่พร้อม ตอบด้วยกฎ)',
    _ => '🤖 ผู้ช่วย',
  };
}

/// Lives as long as the app (held by the home screen), so going back and opening the chat again keeps the conversation.
class ChatSession {
  final List<_Msg> _msgs = [];
  final Set<String> decided = {};
  List<String> quick = [];
  String? conversationId;
  bool get started => conversationId != null;

  /// The person sent at least one message. Only then the home button says "คุยกับ AI ต่อ".
  bool get talked => _msgs.any((m) => m.mine);
  void reset() { _msgs.clear(); decided.clear(); quick = []; conversationId = null; }
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController input = TextEditingController();
  final ScrollController scroll = ScrollController();
  ChatSession get s => widget.session;
  List<_Msg> get msgs => s._msgs;
  Set<String> get decided => s.decided;
  List<String> get quick => s.quick;
  set quick(List<String> v) => s.quick = v;
  String? get conversationId => s.conversationId;
  set conversationId(String? v) => s.conversationId = v;
  String? error;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    if (s.started) {
      busy = false;
      _scrollDown();
    } else {
      _start();
    }
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await widget.api.consent(ai: true);
      if (!mounted) return;
      final c = await widget.api.post('/v1/ai/conversations', {'mode': 'guided'});
      if (!mounted) return;
      conversationId = c['conversationId'] as String;
      setState(() {
        msgs.add(_Msg(false, '${c['greeting']}', status: 'guarded'));
        quick = (c['quickReplies'] as List? ?? const []).cast<String>();
        busy = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { error = e.message; busy = false; });
    }
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || conversationId == null || busy) return;
    input.clear();
    setState(() { msgs.add(_Msg(true, t)); quick = []; busy = true; });
    _scrollDown();
    try {
      final r = await widget.api.post('/v1/ai/conversations/$conversationId/messages', {'text': t});
      if (!mounted) return;
      final guard = (r['guard'] as Map?)?['kind'] as String?;
      setState(() {
        msgs.add(_Msg(false, '${r['reply']}', status: r['aiStatus'] as String?, guard: guard,
            actions: (r['pendingActions'] as List? ?? const []).cast<Map<String, dynamic>>()));
        quick = (r['quickReplies'] as List? ?? const []).cast<String>();
        busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 404) {
        // The server restarted and forgot this conversation: start a new one (answers already saved are not asked again).
        s.reset();
        setState(() => busy = true);
        await _start();
        return;
      }
      setState(() { msgs.add(_Msg(false, e.message, status: 'error')); busy = false; });
    }
    _scrollDown();
  }

  Future<void> _decide(Map<String, dynamic> a, bool yes) async {
    try {
      await widget.api.post('/v1/ai/conversations/$conversationId/actions/${a['id']}', {'decision': yes ? 'confirm' : 'reject'});
      if (!mounted) return;
      setState(() => decided.add(a['id'] as String));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(yes ? 'ทำแล้ว: ${a['label']}' : 'ยกเลิกแล้ว ไม่ได้เปลี่ยนอะไร')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'ให้ AI หาเงินให้ฉัน')),
      body: SafeArea(
        child: Column(children: [
          if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text(error!, style: const TextStyle(color: Colors.red))),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (_, i) => _bubble(msgs[i]),
            ),
          ),
          if (busy && conversationId != null) const LinearProgressIndicator(minHeight: 2),
          if (quick.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                children: [for (final q in quick) Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(label: Text(q), onPressed: () => _send(q)))],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(children: [
              Expanded(child: TextField(controller: input, textInputAction: TextInputAction.send, onSubmitted: _send, decoration: const InputDecoration(hintText: 'พิมพ์ตอบ หรือถามเรื่องเงินของคุณ', border: OutlineInputBorder()))),
              const SizedBox(width: 6),
              IconButton.filled(onPressed: busy ? null : () => _send(input.text), icon: const Icon(Icons.send)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final bg = m.mine ? const Color(0xFF0E9F6E) : const Color(0xFFF1F5F4);
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!m.mine) Text(_who(m), style: const TextStyle(fontSize: 11, color: Colors.black54)),
          Text(m.text, style: TextStyle(color: m.mine ? Colors.white : Colors.black87, fontSize: 15)),
          for (final a in m.actions)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: decided.contains(a['id'])
                  ? const Text('✓ ตัดสินใจแล้ว', style: TextStyle(fontSize: 12))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('⚡ ${a['label']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Row(children: [
                        FilledButton(onPressed: () => _decide(a, true), child: const Text('ยืนยัน')),
                        const SizedBox(width: 6),
                        OutlinedButton(onPressed: () => _decide(a, false), child: const Text('ไม่ใช่')),
                      ]),
                    ]),
            ),
        ]),
      ),
    );
  }
}
