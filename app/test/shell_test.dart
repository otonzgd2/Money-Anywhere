import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/main.dart';

// Widget tests run without a server (every request fails), which is the "new person" home.
// Real I/O only completes inside runAsync, so let it settle before checking.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
  await tester.pump();
}

void main() {
  testWidgets('4 tabs and the new-person home (ui-states.md §1, §3)', (tester) async {
    // Phone-sized screen (1080 x 2340 at 3x) so the whole home fits like on the Demo phone.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MoneyAnywhereApp(app: AppState(Api(baseUrl: 'http://127.0.0.1:9'))));
    await settle(tester);

    for (final label in ['หน้าแรก', 'โอกาส', 'แผนของฉัน', 'ฉัน']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('ให้ AI หาเงินให้ฉัน'), findsOneWidget);
    expect(find.text('เช็คเงินที่ควรได้ เอง'), findsOneWidget);
  });

  testWidgets('ฉัน tab shows delete-all and large text', (tester) async {
    await tester.pumpWidget(MoneyAnywhereApp(app: AppState(Api(baseUrl: 'http://127.0.0.1:9'))));
    await settle(tester);
    await tester.tap(find.text('ฉัน').last);
    await settle(tester);
    expect(find.text('ลบข้อมูลทั้งหมด'), findsOneWidget);
    expect(find.text('ตัวอักษรใหญ่'), findsOneWidget);
  });
}
