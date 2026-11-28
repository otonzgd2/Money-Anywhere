import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/main.dart';

class _OfflineApi extends Api {
  @override
  Future<Map<String, dynamic>> get(String path) async => throw ApiException(503, 'TEST', 'offline');
}

void main() {
  testWidgets('draws a startup screen while local settings are loading', (tester) async {
    final startup = Completer<AppState>();
    final api = _OfflineApi();
    addTearDown(api.close);
    await tester.pumpWidget(MoneyAnywhereStartup(initialize: () => startup.future));

    expect(find.byType(ThangRotSplash), findsOneWidget);
    expect(find.bySemanticsLabel('ทางรอด'), findsOneWidget);

    startup.complete(AppState(api));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจโหมดแอปไม่ได้'), findsOneWidget);
  });

  testWidgets('4 tabs and the new-person home (ui-states.md §1, §3)', (tester) async {
    // Phone-sized screen (1080 x 2340 at 3x) so the whole home fits like on the Demo phone.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = _OfflineApi();
    addTearDown(api.close);
    await tester.pumpWidget(MoneyAnywhereApp(app: AppState(api)));
    await tester.pumpAndSettle();

    for (final label in ['หน้าแรก', 'โอกาส', 'แผนของฉัน', 'ฉัน']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('ฉัน tab shows delete-all and large text', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = _OfflineApi();
    addTearDown(api.close);
    await tester.pumpWidget(MoneyAnywhereApp(app: AppState(api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ฉัน').last);
    await tester.pumpAndSettle();
    expect(find.text('ลบข้อมูลทั้งหมด'), findsOneWidget);
    expect(find.text('ตัวอักษรใหญ่'), findsOneWidget);
  });
}
