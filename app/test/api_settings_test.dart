import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_anywhere/api.dart';

void main() {
  late Directory directory;

  setUp(
    () =>
        directory = Directory.systemTemp.createTempSync('money-anywhere-test-'),
  );
  tearDown(() => directory.deleteSync(recursive: true));

  test('keeps a manually selected URL and device identity across starts', () {
    final first = Api(baseUrl: usbApiBaseUrl, storageDirectory: directory);
    addTearDown(first.close);
    first.setBaseUrl('http://192.0.2.17:8080/');

    final restarted = Api(storageDirectory: directory);
    addTearDown(restarted.close);
    expect(restarted.baseUrl, 'http://192.0.2.17:8080');
    expect(restarted.deviceId, first.deviceId);
  });

  test('cleared onboarding choices stay empty when a write was interrupted', () {
    final first = Api(storageDirectory: directory);
    addTearDown(first.close);
    first.saveOnboardingChoices('yynn');
    File('${directory.path}/money_anywhere_thang_rot_onboarding_v1.tmp')
        .writeAsStringSync('yyyy');
    first.saveOnboardingChoices('');

    final restarted = Api(storageDirectory: directory);
    addTearDown(restarted.close);
    expect(restarted.onboardingChoices, isEmpty);
    restarted.saveOnboardingChoices('nnnn');
    expect(first.onboardingChoices, 'nnnn');
  });

  test(
    'uses the last Wi-Fi default when a later build supplies no default',
    () {
      const savedWifi = 'http://192.0.2.18:8080';
      File('${directory.path}/money_anywhere_wifi_default')
          .writeAsStringSync(savedWifi);
      File('${directory.path}/money_anywhere_server').writeAsStringSync('');

      final api = Api(storageDirectory: directory);
      addTearDown(api.close);
      final wifi = wifiApiBaseUrl.isNotEmpty ? wifiApiBaseUrl : savedWifi;
      expect(api.wifiBaseUrl, wifi);
      expect(
        api.baseUrl,
        const bool.hasEnvironment('API_BASE_URL') ? apiBaseUrl : wifi,
      );
      expect(
        File('${directory.path}/money_anywhere_wifi_default')
            .readAsStringSync(),
        wifi,
      );
    },
  );
}
