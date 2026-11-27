import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:money_anywhere/api.dart';
import 'package:money_anywhere/common.dart';
import 'package:money_anywhere/me_tab.dart';
import 'package:money_anywhere/profile_overview_screen.dart';

const _demoResponse = <String, dynamic>{
  'dataStatus': 'mock',
  'profile': {'displayName': 'นายสมศักดิ์ สมมติ', 'district': 'ปทุมวัน'},
  'identity': {
    'dataStatus': 'mock',
    'pidMasked': 'X-XXXX-XXXXX-12-3',
    'claims': {
      'name': 'นายสมศักดิ์ สมมติ',
      'address': {
        'formatted': '12 ซอยทดสอบ เขตปทุมวัน กรุงเทพมหานคร',
        'locality': 'ปทุมวัน',
      },
      'date_of_issuance': '2023-01-10',
      'date_of_expiry': '2031-04-11',
    },
    'derived': {'age': 65, 'ageBand': '60-69'},
  },
  'sources': [
    {'field': 'identity', 'label': 'ThaID', 'value': 'อายุ 65 ปี'},
    {'field': 'disabilityCard', 'label': 'ทางรัฐ', 'value': 'มีบัตร'},
    {
      'field': 'ss33',
      'label': 'ประกันสังคม',
      'value': 'ส่งเงินสมทบ 8 จาก 15 เดือน',
    },
    {
      'field': 'taxWithheld',
      'label': 'D-MyTax',
      'value': '1,250 บาท · ปีภาษี 2569',
    },
  ],
};

class _ProfileApi extends Api {
  _ProfileApi({
    this.profile,
    this.unavailable = false,
    this.demoEnabled = false,
    this.identity,
  });
  Map<String, dynamic>? profile;
  bool unavailable;
  final bool demoEnabled;
  final Map<String, dynamic>? identity;

  @override
  Future<Map<String, dynamic>> get(String path) async {
    switch (path) {
      case '/v1/me/profile':
        if (unavailable) throw ApiException(0, 'NETWORK', 'Offline');
        return profile ?? (throw ApiException(404, 'NOT_FOUND', 'Empty'));
      case '/v1/me/facts':
        return {};
      case '/v1/me/gov-link':
        return identity == null
            ? {'status': 'not_connected'}
            : {'status': 'connected', 'identity': identity};
      case '/v1/demo/personas/gov-prefill':
        if (!demoEnabled) {
          throw ApiException(404, 'NOT_FOUND', 'Demo unavailable');
        }
        return _demoResponse;
      case '/v1/me/memory':
        return {'items': []};
      case '/v1/me/settings':
        return {'largeText': false};
      case '/v1/app-config':
        return {
          'featureFlags': {'demo': demoEnabled},
          'routes': {
            'me': {
              'sections': [
                {
                  'id': 'demo.gov-prefill',
                  'items': [
                    {
                      'label': 'โปรไฟล์เชื่อม 4 แหล่ง (DEMO)',
                      'sub': 'ข้อมูลตัวอย่าง',
                      'onTap': {
                        'action': 'demo.load',
                        'params': {'id': 'gov-prefill'},
                        'then': {'route': 'me.profile'},
                      },
                    },
                  ],
                },
              ],
            },
          },
          'actions': {
            'demo.load': {'path': '/v1/demo/personas/{id}'},
          },
        };
      case '/v1/me/consents':
        return {
          'current': {
            'purposes': {'core': true},
          },
        };
      default:
        throw StateError('Unexpected GET $path');
    }
  }

  @override
  Future<Map<String, dynamic>> put(String path, Object body) async {
    expect(path, '/v1/me/profile');
    return profile = Map<String, dynamic>.from(body as Map);
  }
}

Future<void> _openProfile(
  WidgetTester tester,
  Api api, {
  ProfileDemo? demo,
}) async {
  tester.view.physicalSize = const Size(800, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(api.close);
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileOverviewScreen(app: AppState(api), demo: demo),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the Me profile keeps the saved details and opens the example separately',
    (tester) async {
      final api = _ProfileApi(
        profile: {'displayName': 'มาลี', 'district': 'ปทุมวัน'},
        demoEnabled: true,
      );
      final app = AppState(api);
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: MeTab(app: app)));
      await tester.pumpAndSettle();
      expect(find.text('มาลี\nเขตที่อยู่ ปทุมวัน'), findsOneWidget);

      api.profile = {...api.profile!, 'displayName': 'มาลี แก้ไข'};
      app.bump();
      await tester.pumpAndSettle();
      expect(find.text('มาลี แก้ไข\nเขตที่อยู่ ปทุมวัน'), findsOneWidget);

      await tester.tap(find.text('โปรไฟล์ของฉัน'));
      await tester.pumpAndSettle();
      expect(find.text('มาลี แก้ไข'), findsOneWidget);
      expect(find.text('บัตรประจำตัวคนพิการ'), findsNothing);
      await tester.tap(find.text('ดูโปรไฟล์ตัวอย่าง'));
      await tester.pumpAndSettle();
      expect(find.text('มาลี แก้ไข'), findsNothing);
      expect(find.text('ข้อมูลส่วนตัว'), findsOneWidget);
      expect(find.text('นายสมศักดิ์ สมมติ'), findsOneWidget);
      expect(find.text('DEMO / MOCK'), findsOneWidget);
      expect(find.text('1,250 บาท · ปีภาษี 2569'), findsOneWidget);
      expect(api.profile?['displayName'], 'มาลี แก้ไข');
    },
  );

  testWidgets(
    'an empty saved profile displays the native identity and imported values in one profile',
    (tester) async {
      await _openProfile(tester, _ProfileApi(demoEnabled: true));

      expect(find.text('นายสมศักดิ์ สมมติ'), findsOneWidget);
      expect(find.text('ข้อมูลส่วนตัว'), findsOneWidget);
      expect(find.text('65 ปี'), findsOneWidget);
      expect(find.text('ที่อยู่ตามทะเบียนบ้าน'), findsOneWidget);
      expect(find.text('XXX123'), findsOneWidget);
      expect(find.text('1,250 บาท · ปีภาษี 2569'), findsOneWidget);
      expect(find.text('ยังไม่ได้ตั้งชื่อ'), findsNothing);
      expect(find.textContaining('60-69'), findsNothing);
      expect(find.text('วันออกบัตร'), findsNothing);
      expect(find.text('วันบัตรหมดอายุ'), findsNothing);
      expect(find.text('เขตที่อยู่'), findsNothing);
    },
  );

  testWidgets(
    'combines matching ThaID and saved profile details in one section',
    (tester) async {
      await _openProfile(
        tester,
        _ProfileApi(
          profile: {'displayName': 'มาลี สมมติ', 'district': 'บางนา'},
          identity: {
            'dataStatus': 'mock',
            'pidMasked': 'X-XXXX-XXXXX-45-6',
            'claims': {
              'birthdate': '${DateTime.now().year - 75}-01-01',
              'address': {
                'formatted': '99 ซอยทดสอบ เขตบางนา กรุงเทพมหานคร',
                'locality': 'บางนา',
              },
              'date_of_issuance': '2021-04-12',
            },
            'derived': {
              'displayName': 'มาลี สมมติ',
              'ageBand': '70-79',
              'district': 'บางนา',
            },
          },
        ),
      );

      expect(find.text('ข้อมูลส่วนตัว'), findsOneWidget);
      expect(find.text('มาลี สมมติ'), findsOneWidget);
      expect(find.text('75 ปี'), findsOneWidget);
      expect(find.text('99 ซอยทดสอบ เขตบางนา กรุงเทพมหานคร'), findsOneWidget);
      expect(find.text('XXX456'), findsOneWidget);
      expect(find.text('DEMO / MOCK'), findsOneWidget);
      expect(find.text('70-79'), findsNothing);
      expect(find.text('วันออกบัตร'), findsNothing);
      expect(find.text('D-MyTax'), findsNothing);
    },
  );

  testWidgets('shows stored profile and refreshes after editing', (
    tester,
  ) async {
    final api = _ProfileApi(
      profile: {
        'displayName': 'มาลี (สมมติ)',
        'district': 'ปทุมวัน',
        'skills': ['ทำอาหาร'],
        'hoursPerWeek': '10-20',
        'incomeGoalPerMonth': 12000,
        'fromGov': ['ageBand'],
      },
    );
    await _openProfile(tester, api);

    expect(find.text('มาลี (สมมติ)'), findsOneWidget);
    expect(find.text('ปทุมวัน'), findsOneWidget);
    expect(find.text('อายุ'), findsNothing);
    expect(find.text('ทำอาหาร'), findsOneWidget);
    expect(find.text('DEMO / MOCK'), findsNothing);
    expect(find.text('D-MyTax'), findsNothing);
    expect(find.textContaining('12,000'), findsOneWidget);

    await tester.tap(find.text('แก้ไขโปรไฟล์'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'ชื่อที่ใช้ในแอป'),
      'ชื่อเล่นตัวอย่าง',
    );
    await tester.ensureVisible(find.text('บันทึก'));
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();

    expect(api.profile?['displayName'], 'ชื่อเล่นตัวอย่าง');
    expect(api.profile?['skills'], ['ทำอาหาร']);
    expect(find.text('ชื่อเล่นตัวอย่าง'), findsOneWidget);
  });

  testWidgets('shows the four synthetic sources and marks the demo profile', (
    tester,
  ) async {
    await _openProfile(
      tester,
      _ProfileApi(),
      demo: ProfileDemo.fromResponse(_demoResponse)!,
    );

    expect(find.text('นายสมศักดิ์ สมมติ'), findsOneWidget);
    expect(find.text('DEMO / MOCK'), findsOneWidget);
    expect(find.text('ข้อมูลส่วนตัว'), findsOneWidget);
    for (final source in ['ThaID', 'ทางรัฐ', 'ประกันสังคม', 'D-MyTax']) {
      expect(find.text(source), findsOneWidget);
    }
    expect(find.text('แก้ไขโปรไฟล์'), findsNothing);
  });

  testWidgets('omits unavailable identity fields on an empty profile', (
    tester,
  ) async {
    await _openProfile(tester, _ProfileApi());

    expect(find.text('ยังไม่ได้ตั้งชื่อ'), findsOneWidget);
    expect(find.text('อายุ'), findsNothing);
    expect(find.text('เลขบัตรประชาชน'), findsNothing);
    expect(find.text('แก้ไขโปรไฟล์'), findsOneWidget);
  });

  testWidgets('shows a retry button when the backend is unavailable', (
    tester,
  ) async {
    final api = _ProfileApi(unavailable: true);
    await _openProfile(tester, api);

    expect(find.text('โหลดโปรไฟล์ไม่ได้'), findsOneWidget);
    api.unavailable = false;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่ได้ตั้งชื่อ'), findsOneWidget);
  });
}
