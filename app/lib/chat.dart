import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'common.dart';
import 'opp_screen.dart';
import 'opportunity_catalog.dart';
import 'task_screen.dart';

/// One-click AI: pressing the home button records consent (core + ai, stated on the button) and starts a
/// guided conversation. Every message is checked by the server policy before any AI call.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.app, required this.session, this.title});
  final AppState app;
  final ChatSession session;
  final String? title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

typedef _PlanLink = ({String taskId, String label});

class _OpportunityLink {
  const _OpportunityLink(this.id, this.title, this.data);

  final String id, title;
  final Map<String, dynamic> data;
  String? get actionId => data['actionId'] as String?;
  String? get savedTaskId => data['savedTaskId'] as String?;

  Uri? get source {
    final value = data['sourceUrl'];
    if (value is! String || data['sourceStatus'] == 'unavailable') return null;
    final uri = Uri.tryParse(value);
    return uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }

  String get sourceLabel {
    return switch (data['dataStatus']) {
      'mock' => 'DEMO / MOCK',
      'curated' => switch (data['checkedAt']) {
        final String date when DateTime.tryParse(date) != null =>
          'ตรวจแล้ว ${date.split('T').first}',
        _ => 'แหล่งข้อมูลคัดตรวจ',
      },
      'live' => 'ข้อมูลจากต้นทาง',
      'open_data' => 'ข้อมูลเปิด',
      _ => 'ยังไม่ทราบที่มา',
    };
  }
}

class _Msg {
  _Msg(this.mine, this.text, {
    this.status,
    this.guard,
    this.actions = const [],
    this.planLinks = const [],
    this.opportunities = const [],
  });
  final bool mine;
  final String text;
  final String? status, guard;
  final List<Map<String, dynamic>> actions;
  final List<_PlanLink> planLinks;
  final List<_OpportunityLink> opportunities;
}

const _guardLabel = {
  'injection': 'ขอเปลี่ยนกฎ', 'sensitive': 'ข้อมูลส่วนตัว', 'guarantee': 'ขอการรับประกัน',
  'scam': 'เสี่ยงมิจฉาชีพ/เงินกู้', 'off_topic': 'นอกเรื่อง',
};

String _who(_Msg m) {
  if (m.guard != null && _guardLabel.containsKey(m.guard)) return '🛡️ กฎของแอป: ${_guardLabel[m.guard]}';
  return switch (m.status) {
    'saved' => '🤖 ผู้ช่วย',
    'ok' => '🤖 AI',
    'guarded' => '🤖 ผู้ช่วย (ตามเช็คลิสต์)',
    'fallback_rules' => '🤖 ผู้ช่วย (AI ไม่พร้อม ตอบด้วยกฎ)',
    _ => '🤖 ผู้ช่วย',
  };
}

/// Lives as long as the app (held by the home screen), so going back and opening the chat again keeps the conversation.
class ChatSession extends ChangeNotifier {
  final List<_Msg> _msgs = [];
  final Set<String> decided = {};
  final Set<Uri> unavailableSources = {};
  List<String> quick = [];
  String? stepId;
  String? conversationId;
  bool _sending = false;
  bool get started => conversationId != null;

  /// The person sent at least one message. Only then the home button says "คุยกับ AI ต่อ".
  bool get talked => _msgs.any((m) => m.mine);
  void reset() {
    _msgs.clear();
    decided.clear();
    unavailableSources.clear();
    quick = [];
    stepId = null;
    conversationId = null;
    _sending = false;
    notifyListeners();
  }

  void _updateMessages(VoidCallback update) {
    update();
    notifyListeners();
  }
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController input = TextEditingController();
  final ScrollController scroll = ScrollController();
  final Set<String> deciding = {};
  Api get api => widget.app.api;
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
    s.addListener(_sessionChanged);
    if (s.started) {
      busy = false;
      _scrollDown();
    } else {
      _start();
    }
  }

  @override
  void dispose() {
    s.removeListener(_sessionChanged);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollDown();
  }

  Future<void> _start() async {
    try {
      await api.consent(ai: true);
      if (!mounted) return;
      final c = await api.post('/v1/ai/conversations', {'mode': 'guided'});
      if (!mounted) return;
      conversationId = c['conversationId'] as String;
      setState(() {
        msgs.add(_Msg(false, '${c['greeting']}', status: 'guarded'));
        quick = (c['quickReplies'] as List? ?? const []).cast<String>();
        s.stepId = (c['step'] as Map?)?['id'] as String?;
        busy = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { error = e.message; busy = false; });
    }
  }

  Future<void> _send(String text, {String? stepId}) async {
    final t = text.trim();
    if (t.isEmpty || conversationId == null || busy || s._sending) return;
    input.clear();
    final session = s;
    final id = conversationId;
    final pending = _Msg(true, 'กำลังตรวจข้อความ…');
    session._updateMessages(() {
      msgs.add(pending);
      session._sending = true;
    });
    try {
      final r = await api.post('/v1/ai/conversations/$id/messages', {
        'text': t,
        'stepId': ?stepId,
      });
      if (session.conversationId != id) return;
      final guard = (r['guard'] as Map?)?['kind'] as String?;
      final planLinks = [
        for (final plan in r['planLinks'] as List? ?? const [])
          if (plan case {'taskId': final String taskId, 'title': final String title})
            (taskId: taskId, label: 'เปิดแผน $title'),
      ];
      final opportunities = [
        for (final link in r['opportunityLinks'] as List? ?? const [])
          if (link case {
            'opportunityId': final String id,
            'title': final String title,
          })
            _OpportunityLink(id, title, Map<String, dynamic>.from(link)),
      ];
      final index = session._msgs.indexOf(pending);
      if (index >= 0) {
        session._updateMessages(() {
          final maskedText = r['maskedText'];
          session._msgs[index] = _Msg(
            true,
            maskedText is String
                ? maskedText
                : guard == 'sensitive' ? 'ซ่อนข้อความที่มีข้อมูลส่วนตัว' : t,
          );
          session._msgs.add(_Msg(false, '${r['reply']}', status: r['aiStatus'] as String?, guard: guard,
              actions: (r['pendingActions'] as List? ?? const []).cast<Map<String, dynamic>>(),
              planLinks: planLinks, opportunities: opportunities));
          session.quick = (r['quickReplies'] as List? ?? const []).cast<String>();
          session.stepId = (r['step'] as Map?)?['id'] as String?;
          session._sending = false;
        });
      }
    } on ApiException catch (e) {
      final index = session._msgs.indexOf(pending);
      if (session.conversationId != id) return;
      if (e.status == 404 && mounted) {
        // The server restarted and forgot this conversation: start a new one (answers already saved are not asked again).
        s.reset();
        setState(() => busy = true);
        await _start();
        return;
      }
      if (index >= 0) {
        session._updateMessages(() {
          session._msgs[index] = _Msg(true, 'ส่งข้อความไม่สำเร็จ');
          session._msgs.add(_Msg(false, 'ตรวจข้อความไม่ได้ ลองส่งอีกครั้งนะคะ', status: 'error'));
          session._sending = false;
        });
      }
    }
    _scrollDown();
  }

  Future<void> _decide(Map<String, dynamic> a, bool yes) async {
    final actionId = a['id'] as String;
    if (deciding.contains(actionId)) return;
    setState(() => deciding.add(actionId));
    try {
      final response = await api.post('/v1/ai/conversations/$conversationId/actions/$actionId', {'decision': yes ? 'confirm' : 'reject'});
      if (!mounted) return;
      setState(() => decided.add(actionId));
      final task = response['result'];
      if (response['status'] == 'done') widget.app.bump();
      if (response['status'] == 'done' && a['tool'] == 'create_task' && task is Map && task['id'] is String) {
        final steps = task['steps'] as List? ?? const [];
        final next = task['doneCount'] as int? ?? 0;
        final summary = [
          'บันทึกในแผนของฉันแล้ว',
          '${task['title']}',
          if (next >= 0 && next < steps.length) 'ขั้นต่อไป: ${steps[next]}',
        ].join('\n');
        setState(() => msgs.add(_Msg(false, summary, status: 'saved', planLinks: [(taskId: task['id'] as String, label: 'ดูแผนของฉัน ›')])));
        _scrollDown();
      } else {
        toast(context, yes ? 'ทำแล้ว: ${a['label']}' : 'ยกเลิกแล้ว ไม่ได้เปลี่ยนอะไร');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, e.message);
    } finally {
      if (mounted) setState(() => deciding.remove(actionId));
    }
  }

  Future<void> _openSource(_OpportunityLink link, Uri source) async {
    final session = s;
    final conversation = conversationId;
    final opened = await openExternal(
      context,
      widget.app,
      url: source.toString(),
      title: link.title,
      opportunityId: link.id,
      askAfterReturn: false,
      showError: false,
    );
    if (!opened && session.conversationId == conversation) {
      session._updateMessages(() => session.unavailableSources.add(source));
    }
  }

  void _openTask(String taskId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TaskScreen(app: widget.app, taskId: taskId),
    ));
  }

  Widget _opportunityRow(_OpportunityLink link, Map<String, dynamic>? action) {
    final source = link.source;
    final saveId = action?['id'];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(link.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text([
            if (link.data['workMode'] == 'remote')
              'ทำจากบ้าน'
            else if (link.data['district'] case final String district)
              'เขต$district',
            link.sourceLabel,
          ].join(' · ')),
          if (link.data['money'] is Map) Text(oppMoney(link.data)),
          Wrap(
            spacing: 4,
            children: [
              if (source != null || link.data['sourceStatus'] == 'unavailable')
                TextButton(
                  onPressed: source == null || s.unavailableSources.contains(source)
                      ? null
                      : () => _openSource(link, source),
                  child: Text(
                    source == null || s.unavailableSources.contains(source)
                        ? 'ต้นทางยังเปิดไม่ได้'
                        : 'ดูต้นทาง',
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => OppScreen(app: widget.app, opportunityId: link.id),
                )),
                child: const Text('ดูรายละเอียด'),
              ),
              if (link.savedTaskId case final String taskId)
                TextButton(
                  onPressed: () => _openTask(taskId),
                  child: const Text('บันทึกไว้แล้ว · ดูแผน ›'),
                )
              else if (action != null && saveId is String && !decided.contains(saveId))
                FilledButton(
                  onPressed: deciding.contains(saveId) ? null : () => _decide(action, true),
                  child: const Text('บันทึกเข้าแผน'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final displayedStepId = s.stepId;
    final sending = busy || s._sending;
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
          if (sending && conversationId != null) const LinearProgressIndicator(minHeight: 2),
          if (quick.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                children: [for (final q in quick) Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(label: Text(q), onPressed: sending ? null : () => _send(q, stepId: displayedStepId)))],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(children: [
              Expanded(child: TextField(controller: input, textInputAction: TextInputAction.send, onSubmitted: _send, decoration: const InputDecoration(hintText: 'พิมพ์ตอบ หรือถามเรื่องเงินของคุณ', border: OutlineInputBorder()))),
              const SizedBox(width: 6),
              IconButton.filled(onPressed: sending ? null : () => _send(input.text), icon: const Icon(Icons.send)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final bg = m.mine ? const Color(0xFF0E9F6E) : const Color(0xFFF1F5F4);
    final actionsById = {for (final action in m.actions) action['id']: action};
    final rowActionIds = {for (final link in m.opportunities) link.actionId};
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
          for (final plan in m.planLinks)
            TextButton(
              onPressed: () => _openTask(plan.taskId),
              child: Text(plan.label),
            ),
          for (final link in m.opportunities)
            _opportunityRow(link, actionsById[link.actionId]),
          for (final a in m.actions.where((a) => !rowActionIds.contains(a['id'])))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: decided.contains(a['id'])
                  ? const Text('✓ ตัดสินใจแล้ว', style: TextStyle(fontSize: 12))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('⚡ ${a['label']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Row(children: [
                        FilledButton(onPressed: deciding.contains(a['id']) ? null : () => _decide(a, true), child: const Text('ยืนยัน')),
                        const SizedBox(width: 6),
                        OutlinedButton(onPressed: deciding.contains(a['id']) ? null : () => _decide(a, false), child: const Text('ไม่ใช่')),
                      ]),
                    ]),
            ),
        ]),
      ),
    );
  }
}
