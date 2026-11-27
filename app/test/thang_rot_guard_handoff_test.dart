import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/chat.dart';
import 'package:money_anywhere/common.dart';

class _GuardApi extends Api {
  final messages = <Map<String, dynamic>>[];
  final response = Completer<Map<String, dynamic>>();

  @override
  Future<void> consent({required bool ai}) async => expect(ai, isTrue);

  @override
  Future<Map<String, dynamic>> post(
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) async {
    if (path == '/v1/ai/conversations') {
      return {
        'conversationId': 'guard-demo',
        'greeting': 'ต้องการ 5,000 บาทเป็นเงินก้อนหรือรายเดือน?',
        'step': {'id': 'period-a', 'question': 'ต้องการเงินก้อนหรือรายเดือน?'},
        'quickReplies': ['เงินก้อน', 'รายเดือน'],
      };
    }
    expect(path, '/v1/ai/conversations/guard-demo/messages');
    messages.add(Map<String, dynamic>.from(body! as Map));
    return response.future;
  }
}

Future<_GuardApi> _open(WidgetTester tester) async {
  final api = _GuardApi();
  addTearDown(api.close);
  await tester.pumpWidget(
    MaterialApp(
      home: ChatScreen(app: AppState(api), session: ChatSession()),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('UI-01 quick reply identifies the question shown to the person', (
    tester,
  ) async {
    final api = await _open(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'รายเดือน'));
    api.response.complete({
      'reply': 'รับเป้ารายเดือนแล้ว',
      'aiStatus': 'guarded',
    });
    await tester.pumpAndSettle();
    expect(api.messages.single['text'], 'รายเดือน');
    expect(api.messages.single['stepId'], 'period-a');
    expect(find.text('รับเป้ารายเดือนแล้ว'), findsOneWidget);
  });

  testWidgets(
    'UI-02 clarification stays accessible without an off-topic badge',
    (tester) async {
      final api = await _open(tester);
      await tester.enterText(find.byType(TextField), 'ไม่รู้จะเริ่มยังไง');
      await tester.tap(find.byIcon(Icons.send));
      api.response.complete({
        'reply': 'อยากเริ่มจากเช็กสิทธิหรือหาเงินเพิ่ม?',
        'guard': {'kind': 'unclear'},
        'aiStatus': 'guarded',
        'quickReplies': ['เช็กสิทธิ', 'หาเงินเพิ่ม'],
      });
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, 'หาเงินเพิ่ม'), findsOneWidget);
      expect(find.textContaining('นอกขอบเขต'), findsNothing);
      expect(find.textContaining('นอกเรื่อง'), findsNothing);
    },
  );

  testWidgets(
    'UI-03 secret stays hidden while pending, after response and on reopen',
    (tester) async {
      final api = await _open(tester);
      final screen = tester.widget<ChatScreen>(find.byType(ChatScreen));
      const secret = 'OTP 000123';
      await tester.enterText(find.byType(TextField), secret);
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      final visibleWhilePending = find
          .textContaining('000123')
          .evaluate()
          .isNotEmpty;
      api.response.complete({
        'reply': 'เก็บรหัสไว้กับตัวเองนะคะ',
        'guard': {'kind': 'sensitive'},
        'aiStatus': 'guarded',
      });
      await tester.pumpAndSettle();
      final visibleAfterReply = find
          .textContaining('000123')
          .evaluate()
          .isNotEmpty;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(app: screen.app, session: screen.session),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        {
          'pending': visibleWhilePending,
          'afterReply': visibleAfterReply,
          'onReopen': find.textContaining('000123').evaluate().isNotEmpty,
        },
        {'pending': false, 'afterReply': false, 'onReopen': false},
      );
    },
  );
}
