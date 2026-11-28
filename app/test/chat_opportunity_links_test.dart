import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/chat.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/opp_screen.dart';
import 'package:money_anywhere/task_screen.dart';

class _ChatApi extends Api {
  _ChatApi(this.turn);

  final Map<String, dynamic> turn;
  final decisions = <String>[];
  final reads = <String>[];
  final failures = <ApiException>[];

  static const task = {
    'id': 'task-demo',
    'title': 'งานธุรการ',
    'status': 'active',
    'doneCount': 0,
    'steps': ['เปิดประกาศ'],
  };

  @override
  Future<Map<String, bool>?> currentPurposes() async => {'ai': true};

  @override
  Future<void> consent({required bool ai}) async => expect(ai, isTrue);

  @override
  Future<Map<String, dynamic>> post(
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) async {
    if (path == '/v1/ai/conversations') {
      return {'conversationId': 'chat-1', 'greeting': 'พร้อมค้นงาน'};
    }
    if (path.endsWith('/messages')) return turn;
    expect((body as Map)['decision'], 'confirm');
    decisions.add(path);
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return {'status': 'done', 'result': task};
  }

  @override
  Future<Map<String, dynamic>> get(String path) async {
    reads.add(path);
    if (path == '/v1/tasks/task-demo') return task;
    if (path == '/v1/tasks') return {'items': []};
    return {'id': 'job-1', 'title': 'งานธุรการ', 'category': 'job_part'};
  }
}

const _action = {'id': 'a-1', 'tool': 'create_task', 'label': 'ข้อเสนอเดิม'};
const _job = {
  'opportunityId': 'job-1',
  'title': 'งานธุรการ',
  'dataStatus': 'mock',
  'district': 'บางนา',
  'actionId': 'a-1',
  'sourceUrl': 'https://example.com/job-1',
  'sourceStatus': 'ok',
};

Future<void> _open(WidgetTester tester, _ChatApi api) async {
  addTearDown(api.close);
  await tester.binding.setSurfaceSize(const Size(480, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ChatScreen(app: AppState(api), session: ChatSession()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'หางานบางนา');
  await tester.pump();
  await tester.tap(find.byTooltip('ส่งข้อความ'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens the source and detail from the matching result', (
    tester,
  ) async {
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final opened = <String>[];
    messenger.setMockMethodCallHandler(launcher, (call) async {
      opened.add((call.arguments as Map)['url'] as String);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
    final api = _ChatApi({
      'reply': 'พบรายการ',
      'opportunityLinks': [
        _job,
        {
          'opportunityId': 'job-2',
          'title': 'ประกาศตรวจแล้ว',
          'dataStatus': 'curated',
          'checkedAt': '2026-11-28T00:00:00Z',
          'sourceUrl': 'javascript:blocked',
        },
      ],
    });
    await _open(tester, api);
    expect(find.textContaining('DEMO / MOCK'), findsOneWidget);
    expect(find.text('ตรวจแล้ว 2026-11-28'), findsOneWidget);
    expect(find.text('ดูต้นทาง'), findsOneWidget);
    await tester.tap(find.text('ดูต้นทาง'));
    await tester.pumpAndSettle();
    expect(opened, ['https://example.com/job-1']);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.text('กลับมาแล้ว 👋'), findsNothing);
    await tester.tap(find.text('ดูรายละเอียด').first);
    await tester.pumpAndSettle();
    expect(tester.widget<OppScreen>(find.byType(OppScreen)).id, 'job-1');
  });

  testWidgets('confirms the row action and opens that plan', (tester) async {
    final api = _ChatApi({
      'reply': 'พบรายการ',
      'opportunityLinks': [_job],
      'pendingActions': [_action],
      'aiStatus': 'ok',
    });
    await _open(tester, api);
    expect(find.text('⚡ ข้อเสนอเดิม'), findsNothing);
    await tester.tap(find.text('บันทึกเข้าแผน'));
    await tester.pumpAndSettle();
    expect(api.decisions.single, '/v1/ai/conversations/chat-1/actions/a-1');
    expect(find.textContaining('บันทึกในแผนของฉันแล้ว'), findsOneWidget);
    await tester.tap(find.text('ดูแผนของฉัน ›'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TaskScreen>(find.byType(TaskScreen)).taskId,
      'task-demo',
    );
    expect(api.reads, contains('/v1/tasks/task-demo'));
  });

  testWidgets('old response keeps the original actions', (tester) async {
    await _open(
      tester,
      _ChatApi({
        'reply': 'เคสเดิม',
        'pendingActions': [_action],
      }),
    );
    expect(find.text('เคสเดิม'), findsOneWidget);
    expect(find.text('ยืนยัน'), findsOneWidget);
    expect(find.text('บันทึกเข้าแผน'), findsNothing);
  });

  testWidgets('fallback row retries the same action after a lost response', (
    tester,
  ) async {
    final api = _ChatApi({
      'reply': 'พบรายการ',
      'opportunityLinks': [_job],
      'pendingActions': [_action],
      'guard': {'kind': 'sensitive'},
      'maskedText': '[ซ่อน] หางานบางนา',
      'aiStatus': 'fallback_rules',
    })..failures.add(ApiException(0, 'NETWORK', 'socket closed'));
    await _open(tester, api);
    expect(find.textContaining('ตอบตามเกณฑ์เมื่อ AI ไม่พร้อม'), findsOneWidget);
    expect(find.text('[ซ่อน] หางานบางนา'), findsOneWidget);
    await tester.tap(find.text('บันทึกเข้าแผน'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ยังไม่ทราบผล'), findsOneWidget);
    await tester.tap(find.text('ลองยืนยันอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(
      api.decisions,
      List.filled(2, '/v1/ai/conversations/chat-1/actions/a-1'),
    );
    expect(find.textContaining('บันทึกในแผนของฉันแล้ว'), findsOneWidget);
  });

  testWidgets('a closed listing disables just its save action', (tester) async {
    final api = _ChatApi({
      'reply': 'พบรายการ',
      'opportunityLinks': [_job],
      'pendingActions': [_action],
    })..failures.add(ApiException(409, 'CONFLICT', 'ประกาศนี้ปิดรับแล้ว'));
    await _open(tester, api);
    await tester.tap(find.text('บันทึกเข้าแผน'));
    await tester.pumpAndSettle();
    expect(find.text('ประกาศนี้ปิดรับแล้ว'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'บันทึกเข้าแผน'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('ดูรายละเอียด'), findsOneWidget);
    expect(api.decisions, hasLength(1));
  });
}
