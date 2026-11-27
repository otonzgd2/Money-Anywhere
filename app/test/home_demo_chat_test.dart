import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/home_tab.dart';
import 'package:money_anywhere/main.dart';

class _ChatApi extends Api {
  _ChatApi({this.demoClient, this.taxClient});
  static const _task = {
    'id': 't-demo',
    'title': 'เงินทดแทนกรณีว่างงาน',
    'steps': ['เตรียมเอกสาร', 'ขึ้นทะเบียนว่างงาน'],
    'doneCount': 1,
    'status': 'active',
  };
  final _ChatApi? demoClient, taxClient;
  final demoFacts = <String, Object?>{'ageBand': '60-69', 'ss33': true, 'disabilityCard': true, 'taxWithheld': true};
  final previewFacts = <Map<String, Object?>>[];
  bool seeded = false;
  bool saved = false;
  int starts = 0;

  @override
  Api forDemo(String name) {
    if (name == 'dmytax') return taxClient!;
    expect(name, 'gov-prefill-chat');
    return demoClient!;
  }

  @override
  Future<Map<String, dynamic>> get(String path) async {
    switch (path) {
      case '/v1/me/facts':
        return seeded ? demoFacts : {};
      case '/v1/me/consents':
        return {'current': null};
      case '/v1/me/memory':
        return {'items': []};
      case '/v1/me/settings':
      case '/v1/app-config':
        return {};
      case '/v1/me/gov-link':
        return {'status': 'not_connected'};
      case '/v1/me/profile':
        if (!seeded) throw ApiException(404, 'NOT_FOUND', 'No profile');
        return {'displayName': 'สมศักดิ์ สมมติ'};
      case '/v1/demo/personas/gov-prefill':
        return {
          'dataStatus': 'mock',
          'profile': {'displayName': 'สมศักดิ์ สมมติ'},
          'identity': {'dataStatus': 'mock'},
          'sources': [],
        };
      case '/v1/tasks/t-demo':
        expect(saved, isTrue);
        return _task;
      case '/v1/tasks':
        return {'items': [if (saved) _task]};
      default:
        if (path.startsWith('/v1/opportunities?')) return {'items': []};
        throw StateError('Unexpected GET $path');
    }
  }

  @override
  Future<void> consent({required bool ai}) async => expect(ai, isTrue);

  @override
  Future<Map<String, dynamic>> post(
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) async {
    if (path == '/v1/demo/personas/gov-prefill') {
      expect(demoClient, isNull);
      expect(seeded, isFalse);
      seeded = true;
      return {'dataStatus': 'mock'};
    }
    if (path == '/v1/money/preview') {
      final facts = Map<String, Object?>.from((body as Map)['facts'] as Map);
      previewFacts.add(facts);
      final missing = !facts.containsKey('ageBand')
          ? (field: 'ageBand', question: 'คุณอายุเท่าไหร่')
          : !facts.containsKey('taxWithheld')
          ? (field: 'taxWithheld', question: 'ปีนี้ถูกหักภาษี ณ ที่จ่ายไหม')
          : null;
      return {'items': [
        if (missing != null)
          {'id': 'old_age', 'status': 'need', 'nextQuestion': {'fact': missing.field, 'question': missing.question}}
        else
          {'id': 'old_age', 'title': 'เบี้ยยังชีพผู้สูงอายุ', 'status': 'likely', 'amount': {'value': 600, 'unit': 'บาท/เดือน'}},
      ]};
    }
    if (path == '/v1/ai/conversations/conv-test/messages') {
      if ((body as Map)['text'] == 'เงินฉันอยู่ไหน') {
        expect(saved, isTrue);
        return {
          'reply': 'มีแผนเดิมที่ยังไม่ได้รับเงิน',
          'planLinks': [{'taskId': _task['id'], 'title': _task['title']}],
        };
      }
      return {
        'reply': 'เตรียมเอกสารและยื่นกับกรมการจัดหางาน',
        'pendingActions': [
          {'id': 'pa-test', 'tool': 'create_task', 'label': 'บันทึกแผนเงินว่างงาน'},
        ],
        'quickReplies': ['เงินฉันอยู่ไหน'],
      };
    }
    if (path == '/v1/ai/conversations/conv-test/actions/pa-test') {
      saved = (body as Map)['decision'] == 'confirm';
      return saved ? {'status': 'done', 'result': _task} : {'status': 'rejected'};
    }
    expect(path, '/v1/ai/conversations');
    expect(body, {'mode': 'guided'});
    starts++;
    return {
      'conversationId': 'conv-test',
      'greeting': seeded ? 'ถูกรวมข้อมูล DEMO แล้ว' : 'คุณอายุเท่าไหร่',
      if (seeded) 'quickReplies': ['ดูวิธีรับเงินว่างงาน'],
    };
  }
}

void main() {
  testWidgets(
    'starts the guided demo chat with its own facts and keeps the personal entry',
    (tester) async {
      final demo = _ChatApi();
      final personal = _ChatApi(demoClient: demo);
      addTearDown(personal.close);
      addTearDown(demo.close);
      await tester.pumpWidget(
        MaterialApp(home: HomeTab(app: AppState(personal))),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('เริ่มคุยเลย ›'));
      await tester.pumpAndSettle();
      expect(find.text('ถูกรวมข้อมูล DEMO แล้ว'), findsOneWidget);
      expect(find.text('คุณอายุเท่าไหร่'), findsNothing);
      expect(personal.starts, 0);
      expect(demo.starts, 1);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('เริ่มคุยด้วยข้อมูลของฉัน'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('เริ่มคุยด้วยข้อมูลของฉัน'));
      await tester.pumpAndSettle();
      expect(find.text('คุณอายุเท่าไหร่'), findsOneWidget);
      expect(personal.starts, 1);
      expect(personal.seeded, isFalse);
    },
  );

  testWidgets('manual check reuses saved demo facts, then asks only missing facts in the selected profile', (tester) async {
    final demo = _ChatApi();
    final personal = _ChatApi(demoClient: demo);
    addTearDown(personal.close);
    addTearDown(demo.close);
    await tester.pumpWidget(MaterialApp(home: HomeTab(app: AppState(personal))));
    await tester.pumpAndSettle();

    Future<void> openCheck(String label) async {
      final action = find.text(label);
      await tester.scrollUntilVisible(action.hitTestable(), 120, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(action.hitTestable());
      await tester.pumpAndSettle();
    }

    await openCheck('เช็คเงินที่ควรได้ เอง');
    expect(find.text('เช็คเงินที่ควรได้ · DEMO'), findsOneWidget);
    expect(find.textContaining('เบี้ยยังชีพผู้สูงอายุ'), findsOneWidget);
    expect(demo.previewFacts.single, demo.demoFacts);
    expect(personal.previewFacts, isEmpty);
    expect(demo.starts, 0);

    await tester.pageBack();
    await tester.pumpAndSettle();
    demo.demoFacts.remove('taxWithheld');
    await openCheck('เช็คเงินที่ควรได้ เอง');
    expect(find.text('ปีนี้ถูกหักภาษี ณ ที่จ่ายไหม'), findsOneWidget);
    expect(find.text('คุณอายุเท่าไหร่'), findsNothing);
    expect(demo.previewFacts.last, demo.demoFacts);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await openCheck('เช็คด้วยข้อมูลของฉัน');
    expect(find.text('เช็คเงินที่ควรได้'), findsOneWidget);
    expect(find.text('คุณอายุเท่าไหร่'), findsOneWidget);
    expect(personal.previewFacts.single, isEmpty);
    expect(personal.seeded, isFalse);
  });

  for (final confirm in [true, false]) {
    testWidgets(
      'demo chat opens its saved plan only after a successful confirmation ($confirm)',
      (tester) async {
        final demo = _ChatApi();
        final tax = _ChatApi();
        final personal = _ChatApi(demoClient: demo, taxClient: tax);
        addTearDown(personal.close);
        addTearDown(demo.close);
        addTearDown(tax.close);
        await tester.pumpWidget(MoneyAnywhereApp(app: AppState(personal)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('เริ่มคุยเลย ›'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ดูวิธีรับเงินว่างงาน'));
        await tester.pumpAndSettle();
        expect(find.text('ดูแผนของฉัน ›'), findsNothing);

        await tester.tap(find.text(confirm ? 'ยืนยัน' : 'ไม่ใช่'));
        await tester.pumpAndSettle();
        expect(demo.saved, confirm);
        expect(personal.saved, isFalse);
        if (!confirm) {
          expect(find.text('ดูแผนของฉัน ›'), findsNothing);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.text('แผนของฉัน'));
          await tester.pumpAndSettle();
          expect(find.text('ยังไม่มีแผน'), findsOneWidget);
          return;
        }

        expect(find.textContaining('ขั้นต่อไป: ขึ้นทะเบียนว่างงาน'), findsOneWidget);
        await tester.tap(find.text('ดูแผนของฉัน ›'));
        await tester.pumpAndSettle();
        expect(find.text('แผนของฉัน · DEMO'), findsOneWidget);
        expect(find.text('เงินทดแทนกรณีว่างงาน'), findsOneWidget);
        expect(find.text('ทำแล้ว 1 จาก 2 ขั้น'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('เงินฉันอยู่ไหน'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('เปิดแผน เงินทดแทนกรณีว่างงาน'));
        await tester.pumpAndSettle();
        expect(find.text('แผนของฉัน · DEMO'), findsOneWidget);
        expect(find.text('ทำแล้ว 1 จาก 2 ขั้น'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('แผนของฉัน'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO · โปรไฟล์เชื่อม 4 แหล่ง'), findsOneWidget);
        expect(find.text('ยังไม่มีแผน'), findsNothing);
        await tester.tap(find.text('เงินทดแทนกรณีว่างงาน'));
        await tester.pumpAndSettle();
        expect(find.text('แผนของฉัน · DEMO'), findsOneWidget);
        expect(find.text('ทำแล้ว 1 จาก 2 ขั้น'), findsOneWidget);
      },
    );
  }
}
