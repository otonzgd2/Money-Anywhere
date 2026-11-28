import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'chat_composer.dart';
import 'common.dart';
import 'opp_screen.dart';
import 'opportunity_catalog.dart';
import 'task_screen.dart';
import 'thang_rot_theme.dart';

/// The server checks each message before passing it to the AI.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.app,
    required this.session,
    this.title,
  });
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
  _Msg(
    this.mine,
    this.text, {
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
  'injection': 'ขอเปลี่ยนกฎ',
  'sensitive': 'ข้อมูลส่วนตัว',
  'guarantee': 'ขอการรับประกัน',
  'scam': 'เสี่ยงมิจฉาชีพ/เงินกู้',
  'off_topic': 'นอกเรื่อง',
};

String _who(_Msg m) {
  // With the soft guard a flagged message can still be answered by the rules fallback.
  if (m.status == 'fallback_rules') {
    return 'ทางรอด · ตอบตามเกณฑ์เมื่อ AI ไม่พร้อม';
  }
  if (m.guard != null && _guardLabel.containsKey(m.guard)) {
    return 'กฎของแอป · ${_guardLabel[m.guard]}';
  }
  return switch (m.status) {
    'ok' => 'ทางรอด AI',
    'guarded' => 'ทางรอด · ข้อมูลตามเกณฑ์',
    _ => 'ผู้ช่วยทางรอด',
  };
}

enum ChatSubmission { ignored, cancelled, sent, failed }

enum _ChatPhase { idle, working, choosingConsent }

/// Holds the conversation and arbitrates sends from Home and the chat tab.
class ChatSession extends ChangeNotifier {
  final List<_Msg> _msgs = [];
  final Set<String> decided = {};
  final Set<String> deciding = {};
  final Map<String, ({String message, bool retry})> actionErrors = {};
  final Set<Uri> unavailableSources = {};
  List<String> quick = [];
  String? stepId;
  String? conversationId;
  String? error;
  String? _retryDraft;
  _ChatPhase _phase = _ChatPhase.idle;
  bool get sending => _phase != _ChatPhase.idle;
  int _revision = 0;
  bool _approved = false;
  int questionNumber = 0;
  bool get started => conversationId != null;
  bool get talked => _msgs.any((m) => m.mine);

  void reset({bool keepApproval = false}) {
    _revision++;
    _clearConversation();
    _phase = _ChatPhase.idle;
    error = null;
    if (!keepApproval) _approved = false;
    notifyListeners();
  }

  void _clearConversation() {
    _msgs.clear();
    decided.clear();
    deciding.clear();
    actionErrors.clear();
    unavailableSources.clear();
    quick = [];
    stepId = null;
    conversationId = null;
    questionNumber = 0;
    _retryDraft = null;
  }

  void _updateMessages(VoidCallback update) {
    update();
    notifyListeners();
  }

  String? _takeRetryDraft() {
    final draft = _retryDraft;
    _retryDraft = null;
    return draft;
  }

  Future<ChatSubmission> submit(
    AppState app,
    String text, {
    required Future<bool> Function() confirmConsent,
    Future<void> Function()? prepare,
    VoidCallback? onDispatch,
    String? stepId,
  }) async {
    if (text.trim().isEmpty || sending || app.deletingData) {
      return ChatSubmission.ignored;
    }
    final revision = _revision;
    bool isCurrent() => revision == _revision && !app.deletingData;
    _phase = _ChatPhase.working;
    error = null;
    notifyListeners();
    _Msg? pending;
    try {
      if (!started) {
        // A seeded DEMO profile may already have server consent. Its chat
        // still needs a decision from the person using this app session.
        final needsConsent =
            (app.demo && !_approved) ||
            (await app.api.currentPurposes())?['ai'] != true;
        if (!isCurrent()) return ChatSubmission.ignored;
        if (needsConsent) {
          _phase = _ChatPhase.choosingConsent;
          notifyListeners();
          if (!await confirmConsent()) return ChatSubmission.cancelled;
          if (!isCurrent()) return ChatSubmission.ignored;
          _phase = _ChatPhase.working;
          notifyListeners();
        }
        if (prepare != null) await prepare();
        if (!isCurrent()) return ChatSubmission.ignored;
        if (needsConsent) {
          await app.api.consent(ai: true);
          if (!isCurrent()) return ChatSubmission.ignored;
          _approved = true;
          app.bump();
        }
        final created = await app.api.post('/v1/ai/conversations', {
          'mode': 'guided',
        });
        if (!isCurrent()) return ChatSubmission.ignored;
        conversationId = created['conversationId'] as String;
        _msgs.add(_Msg(false, '${created['greeting']}', status: 'guarded'));
        quick = (created['quickReplies'] as List? ?? const []).cast<String>();
        this.stepId = (created['step'] as Map?)?['id'] as String?;
        questionNumber = this.stepId == null ? 0 : 1;
      }

      pending = _Msg(true, 'กำลังตรวจข้อความ…');
      _msgs.add(pending);
      notifyListeners();
      onDispatch?.call();
      final result = await app.api.post(
        '/v1/ai/conversations/$conversationId/messages',
        {'text': text, 'stepId': ?stepId},
      );
      if (!isCurrent()) return ChatSubmission.ignored;
      final guard = (result['guard'] as Map?)?['kind'] as String?;
      final maskedText = result['maskedText'];
      _msgs[_msgs.indexOf(pending)] = _Msg(
        true,
        maskedText is String
            ? maskedText
            : guard == 'sensitive'
            ? 'ซ่อนข้อความที่มีข้อมูลส่วนตัว'
            : text,
      );
      _msgs.add(
        _Msg(
          false,
          '${result['reply']}',
          status: result['aiStatus'] as String?,
          guard: guard,
          actions: (result['pendingActions'] as List? ?? const [])
              .cast<Map<String, dynamic>>(),
          planLinks: [
            for (final plan in result['planLinks'] as List? ?? const [])
              if (plan case {
                'taskId': final String taskId,
                'title': final String title,
              })
                (taskId: taskId, label: 'เปิดแผน $title'),
          ],
          opportunities: [
            for (final link in result['opportunityLinks'] as List? ?? const [])
              if (link case {
                'opportunityId': final String id,
                'title': final String title,
              })
                _OpportunityLink(id, title, Map<String, dynamic>.from(link)),
          ],
        ),
      );
      quick = (result['quickReplies'] as List? ?? const []).cast<String>();
      final nextStep = (result['step'] as Map?)?['id'] as String?;
      if (nextStep != null && nextStep != this.stepId) questionNumber++;
      this.stepId = nextStep;
      return ChatSubmission.sent;
    } on ApiException catch (failure) {
      if (!isCurrent()) return ChatSubmission.ignored;
      if (pending != null) {
        if (failure.status == 404) {
          _clearConversation();
          error = 'บทสนทนาหมดอายุ กดส่งเพื่อเริ่มใหม่';
        } else {
          _msgs[_msgs.indexOf(pending)] = _Msg(true, 'ส่งข้อความไม่สำเร็จ');
          error = 'ตรวจข้อความไม่ได้ ลองส่งอีกครั้งนะคะ';
        }
        if (stepId == null) _retryDraft = text;
      } else {
        error = failure.message;
      }
      return ChatSubmission.failed;
    } finally {
      if (revision == _revision) {
        _phase = _ChatPhase.idle;
        notifyListeners();
      }
    }
  }
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController input = TextEditingController();
  final ScrollController scroll = ScrollController();
  Set<String> get deciding => s.deciding;
  Api get api => widget.app.api;
  ChatSession get s => widget.session;
  List<_Msg> get msgs => s._msgs;
  Set<String> get decided => s.decided;
  String? get conversationId => s.conversationId;

  @override
  void initState() {
    super.initState();
    _restoreRetryDraft();
    s.addListener(_sessionChanged);
    if (s.started) _scrollDown();
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
    _restoreRetryDraft();
    setState(() {});
    _scrollDown();
  }

  void _restoreRetryDraft() {
    if (s._takeRetryDraft() case final draft? when input.text.isEmpty) {
      input.text = draft;
    }
  }

  Future<void> _send(String text, {String? stepId}) async {
    final draft = input.text;
    await s.submit(
      widget.app,
      text,
      confirmConsent: () => confirmChatConsent(context, widget.app),
      stepId: stepId,
      onDispatch: () {
        if (mounted && stepId == null && input.text == draft) input.clear();
      },
    );
  }

  Future<void> _decide(Map<String, dynamic> a, bool yes) async {
    final actionId = a['id'] as String;
    final session = s;
    final conversation = conversationId;
    final app = widget.app;
    if (conversation == null ||
        deciding.contains(actionId) ||
        decided.contains(actionId) ||
        session.actionErrors[actionId]?.retry == false) {
      return;
    }
    session._updateMessages(() {
      deciding.add(actionId);
      session.actionErrors.remove(actionId);
    });
    try {
      final response = await api.post(
        '/v1/ai/conversations/$conversation/actions/$actionId',
        {'decision': yes ? 'confirm' : 'reject'},
      );
      if (session.conversationId != conversation) return;
      session._updateMessages(() => session.decided.add(actionId));
      final task = response['result'];
      if (response['status'] == 'done') app.bump();
      if (response['status'] == 'done' &&
          a['tool'] == 'create_task' &&
          task is Map &&
          task['id'] is String) {
        final steps = task['steps'] as List? ?? const [];
        final next = task['doneCount'] as int? ?? 0;
        final summary = [
          'บันทึกในแผนของฉันแล้ว',
          '${task['title']}',
          if (next >= 0 && next < steps.length) 'ขั้นต่อไป: ${steps[next]}',
        ].join('\n');
        session._updateMessages(
          () => session._msgs.add(
            _Msg(
              false,
              summary,
              status: 'saved',
              planLinks: [
                (taskId: task['id'] as String, label: 'ดูแผนของฉัน ›'),
              ],
            ),
          ),
        );
      } else if (mounted) {
        toast(
          context,
          yes ? 'ทำแล้ว: ${a['label']}' : 'ยกเลิกแล้ว ไม่ได้เปลี่ยนอะไร',
        );
      }
    } on ApiException catch (e) {
      if (session.conversationId != conversation) return;
      final jobLinked = session._msgs.any(
        (message) =>
            message.opportunities.any((link) => link.actionId == actionId),
      );
      if (jobLinked && (e.status == 409 || e.status == 404)) {
        session._updateMessages(() {
          session.actionErrors[actionId] = (message: e.message, retry: false);
        });
      } else if (jobLinked && (e.isNetwork || e.status >= 500)) {
        session._updateMessages(() {
          session.actionErrors[actionId] = (
            message: 'ยังไม่ทราบผล ลองยืนยันอีกครั้งได้ ระบบจะไม่บันทึกซ้ำ',
            retry: true,
          );
        });
      } else if (mounted) {
        toast(context, e.message);
      }
    } finally {
      if (session.conversationId == conversation) {
        session._updateMessages(() => session.deciding.remove(actionId));
      }
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskScreen(app: widget.app, taskId: taskId),
      ),
    );
  }

  Widget _opportunityRow(_OpportunityLink link, Map<String, dynamic>? action) {
    final source = link.source;
    final saveId = action?['id'];
    final actionError = s.actionErrors[saveId];
    final sourceBlocked =
        source == null || s.unavailableSources.contains(source);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(link.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            [
              if (link.data['workMode'] == 'remote')
                'ทำจากบ้าน'
              else if (link.data['district'] case final String district)
                'เขต$district',
              link.sourceLabel,
            ].join(' · '),
            style: const TextStyle(color: mutedInk, fontSize: 13),
          ),
          if (link.data['money'] is Map) Text(oppMoney(link.data)),
          if (actionError != null) Text(actionError.message),
          Wrap(
            spacing: 4,
            children: [
              if (source != null || link.data['sourceStatus'] == 'unavailable')
                TextButton(
                  onPressed: sourceBlocked
                      ? null
                      : () => _openSource(link, source),
                  child: Text(
                    sourceBlocked ? 'ต้นทางยังเปิดไม่ได้' : 'ดูต้นทาง',
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        OppScreen(app: widget.app, opportunityId: link.id),
                  ),
                ),
                child: const Text('ดูรายละเอียด'),
              ),
              if (link.savedTaskId case final String taskId)
                TextButton(
                  onPressed: () => _openTask(taskId),
                  child: const Text('บันทึกไว้แล้ว · ดูแผน ›'),
                )
              else if (action != null &&
                  saveId is String &&
                  !decided.contains(saveId))
                FilledButton(
                  onPressed:
                      deciding.contains(saveId) || actionError?.retry == false
                      ? null
                      : () => _decide(action, true),
                  child: Text(
                    actionError?.retry == true
                        ? 'ลองยืนยันอีกครั้ง'
                        : 'บันทึกเข้าแผน',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final displayedStepId = s.stepId;
    final sending = s.sending;
    return Scaffold(
      body: Column(
        children: [
          BrandHeader(
            child: Row(
              children: [
                if (ModalRoute.of(context)?.canPop == true)
                  const BackButton(color: Colors.white),
                Expanded(
                  child: Text(
                    widget.title ?? 'คุยกับ AI',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (s.started)
                  TextButton.icon(
                    onPressed: sending || deciding.isNotEmpty
                        ? null
                        : () {
                            s.reset(keepApproval: true);
                            input.clear();
                          },
                    style: TextButton.styleFrom(backgroundColor: Colors.white),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('เริ่มใหม่'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length + 2,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      widget.app.demo ? 'DEMO · ใช้ข้อมูลจำลองเพื่อสาธิต' : 'ผลเป็นการประเมินเบื้องต้น โปรดตรวจสอบสิทธิ์กับหน่วยงาน',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: mutedInk, fontSize: 13),
                    ),
                  );
                }
                if (i <= msgs.length) return _bubble(msgs[i - 1]);
                final error = s.error;
                if (error != null || !s.started) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Semantics(
                        liveRegion: error != null,
                        child: Text(
                          error ??
                              'ถามเรื่องสิทธิ์ เอกสาร หรือรายได้ที่เหมาะกับคุณ',
                          style: error == null
                              ? null
                              : TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                        ),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          if (s._phase == _ChatPhase.working)
            const LinearProgressIndicator(minHeight: 2),
          if (s.quick.isNotEmpty && s.started)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (displayedStepId != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          'คำถามข้อ ${s.questionNumber}',
                          style: const TextStyle(color: brandDark),
                        ),
                      ),
                    for (final q in s.quick)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          backgroundColor: blueTint,
                          label: Text(q),
                          onPressed: sending
                              ? null
                              : () => _send(q, stepId: displayedStepId),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: ChatComposer(
              controller: input,
              hint: 'พิมพ์ตอบ หรือถามเรื่องเงิน',
              busy: sending,
              onSend: _send,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final bg = m.mine ? brandDark : Colors.white;
    final actionsById = {for (final action in m.actions) action['id']: action};
    final rowActionIds = {for (final link in m.opportunities) link.actionId};
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: m.mine ? null : Border.all(color: cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!m.mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  _who(m),
                  style: const TextStyle(
                    fontSize: 12,
                    color: mutedInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Text(
              m.text,
              style: TextStyle(
                color: m.mine ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
            ),
            for (final plan in m.planLinks)
              TextButton(
                onPressed: () => _openTask(plan.taskId),
                child: Text(plan.label),
              ),
            for (final link in m.opportunities)
              _opportunityRow(link, actionsById[link.actionId]),
            for (final a in m.actions.where(
              (a) => !rowActionIds.contains(a['id']),
            ))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: decided.contains(a['id'])
                    ? const Text(
                        '✓ ตัดสินใจแล้ว',
                        style: TextStyle(fontSize: 12),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '⚡ ${a['label']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Wrap(
                            spacing: 6,
                            children: [
                              FilledButton(
                                onPressed: deciding.contains(a['id'])
                                    ? null
                                    : () => _decide(a, true),
                                child: const Text('ยืนยัน'),
                              ),
                              OutlinedButton(
                                onPressed: deciding.contains(a['id'])
                                    ? null
                                    : () => _decide(a, false),
                                child: const Text('ไม่ใช่'),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
