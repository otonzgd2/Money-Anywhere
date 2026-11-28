import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/main.dart';
import 'package:money_anywhere/opp_screen.dart';
import 'package:money_anywhere/opp_tab.dart' show OppTab;
import 'package:money_anywhere/opportunity_catalog.dart';

const select = 'เชื่อมต่อข้อมูลจำลอง';
const skipAll = 'ข้ามทั้งหมด';
const save = 'บันทึกไว้ในแผนของฉัน';

Map<String, dynamic> listing(String id, String category, {bool mock = false}) =>
    {
      'id': id,
      'title': 'ประกาศ $id',
      'category': category,
      'organization': 'ผู้เผยแพร่ $id',
      'provenance': {
        'dataStatus': mock ? 'mock' : 'live',
        'attribution': 'แหล่ง $id',
      },
      'money': {'basis': 'listing', 'unit': 'บาท/วัน', 'min': 400, 'max': 500},
      'locations': [
        {
          'districtCode': '1047',
          'address': 'บางนา $id',
          'precision': 'exact',
          'lat': 13.66,
          'lng': 100.60,
        },
        {'districtCode': '1033', 'address': 'คลองเตย $id', 'precision': 'city'},
      ],
    };

class FlowApi extends Api {
  FlowApi(Directory directory) : super(storageDirectory: directory);

  final List<String> calls = [];
  final List<Map<String, dynamic>> tasks = [];
  final Map<String, Map<String, dynamic>> entries = {
    'full1': listing('full1', 'job_full'),
    'full2': listing('full2', 'job_full'),
    'free1': listing('free1', 'freelance'),
    'free2': listing('free2', 'freelance'),
    'part1': listing('part1', 'job_part'),
    'sell1': listing('sell1', 'sell'),
  };
  bool user = false,
      configFails = false,
      assessmentFails = false,
      saveFails = false;
  bool? hasMoreMapLocations;
  final districtCounts = <String, int>{};
  Completer<Map<String, dynamic>>? pendingSave;
  Map<String, dynamic>? previewFacts;

  @override
  Future<Map<String, bool>?> currentPurposes() async => {'core': true};

  @override
  Api forDemo(String name) {
    calls.add('demo-device:$name');
    return _OnboardingApi(this);
  }

  @override
  Future<Map<String, dynamic>> get(String path) async {
    calls.add(path);
    final uri = Uri.parse(path);
    switch (uri.path) {
      case '/v1/app-config':
        if (configFails) throw ApiException(503, 'TEST', 'config');
        return {
          'mode': user ? 'user' : 'demo',
          'featureFlags': {'demo': !user},
        };
      case '/v1/money':
        if (assessmentFails) throw ApiException(503, 'TEST', 'assessment');
        return {
          'items': [
            {
              'id': 'old_age',
              'title': 'เบี้ยยังชีพผู้สูงอายุ',
              'kind': 'monthly',
              'status': 'need',
            },
          ],
        };
      case '/v1/plans/options':
        return {'items': []};
      case '/v1/tasks':
        return {'items': List.of(tasks)};
      case '/v1/me/memory':
        return {'items': []};
      case '/v1/opportunities':
        expect(uri.queryParameters['area'], 'bangkok');
        final category = uri.queryParameters['category'];
        if (uri.queryParameters['includeDistrictPins'] == 'true') {
          return {
            'districtPins': [
              if (districtCounts[category] case final count?)
                {
                  'district': 'บางนา',
                  'lat': 13.68,
                  'lng': 100.63,
                  'count': count,
                },
            ],
          };
        }
        final candidates = entries.values
            .where((item) => category == null || item['category'] == category)
            .toList();
        if (category == null || candidates.length < 2) {
          return {'items': candidates};
        }
        return uri.queryParameters.containsKey('cursor')
            ? {'items': candidates.skip(1).toList()}
            : {
                'items': candidates.take(1).toList(),
                'nextCursor': 'page-two',
                if (hasMoreMapLocations != null)
                  'hasMoreMapLocations': hasMoreMapLocations,
              };
    }
    if (uri.pathSegments.length == 3 &&
        uri.pathSegments[1] == 'opportunities') {
      final item = entries[uri.pathSegments.last];
      if (item == null) throw ApiException(404, 'NOT_FOUND', 'no item');
      return {...item, 'description': 'รายละเอียดล่าสุด ${item['id']}'};
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) async {
    calls.add('POST $path');
    if (path == '/v1/money/preview') {
      previewFacts = (body as Map)['facts'] as Map<String, dynamic>;
      return {
        'items': [
          {
            'id': 'old_age',
            'title': 'เบี้ยยังชีพผู้สูงอายุ',
            'kind': 'monthly',
            'status': 'likely',
            'amount': {'value': 600, 'unit': 'บาท/เดือน'},
          },
          {
            'id': 'tax_refund',
            'title': 'เงินคืนภาษี',
            'kind': 'once',
            'status': 'check',
          },
        ],
      };
    }
    if (path == '/v1/tasks') {
      if (saveFails) throw ApiException(503, 'TEST', 'บันทึกไม่สำเร็จ');
      final task = {'id': 't1', ...body as Map<String, dynamic>};
      if (pendingSave case final pending?) await pending.future;
      tasks.add(task);
      return task;
    }
    return {};
  }
}

class _OnboardingApi extends Api {
  _OnboardingApi(this.flow);
  final FlowApi flow;

  @override
  Future<Map<String, dynamic>> get(String path) async => {'items': []};

  @override
  Future<Map<String, dynamic>> post(
    String path, [
    Object? body,
    Map<String, String>? headers,
  ]) async {
    expect(Uri.parse(path).queryParameters.keys, ['sources']);
    flow.calls.add('isolated $path');
    return {
      'dataStatus': 'mock',
      'facts': {'govPension': false},
    };
  }
}

void main() {
  late FlowApi api;

  setUp(() {
    final directory = Directory.systemTemp.createTempSync('thang-rot-test-');
    api = FlowApi(directory);
    addTearDown(() {
      api.close();
      directory.deleteSync(recursive: true);
    });
  });

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      MoneyAnywhereApp(key: UniqueKey(), app: AppState(api), runStartup: true),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    final text = find.text(label);
    if (text.evaluate().isNotEmpty && text.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(text.first);
      await tester.pumpAndSettle();
    }
    await tester.tap(text.hitTestable().first);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'AC-02 connects four bundled sources in order and does not show them again',
    (tester) async {
      await launch(tester);
      for (final source in [
        'ThaID',
        'ทางรัฐ',
        'ประกันสังคม (SSO+)',
        'D-MyTax',
      ]) {
        expect(find.text(source), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );
        expect(
          find.text('ใช้ข้อมูลจำลองเพื่อประเมินสิทธิ์และรายได้'),
          findsOneWidget,
        );
        await choose(tester, select);
      }
      expect(api.onboardingChoices, 'yyyy');
      expect(api.calls, contains('demo-device:thang-rot-onboarding'));
      expect(
        api.calls.where((call) => call.startsWith('isolated')).single,
        endsWith('sources=thaid%2CtangRat%2CsocialSecurity%2CdMyTax'),
      );
      expect(api.previewFacts, {'govPension': false});
      expect(find.text('รายเดือน 600 บาท'), findsOneWidget);
      expect(find.text('ครั้งเดียว ยังไม่ทราบยอด'), findsOneWidget);
      await choose(tester, 'ผลประเมินสิทธิ์และสวัสดิการ');
      expect(find.textContaining('ตรวจสอบยอดกับหน่วยงาน'), findsOneWidget);
      await launch(tester);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'AC-03 resumes the undecided source and skip remaining keeps selections',
    (tester) async {
      await launch(tester);
      await choose(tester, select);
      await choose(tester, 'ข้าม');
      await launch(tester);
      expect(find.text('ประกันสังคม (SSO+)'), findsOneWidget);
      await choose(tester, skipAll);
      expect(api.onboardingChoices, 'ynnn');
      expect(
        api.calls.where((call) => call.startsWith('isolated')).single,
        endsWith('sources=thaid'),
      );
    },
  );

  testWidgets('AC-03 skipping everything loads only the primary assessment', (
    tester,
  ) async {
    await launch(tester);
    await choose(tester, skipAll);
    expect(api.onboardingChoices, 'nnnn');
    expect(api.calls.where((call) => call.contains('personas')), isEmpty);
    expect(find.text('ข้อมูลยังไม่พอประเมิน'), findsOneWidget);
  });

  testWidgets(
    'AC-04 unavailable config leaves onboarding pending and user mode can retry assessment',
    (tester) async {
      api.configFails = true;
      api.user = true;
      await launch(tester);
      expect(find.text('ตรวจโหมดแอปไม่ได้'), findsOneWidget);
      api.configFails = false;
      api.assessmentFails = true;
      await choose(tester, 'ลองใหม่');
      expect(find.text('ยังประเมินไม่สำเร็จ'), findsOneWidget);
      api.assessmentFails = false;
      await choose(tester, 'ลองใหม่');
      expect(find.text('ผลประเมินสิทธิ์และสวัสดิการ'), findsOneWidget);
      expect(api.onboardingChoices, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('AC-06 unions category pages and retains filters after detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppState(api)..oppGroup.value = 'job';
    await tester.pumpWidget(MaterialApp(home: OppTab(app: app)));
    await tester.pumpAndSettle();
    await choose(tester, 'ประเภทงาน');
    await choose(tester, 'งานประจำ');
    await choose(tester, 'ฟรีแลนซ์');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('ประเภทงาน (2)'), findsOneWidget);
    expect(find.text('ประกาศ part1'), findsNothing);
    if (find.text('โหลดเพิ่ม').hitTestable().evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text('โหลดเพิ่ม'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await choose(tester, 'โหลดเพิ่ม');
    expect(
      api.calls.where(
        (call) =>
            call.contains('cursor=page-two') && call.contains('category='),
      ),
      hasLength(2),
    );
    await tester.ensureVisible(find.text('ประกาศ free2'));
    await choose(tester, 'ประกาศ free2');
    expect(find.text('รายละเอียดล่าสุด free2'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('ประเภทงาน (2)'), findsOneWidget);
    expect(find.text('ประกาศ part1'), findsNothing);
    await choose(tester, 'ดูแผนที่');
    expect(find.text('ยังไม่มีพิกัดสำหรับตัวกรองนี้'), findsOneWidget);
    const lanes = {
      'สิทธิ์และสวัสดิการ': {'welfare', 'refund', 'owed'},
      'ขายสินค้า': {'sell'},
      'อื่นๆ': {'assets', 'grant', 'skill'},
      'ทั้งหมด': {null},
    };
    for (final lane in lanes.entries) {
      final before = api.calls.length;
      await choose(tester, lane.key);
      final categories = api.calls
          .skip(before)
          .where((call) => call.startsWith('/v1/opportunities?'))
          .map((call) => Uri.parse(call).queryParameters['category'])
          .toSet();
      expect(categories, lane.value);
    }
  });

  test('AC-07 only in-range exact database coordinates qualify and legacy district names resolve', () {
    const known = {
      'district': 'เขตบางนา',
      'precision': 'exact',
      'lat': 13.66,
      'lng': 100.60,
    };
    expect(OpportunityLocation(known).districtCode, '1047');
    expect(OpportunityLocation(known).point, isNull);
    const db = {...known, 'coordinateSource': 'database'};
    expect(OpportunityLocation(db).point, isNotNull);
    expect(OpportunityLocation({...db, 'lat': 91}).point, isNull);
    expect(OpportunityLocation({...db, 'workMode': 'remote'}).point, isNull);
    expect(
      OpportunityLocation({...db, 'areaType': 'service_area'}).point,
      isNull,
    );
  });

  testWidgets(
    'AC-07 the list and a database pin open the same opportunity ID',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final entry = api.entries['full1']!;
      final locations = entry['locations'] as List;
      (locations.first as Map)['coordinateSource'] = 'database';
      final app = AppState(api)..oppGroup.value = 'job';
      await tester.pumpWidget(MaterialApp(home: OppTab(app: app)));
      await tester.pumpAndSettle();
      await choose(tester, 'ประกาศ full1');
      expect(find.text('รายละเอียดล่าสุด full1'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await choose(tester, 'ดูแผนที่');
      final pin = find.byTooltip('ประกาศ full1');
      expect(pin, findsOneWidget);
      expect(find.byTooltip('ประกาศ free1'), findsNothing);
      await tester.tap(pin);
      await tester.pumpAndSettle();
      expect(find.text('รายละเอียดล่าสุด full1'), findsOneWidget);
      expect(find.text('บางนา full1'), findsOneWidget);
      expect(find.text('คลองเตย full1'), findsNothing);
    },
  );

  testWidgets(
    'map skips later pages without pins and list can still load them',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      api.hasMoreMapLocations = false;
      final app = AppState(api)..oppGroup.value = 'job';
      await tester.pumpWidget(MaterialApp(home: OppTab(app: app)));
      await tester.pumpAndSettle();

      await choose(tester, 'ดูแผนที่');
      expect(find.text('ยังไม่มีพิกัดสำหรับตัวกรองนี้'), findsOneWidget);
      expect(
        api.calls.any((call) => call.contains('cursor=page-two')),
        isFalse,
      );

      await choose(tester, 'โหลดเพิ่ม');
      expect(api.calls.any((call) => call.contains('cursor=page-two')), isTrue);
      expect(find.text('ประกาศ full2'), findsOneWidget);
    },
  );

  testWidgets('map combines demo district counts and opens the scoped list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api.hasMoreMapLocations = false;
    api.districtCounts.addAll({'job_full': 20, 'job_part': 20});
    final locations = api.entries['full1']!['locations'] as List;
    (locations.first as Map)['coordinateSource'] = 'database';
    final app = AppState(api)..oppGroup.value = 'job';
    await tester.pumpWidget(MaterialApp(home: OppTab(app: app)));
    await tester.pumpAndSettle();

    await choose(tester, 'ดูแผนที่');
    expect(find.byTooltip('ประกาศ full1'), findsOneWidget);
    expect(find.text('DEMO · พิกัดรายเขต 1 เขต'), findsOneWidget);
    final districtPin = find.byTooltip('เขตบางนา 40 รายการจำลอง');
    expect(districtPin, findsOneWidget);
    await tester.tap(districtPin);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'เขตบางนา'), findsOneWidget);
    expect(find.text('ดูแผนที่'), findsOneWidget);
    expect(
      api.calls.map(Uri.parse).any((uri) {
        final query = uri.queryParameters;
        return query['districtCode'] == '1047' && query['district'] == 'บางนา';
      }),
      isTrue,
    );
  });

  testWidgets(
    'AC-08 opens an ID with district context and handles missing IDs',
    (tester) async {
      final app = AppState(api);
      await tester.pumpWidget(MoneyAnywhereApp(app: app));
      await tester.pumpAndSettle();
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      void open(String id, String? district) => nav.pushNamed<void>(
        '/opportunities/$id${district == null ? '' : '?districtCode=$district'}',
      );
      Color? chipColor(String label) =>
          tester.widget<Chip>(find.widgetWithText(Chip, label)).backgroundColor;
      open('full1', '1047');
      await tester.pumpAndSettle();
      expect(find.text('บางนา full1'), findsOneWidget);
      expect(find.text('คลองเตย full1'), findsNothing);
      final jobColor = chipColor('งานประจำ');
      await tester.pageBack();
      await tester.pumpAndSettle();
      open('full2', '1033');
      await tester.pumpAndSettle();
      expect(find.text('คลองเตย full2'), findsOneWidget);
      expect(chipColor('งานประจำ'), jobColor);
      await tester.pageBack();
      await tester.pumpAndSettle();
      open('sell1', null);
      await tester.pumpAndSettle();
      expect(chipColor('ขายสินค้า'), isNot(jobColor));
      await tester.pageBack();
      await tester.pumpAndSettle();
      open('unknown', null);
      await tester.pumpAndSettle();
      expect(find.text('ไม่พบรายการนี้หรือรายการหมดอายุแล้ว'), findsOneWidget);
      await choose(tester, 'กลับไปโอกาส');
      expect(find.text('โอกาส'), findsWidgets);
    },
  );

  testWidgets(
    'AC-09 saves once, reflects backend on reopen and permits retry after failure',
    (tester) async {
      final app = AppState(api);
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: OppScreen(app: app, opportunityId: 'full1'),
          ),
        );
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.text('รายละเอียดงาน'), findsOneWidget);
      api.saveFails = true;
      await choose(tester, save);
      expect(find.text('บันทึกแล้ว'), findsNothing);
      api.saveFails = false;
      api.pendingSave = Completer();
      await tester.ensureVisible(find.text(save));
      await tester.tap(find.text(save));
      await tester.pump();
      final saving = find.widgetWithText(FilledButton, 'กำลังบันทึก');
      expect(tester.widget<FilledButton>(saving).onPressed, isNull);
      api.pendingSave!.complete({});
      await tester.pumpAndSettle();
      expect(api.tasks, hasLength(1));
      expect(find.text('บันทึกแล้ว'), findsOneWidget);
      await open();
      expect(find.text('บันทึกแล้ว'), findsOneWidget);
      api.tasks.clear();
      await open();
      expect(find.text(save), findsOneWidget);
    },
  );
}
