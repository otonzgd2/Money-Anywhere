import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/plans_tab.dart';
import 'package:money_anywhere/task_screen.dart';

Map<String, dynamic> plan(
  String id,
  String title, {
  String status = 'active',
  int done = 0,
  List<String> steps = const ['เตรียมเอกสาร', 'ติดต่อหน่วยงาน'],
  String? category,
  int? categoryId,
  String? moneyId,
}) => {
  'id': id,
  'title': title,
  'status': status,
  'doneCount': done,
  'steps': steps,
  'category': ?category,
  'categoryId': ?categoryId,
  'moneyId': ?moneyId,
};

class _PlanData {
  final plans = <String, List<Map<String, dynamic>>>{};
  final errors = <String, ApiException>{};
  final opened = <(String, String)>[];
  Completer<void>? firstLoad;
  int primaryLoads = 0;
}

class _PlanApi extends Api {
  _PlanApi(this.data, [this.profile = 'primary']);

  final _PlanData data;
  final String profile;

  @override
  Api forDemo(String name) => _PlanApi(data, name);

  Map<String, dynamic> _find(String id) =>
      data.plans[profile]!.singleWhere((task) => task['id'] == id);

  @override
  Future<Map<String, dynamic>> get(String path) async {
    if (path == '/v1/tasks') {
      if (profile == 'primary') {
        data.primaryLoads++;
        await data.firstLoad?.future;
      }
      if (data.errors[profile] case final failure?) throw failure;
      return {'items': data.plans[profile] ?? []};
    }
    if (path.startsWith('/v1/tasks/')) {
      final id = path.split('/').last;
      data.opened.add((profile, id));
      return _find(id);
    }
    throw ApiException(404, 'NOT_FOUND', 'ไม่พบต้นทาง');
  }

  @override
  Future<Map<String, dynamic>> taskEvent(
    String taskId,
    Map<String, Object?> event,
  ) async {
    final task = _find(taskId);
    if (event['type'] == 'complete_step') {
      task['doneCount'] = (task['doneCount'] as int) + 1;
    }
    return task;
  }
}

Future<AppState> _showPlans(
  WidgetTester tester,
  _PlanData data, {
  Size size = const Size(360, 1200),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _PlanApi(data);
  addTearDown(api.close);
  final app = AppState(api)..goTab(AppTab.plans);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: PlansTab(app: app),
    ),
  );
  return app;
}

void main() {
  testWidgets('AC-14 shows a title during load and a home action when empty', (
    tester,
  ) async {
    final data = _PlanData()..firstLoad = Completer<void>();
    final app = await _showPlans(tester, data);
    expect(find.text('แผนของฉัน'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('แผนที่บันทึก'), findsNothing);
    expect(find.text('ยังไม่มีแผน'), findsNothing);

    data.firstLoad!.complete();
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีแผน'), findsOneWidget);
    expect(find.textContaining('แผนที่บันทึก'), findsNothing);
    expect(find.textContaining('โหลดตัวอย่าง'), findsNothing);
    await tester.tap(find.text('ไปเช็คเงินที่หน้าแรก'));
    expect(app.tab.value, AppTab.home);
  });

  testWidgets('AC-15 orders groups and renders bounded step progress', (
    tester,
  ) async {
    final data = _PlanData();
    data.plans['primary'] = [
      plan('unknown', 'แผนเก่า', status: 'legacy', steps: const []),
      plan(
        'finished',
        'แผนที่จบ',
        status: 'finished',
        done: 3,
        steps: const ['ขั้นที่จบแล้ว'],
      ),
      plan('snoozed', 'แผนที่เลื่อน', status: 'snoozed', done: -1),
      plan(
        'blocked',
        'แผนติดปัญหา',
        status: 'blocked',
        steps: const ['หาหลักฐาน'],
      ),
      plan('active', 'แผนที่กำลังทำ', moneyId: 'old_age', done: 1),
    ];
    await _showPlans(tester, data);
    await tester.pumpAndSettle();
    expect(find.text('5 แผนที่บันทึก'), findsOneWidget);
    expect(find.text('สวัสดิการรัฐ'), findsOneWidget);
    final positions = [
      'แผนที่กำลังทำ',
      'รอดำเนินการ',
      'แผนติดปัญหา',
      'แผนที่เลื่อน',
      'เสร็จแล้ว',
      'แผนที่จบ',
      'แผนเก่า',
    ].map((label) => tester.getTopLeft(find.text(label)).dy).toList();
    expect(positions, orderedEquals([...positions]..sort()));
    expect(
      find.text('ขั้นถัดไป ติดต่อหน่วยงาน', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('ขั้นถัดไป หาหลักฐาน', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('ขั้นที่จบแล้ว', findRichText: true),
      findsNothing,
    );
    expect(find.text('0/2 ขั้น'), findsOneWidget);
    expect(find.text('1/1 ขั้น'), findsOneWidget);
    expect(find.text('0/0 ขั้น'), findsNothing);
    expect(find.text('ติดปัญหา'), findsOneWidget);
    expect(find.text('เลื่อนไว้'), findsOneWidget);
    expect(find.text('ครบตามที่คุณแจ้ง'), findsOneWidget);
    expect(find.text('ไม่ระบุสถานะ'), findsWidgets);
  });

  testWidgets(
    'AC-16 opens plans in the correct profile and keeps scroll and fresh progress',
    (tester) async {
      final data = _PlanData();
      data.plans['primary'] = [
        plan('same-id', 'แผนเก่าไม่มีหมวด'),
        plan('job', 'แผนงาน', category: 'job_full'),
        for (var i = 0; i < 3; i++) plan('id$i', 'แผนเพิ่มเติม $i'),
      ];
      for (final demo in DemoChatProfile.values) {
        data.plans[demo.deviceSuffix] = [
          plan('same-id', 'แผน ${demo.name}', categoryId: 5),
        ];
      }
      await _showPlans(tester, data, size: const Size(360, 700));
      await tester.pumpAndSettle();
      expect(find.text('8 แผนที่บันทึก'), findsOneWidget);
      expect(find.text('งานประจำ'), findsOneWidget);
      expect(find.text('รอดำเนินการ'), findsNothing);
      expect(find.text('กำลังทำ'), findsWidgets);

      await tester.tap(find.text('แผนเก่าไม่มีหมวด'));
      await tester.pumpAndSettle();
      expect(data.opened.last, ('primary', 'same-id'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('แผนงาน'));
      await tester.pumpAndSettle();
      expect(data.opened.last, ('primary', 'job'));
      await tester.pageBack();
      await tester.pumpAndSettle();

      final demo = DemoChatProfile.tax;
      final demoPlan = find.text('แผน ${demo.name}');
      await tester.scrollUntilVisible(demoPlan, 230);
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      final offset = scroll.position.pixels;
      expect(offset, greaterThan(0));
      expect(find.text(demo.planLabel), findsOneWidget);
      expect(find.text('พาร์ตไทม์'), findsWidgets);
      await tester.tap(demoPlan);
      await tester.pumpAndSettle();
      expect(data.opened.last, (demo.deviceSuffix, 'same-id'));
      expect(
        tester.widget<TaskScreen>(find.byType(TaskScreen)).app.demo,
        isTrue,
      );
      final complete = find.text('✓ ทำขั้นนี้เสร็จแล้ว');
      await tester.scrollUntilVisible(complete.hitTestable(), 160);
      await tester.pumpAndSettle();
      await tester.tap(complete);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, offset);
      expect(find.text('1/2 ขั้น'), findsOneWidget);
    },
  );

  testWidgets(
    'AC-17 retries, pulls to refresh and opens a large-text card via semantics',
    (tester) async {
      final data = _PlanData();
      data.errors['primary'] = ApiException(503, 'SERVER', 'โหลดแผนไม่สำเร็จ');
      data.plans[DemoChatProfile.connected.deviceSuffix] = [
        plan(
          'demo',
          'งานตัวอย่างที่อยู่ในโปรไฟล์ทดสอบ',
          category: 'freelance',
          done: 1,
        ),
      ];
      await _showPlans(tester, data, size: const Size(320, 650), scale: 2);
      await tester.pumpAndSettle();
      expect(find.text('โหลดแผนไม่สำเร็จ'), findsOneWidget);
      expect(find.text('1 แผนที่บันทึก'), findsOneWidget);
      expect(find.text('ฟรีแลนซ์'), findsOneWidget);
      expect(find.text('ยังไม่มีแผน'), findsNothing);
      expect(tester.takeException(), isNull);

      data.errors['primary'] = ApiException(0, 'NETWORK', 'ออฟไลน์');
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      expect(find.byType(OfflineCard), findsOneWidget);
      expect(data.primaryLoads, 2);
      data.errors.clear();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 340));
      await tester.pumpAndSettle();
      expect(data.primaryLoads, 3);
      expect(find.byType(OfflineCard), findsNothing);

      final card = find.semantics.byLabel(
        RegExp('งานตัวอย่างที่อยู่ในโปรไฟล์ทดสอบ'),
      );
      final label = card.evaluate().single.label;
      expect(label, contains('ฟรีแลนซ์'));
      expect(label, contains('กำลังทำ'));
      expect(label, contains('ขั้นถัดไป ติดต่อหน่วยงาน'));
      expect(label, contains('ทำแล้ว 1 จาก 2 ขั้น'));
      tester.semantics.tap(card);
      await tester.pumpAndSettle();
      expect(data.opened.last, (
        DemoChatProfile.connected.deviceSuffix,
        'demo',
      ));
      expect(tester.takeException(), isNull);
    },
  );
}
