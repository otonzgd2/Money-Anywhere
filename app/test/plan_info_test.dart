import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/plan_info.dart';
import 'package:money_anywhere/plan_contact_screen.dart';
import 'package:money_anywhere/plans_tab.dart';
import 'package:money_anywhere/task_screen.dart';
import 'package:money_anywhere/thang_rot_theme.dart';

class _PlanApi extends Api {
  String id = 'welfare';
  String? moneyId;
  bool sourceFails = false, closed = false;
  int sourceReads = 0;

  Map<String, dynamic> get task => {
    'id': 'test-plan',
    'title': 'แผน $id',
    'status': 'active',
    'doneCount': 1,
    'steps': ['เตรียมข้อมูล', 'ติดต่อหน่วยงาน'],
    'districtCode': '1047',
    if (moneyId == null) 'opportunityId': id else 'moneyId': moneyId,
  };

  @override
  Api forDemo(String name) => _EmptyPlans();

  @override
  Future<Map<String, dynamic>> get(String path) async {
    if (path == '/v1/tasks') {
      return {
        'items': [task],
      };
    }
    if (path == '/v1/tasks/test-plan') return task;
    sourceReads++;
    if (sourceFails) throw ApiException(503, 'TEST', 'source unavailable');
    return {
      'category': id,
      'title': 'ต้นทาง $id',
      'organization': 'หน่วยงานตัวอย่าง',
      'summary': 'สรุปจากต้นทาง $id',
      'conditions': ['เงื่อนไขตัวอย่าง'],
      'documents': ['เอกสารของแผน'],
      'money': {'basis': 'listing', 'min': 500, 'unit': 'บาท/วัน'},
      'claim': {'taxYear': 2568, 'paymentCycle': 'ตามรอบประกาศ'},
      'job': {'shift': 'กะเช้า', 'deliverables': 'ส่งงานตามข้อตกลง'},
      'income': {'type': 'training', 'skills': 'วางแผนต้นทุน'},
      'grant': {
        'round': 'รอบประจำปี',
        if (closed) 'closesAt': '2020-05-05T09:30:00Z',
      },
      'contacts': [
        {
          'label': 'ช่องทางสมัคร',
          'purpose': 'apply',
          'type': 'website',
          'destination': 'https://agency.test/apply',
          'districtCode': '1047',
        },
        {'label': 'สำนักงานอีกเขต', 'type': 'office', 'districtCode': '1033'},
      ],
      'locations': [
        {
          'districtCode': '1047',
          'address': 'สำนักงานบางนา',
          'precision': 'city',
        },
      ],
      'provenance': {'dataStatus': 'curated', 'attribution': 'หน่วยงานต้นทาง'},
    };
  }
}

class _EmptyPlans extends Api {
  @override
  Future<Map<String, dynamic>> get(String path) async => {'items': []};
}

void main() {
  const layouts = {
    'welfare': ('สวัสดิการรัฐ', 'สิทธิ์และเงิน'),
    'refund': ('เงินคืน', 'สิทธิ์และเงิน'),
    'owed': ('เงินค้างจ่าย', 'สิทธิ์และเงิน'),
    'job_full': ('งานประจำ', 'ข้อมูลงาน'),
    'job_part': ('พาร์ตไทม์', 'ข้อมูลงาน'),
    'freelance': ('ฟรีแลนซ์', 'ข้อมูลงาน'),
    'sell': ('ขายสินค้า', 'ช่องทางหารายได้'),
    'assets': ('ใช้ทรัพย์สิน', 'ช่องทางหารายได้'),
    'grant': ('ทุนให้เปล่า', 'ข้อมูลรอบทุน'),
    'skill': ('ทักษะ', 'ช่องทางหารายได้'),
  };

  testWidgets(
    'AC-10 opens saved plans for all ten categories and applies four layouts',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _PlanApi();
      addTearDown(api.close);
      for (final category in layouts.entries) {
        api.id = category.key;
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: PlansTab(app: AppState(api)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('แผน ${category.key}'));
        await tester.pumpAndSettle();
        expect(find.text('ต้นทาง ${category.key}'), findsOneWidget);
        expect(find.text(category.value.$1), findsOneWidget);
        expect(find.text(category.value.$2), findsOneWidget);
        expect(find.text('ทำแล้ว 1 จาก 2 ขั้น'), findsOneWidget);
      }
      expect(api.sourceReads, 10);
    },
  );

  testWidgets(
    'AC-12 expired application is disabled, source failures can retry, and progress stays intact',
    (tester) async {
      final api = _PlanApi()
        ..id = 'grant'
        ..sourceFails = true
        ..closed = true;
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskScreen(app: AppState(api), taskId: 'test-plan'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('โหลดรายละเอียดต้นทางไม่สำเร็จ'), findsOneWidget);
      await tester.tap(find.text('ข้อมูลติดต่อ'));
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีช่องทางติดต่อที่ตรวจสอบได้'), findsOneWidget);
      api.sourceFails = false;
      await tester.tap(
        find.descendant(
          of: find.byType(PlanContactScreen),
          matching: find.text('ลองใหม่'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(PlanContactScreen),
          matching: find.text('ปิดรับแล้ว'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('16:30 น. (เวลาไทย)'), findsOneWidget);
      expect(find.text('เปิดเว็บไซต์'), findsNothing);
      expect(find.text('สำนักงานอีกเขต'), findsNothing);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('กำลังทำ'), findsOneWidget);
      expect(find.text('ทำแล้ว 1 จาก 2 ขั้น'), findsOneWidget);
      expect(api.sourceReads, 2);
    },
  );

  testWidgets(
    'AC-13 keyboard navigation opens contact in a small viewport at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _PlanApi()..id = 'freelance';
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: thangRotTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: TaskScreen(app: AppState(api), taskId: 'test-plan'),
        ),
      );
      await tester.pumpAndSettle();
      final contact = find.widgetWithText(OutlinedButton, 'ข้อมูลติดต่อ');
      for (
        var i = 0;
        i < 3 &&
            tester.widget<OutlinedButton>(contact).focusNode?.hasFocus != true;
        i++
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(
        tester.widget<OutlinedButton>(contact).focusNode?.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('ช่องทางติดต่อ'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PlanContactScreen),
          matching: find.text('ต้นทาง freelance'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('contact actions use complete typed destinations and reject unsafe or placeholder URI values', () {
    PlanContact contact(String type, String destination) => PlanContact(
      {'label': 'สอบถาม', 'type': type, 'destination': destination},
      isJob: false,
      legacy: false,
    );
    expect(
      contact('phone', '02-123-4567').destination.toString(),
      'tel:021234567',
    );
    expect(
      contact('email', 'service@agency.test').destination.toString(),
      'mailto:service@agency.test',
    );
    expect(contact('map', 'https://map.agency.test/site').action, 'เปิดแผนที่');
    expect(contact('website', 'javascript:alert(1)').destination, isNull);
    expect(contact('website', 'https://example.org/mock').destination, isNull);
  });
}
