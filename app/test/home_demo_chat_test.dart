import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/home_tab.dart';
import 'package:money_anywhere/main.dart';

class _ChatApi extends Api {
  _ChatApi({this.demoClient, this.taxClient, this.sourcesClient});
  static const _task = {
    'id': 't-demo',
    'title': 'เงินทดแทนกรณีว่างงาน',
    'steps': ['เตรียมเอกสาร', 'ขึ้นทะเบียนว่างงาน'],
    'doneCount': 1,
    'status': 'active',
  };
  final _ChatApi? demoClient, taxClient, sourcesClient;
  final demoFacts = <String, Object?>{
    'ageBand': '60-69',
    'ss33': true,
    'disabilityCard': true,
    'taxWithheld': true,
  };
  final previewFacts = <Map<String, Object?>>[];
  bool seeded = false;
  bool saved = false;
  bool failNextMessage = false;
  int starts = 0;
  final sentTexts = <String>[];
  static const greeting = 'อยากเริ่มจากเช็กสิทธิรับเงิน หรือวางแผนหาเงินเพิ่ม?';
  bool consentedAi = false;

  @override
  Api forDemo(String name) {
    if (name == 'dmytax') return taxClient!;
    if (name == 'gov-prefill-selection') return sourcesClient!;
    expect(name, 'gov-prefill-chat');
    return demoClient!;
  }

  @override
  Future<Map<String, dynamic>> get(String path) async {
    switch (path) {
      case '/v1/me/facts':
        return seeded ? demoFacts : {};
      case '/v1/me/consents':
        return {
          'current': consentedAi
              ? {
                  'purposes': {'core': true, 'ai': true},
                }
              : null,
        };
      case '/v1/me/memory':
        return {'items': []};
      case '/v1/me/settings':
      case '/v1/app-config':
        return {
          'mode': 'demo',
          'featureFlags': {'demo': true},
        };
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
        return {
          'items': [if (saved) _task],
        };
      case '/v1/money/unemployment':
        return {'title': 'เงินทดแทนกรณีว่างงาน', 'status': 'need'};
      default:
        if (path.startsWith('/v1/opportunities?')) return {'items': []};
        throw StateError('Unexpected GET $path');
    }
  }

  @override
  Future<void> consent({required bool ai}) async {
    expect(ai, isTrue);
    consentedAi = true;
  }

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
      return {
        'items': [
          if (missing != null)
            {
              'id': 'old_age',
              'status': 'need',
              'nextQuestion': {
                'fact': missing.field,
                'question': missing.question,
              },
            }
          else
            {
              'id': 'old_age',
              'title': 'เบี้ยยังชีพผู้สูงอายุ',
              'status': 'likely',
              'amount': {'value': 600, 'unit': 'บาท/เดือน'},
            },
        ],
      };
    }
    if (path == '/v1/ai/conversations/conv-test/messages') {
      final message = (body as Map)['text'] as String;
      sentTexts.add(message);
      if (failNextMessage) {
        failNextMessage = false;
        throw ApiException(503, 'UNAVAILABLE', 'ส่งข้อความไม่สำเร็จ');
      }
      if (message.trim() == 'ขอข้อมูลเบื้องต้น') {
        return {
          'reply': 'ลองเลือกเรื่องที่อยากตรวจ',
          'step': {'id': 'intent-test', 'fact': 'intent'},
          'quickReplies': [
            if (seeded) 'ดูวิธีรับเงินว่างงาน' else 'เช็กสิทธิเบี้ยผู้สูงอายุ',
          ],
        };
      }
      if (body['text'] == 'เงินฉันอยู่ไหน') {
        expect(saved, isTrue);
        return {
          'reply': 'มีแผนเดิมที่ยังไม่ได้รับเงิน',
          'planLinks': [
            {'taskId': _task['id'], 'title': _task['title']},
          ],
        };
      }
      if (body['text'] == 'เช็กสิทธิเบี้ยผู้สูงอายุ') {
        expect(body['stepId'], 'intent-test');
        return {
          'reply': 'คุณอายุเท่าไหร่',
          'step': {'id': 'age-test', 'fact': 'ageBand'},
          'quickReplies': ['60-69'],
        };
      }
      if (body['text'] == '60-69') {
        expect(body['stepId'], 'age-test');
        return {'reply': 'คุณมีสัญชาติไทยไหม'};
      }
      return {
        'reply': 'เตรียมเอกสารและยื่นกับกรมการจัดหางาน',
        'pendingActions': [
          {
            'id': 'pa-test',
            'tool': 'create_task',
            'label': 'บันทึกแผนเงินว่างงาน',
          },
        ],
        'quickReplies': ['เงินฉันอยู่ไหน'],
      };
    }
    if (path == '/v1/ai/conversations/conv-test/actions/pa-test') {
      saved = (body as Map)['decision'] == 'confirm';
      return saved
          ? {'status': 'done', 'result': _task}
          : {'status': 'rejected'};
    }
    expect(path, '/v1/ai/conversations');
    expect(body, {'mode': 'guided'});
    starts++;
    return {
      'conversationId': 'conv-test',
      'greeting': greeting,
      'step': {'id': 'intent-test', 'fact': 'intent'},
      'quickReplies': [
        if (seeded) 'ดูวิธีรับเงินว่างงาน' else 'เช็กสิทธิเบี้ยผู้สูงอายุ',
      ],
    };
  }
}

Future<void> requestSend(WidgetTester tester, [String? draft]) async {
  final composer = find.byType(TextField);
  await tester.ensureVisible(composer);
  if (draft != null) await tester.enterText(composer, draft);
  await tester.pump();
  final send = find.byTooltip('ส่งข้อความ');
  await tester.ensureVisible(send);
  await tester.pumpAndSettle();
  await tester.tap(send);
  await tester.pumpAndSettle();
}

Future<void> approveChat(
  WidgetTester tester, [
  String draft = 'ขอข้อมูลเบื้องต้น',
]) async {
  await requestSend(tester, draft);
  expect(find.text('ก่อนส่งข้อความถึง AI'), findsOneWidget);
  await tester.tap(find.text('ยอมรับและส่ง'));
  await tester.pumpAndSettle();
}

void main() {
  for (final fromHome in [true, false]) {
    testWidgets(
      '${fromHome ? 'Home DEMO' : 'Chat tab'} keeps the draft on cancel and sends it exactly once after consent at 320×640',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final demo = _ChatApi();
        final personal = _ChatApi(demoClient: demo);
        final target = fromHome ? demo : personal;
        final other = fromHome ? personal : demo;
        addTearDown(demo.close);
        addTearDown(personal.close);
        final app = AppState(personal)..largeText.value = true;
        if (!fromHome) app.goTab(AppTab.chat);
        await tester.pumpWidget(MoneyAnywhereApp(app: app));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(TextField));
        expect(find.byTooltip('พิมพ์ด้วยเสียง'), findsOneWidget);
        expect(target.starts, 0);

        const draft = '  มีงานประจำแล้ว ต้องการงานเสริม  ';
        await requestSend(tester, draft);
        expect(find.text('ก่อนส่งข้อความถึง AI'), findsOneWidget);
        expect(target.starts, 0);
        expect(target.seeded, isFalse);
        await tester.tap(find.text('ยกเลิก'));
        await tester.pumpAndSettle();

        expect(app.tab.value, fromHome ? AppTab.home : AppTab.chat);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          draft,
        );
        expect(target.consentedAi, isFalse);
        expect(target.seeded, isFalse);
        expect(target.sentTexts, isEmpty);

        await requestSend(tester);
        final accept = find.text('ยอมรับและส่ง');
        await tester.tap(accept);
        await tester.tap(accept, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(app.tab.value, AppTab.chat);
        expect(target.consentedAi, isTrue);
        expect(target.starts, 1);
        expect(target.sentTexts, [draft]);
        expect(other.starts, 0);
        expect(other.sentTexts, isEmpty);
        expect(find.text('ก่อนส่งข้อความถึง AI'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Home send failure retains the first question in the active chat composer',
    (tester) async {
      final demo = _ChatApi()..failNextMessage = true;
      final personal = _ChatApi(demoClient: demo);
      addTearDown(demo.close);
      addTearDown(personal.close);
      final app = AppState(personal);
      await tester.pumpWidget(MoneyAnywhereApp(app: app));
      await tester.pumpAndSettle();

      const draft = 'หางานใกล้บ้าน';
      await approveChat(tester, draft);
      expect(app.tab.value, AppTab.chat);
      expect(demo.sentTexts, [draft]);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        draft,
      );
      await requestSend(tester);
      expect(find.text('ก่อนส่งข้อความถึง AI'), findsNothing);
      expect(demo.starts, 1);
      expect(demo.sentTexts, [draft, draft]);
    },
  );

  testWidgets(
    'Home microphone falls back to the editable composer at 320×640',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final demo = _ChatApi();
      final personal = _ChatApi(demoClient: demo);
      addTearDown(demo.close);
      addTearDown(personal.close);
      const channel = MethodChannel('money_anywhere/speech');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(MoneyAnywhereApp(app: AppState(personal)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('พิมพ์ด้วยเสียง'));
      await tester.tap(find.byTooltip('พิมพ์ด้วยเสียง'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เริ่มพูด'));
      await tester.pumpAndSettle();
      expect(
        find.text('ถอดเสียงบนอุปกรณ์นี้ไม่ได้ พิมพ์ข้อความต่อได้'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'หางานเสริม');
      expect(demo.starts, 0);
      expect(personal.starts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'starts the guided demo chat with its own facts and keeps the personal entry',
    (tester) async {
      final demo = _ChatApi();
      final personal = _ChatApi(demoClient: demo);
      addTearDown(personal.close);
      addTearDown(demo.close);
      await tester.pumpWidget(MoneyAnywhereApp(app: AppState(personal)));
      await tester.pumpAndSettle();

      await approveChat(tester);
      expect(
        find.text('อยากเริ่มจากเช็กสิทธิรับเงิน หรือวางแผนหาเงินเพิ่ม?'),
        findsOneWidget,
      );
      expect(find.text('คุณอายุเท่าไหร่'), findsNothing);
      expect(personal.starts, 0);
      expect(demo.starts, 1);

      await tester.tap(find.text('หน้าแรก'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('เริ่มคุยด้วยข้อมูลของฉัน'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('เริ่มคุยด้วยข้อมูลของฉัน'));
      await tester.pumpAndSettle();
      await approveChat(tester);
      expect(
        find.text('อยากเริ่มจากเช็กสิทธิรับเงิน หรือวางแผนหาเงินเพิ่ม?'),
        findsOneWidget,
      );
      expect(find.text('คุณอายุเท่าไหร่'), findsNothing);
      await tester.tap(
        find.widgetWithText(ActionChip, 'เช็กสิทธิเบี้ยผู้สูงอายุ'),
      );
      await tester.pumpAndSettle();
      expect(find.text('คุณอายุเท่าไหร่'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, '60-69'));
      await tester.pumpAndSettle();
      expect(find.text('คุณมีสัญชาติไทยไหม'), findsOneWidget);
      expect(personal.starts, 1);
      expect(personal.seeded, isFalse);
    },
  );

  testWidgets(
    'manual check reuses saved demo facts, then asks only missing facts in the selected profile',
    (tester) async {
      final demo = _ChatApi();
      final personal = _ChatApi(demoClient: demo);
      addTearDown(personal.close);
      addTearDown(demo.close);
      await tester.pumpWidget(
        MaterialApp(home: HomeTab(app: AppState(personal))),
      );
      await tester.pumpAndSettle();

      Future<void> openCheck(String label) async {
        final action = find.text(label);
        await tester.scrollUntilVisible(
          action.hitTestable(),
          120,
          scrollable: find.byType(Scrollable).first,
        );
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
    },
  );

  for (final confirm in [true, false]) {
    testWidgets(
      'demo chat opens its saved plan only after a successful confirmation ($confirm)',
      (tester) async {
        final demo = _ChatApi();
        final tax = _ChatApi();
        final sources = _ChatApi();
        final personal = _ChatApi(
          demoClient: demo,
          taxClient: tax,
          sourcesClient: sources,
        );
        addTearDown(personal.close);
        addTearDown(demo.close);
        addTearDown(tax.close);
        addTearDown(sources.close);
        await tester.pumpWidget(MoneyAnywhereApp(app: AppState(personal)));
        await tester.pumpAndSettle();
        await approveChat(tester, 'ดูวิธีรับเงินว่างงาน');
        expect(find.text('ดูแผนของฉัน ›'), findsNothing);

        await tester.tap(find.text(confirm ? 'ยืนยัน' : 'ไม่ใช่'));
        await tester.pumpAndSettle();
        expect(demo.saved, confirm);
        expect(personal.saved, isFalse);
        if (!confirm) {
          expect(find.text('ดูแผนของฉัน ›'), findsNothing);
          await tester.tap(find.text('แผนของฉัน'));
          await tester.pumpAndSettle();
          expect(find.text('ยังไม่มีแผน'), findsOneWidget);
          return;
        }

        expect(
          find.textContaining('ขั้นต่อไป: ขึ้นทะเบียนว่างงาน'),
          findsOneWidget,
        );
        await tester.tap(find.text('ดูแผนของฉัน ›'));
        await tester.pumpAndSettle();
        expect(find.text('รายละเอียดแผน'), findsOneWidget);
        expect(find.text('เงินทดแทนกรณีว่างงาน'), findsOneWidget);
        expect(find.text('ทำแล้ว 1 จาก 2 ขั้น'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('เงินฉันอยู่ไหน'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('เปิดแผน เงินทดแทนกรณีว่างงาน'));
        await tester.pumpAndSettle();
        expect(find.text('รายละเอียดแผน'), findsOneWidget);
        expect(find.text('ทำแล้ว 1 จาก 2 ขั้น'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('แผนของฉัน'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO · โปรไฟล์แหล่งข้อมูล'), findsOneWidget);
        expect(find.text('ยังไม่มีแผน'), findsNothing);
        await tester.tap(find.text('เงินทดแทนกรณีว่างงาน'));
        await tester.pumpAndSettle();
        expect(find.text('รายละเอียดแผน'), findsOneWidget);
        expect(find.text('ทำแล้ว 1 จาก 2 ขั้น'), findsOneWidget);
      },
    );
  }
}
