// Thin client for contracts/openapi.yaml (API 0.7). Walking skeleton: hand-written for the
// endpoints the app uses; task B7 replaces it with a client generated from the contract.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const usbApiBaseUrl = 'http://127.0.0.1:8080';

/// Set to the notebook's LAN URL when building an APK for Wi-Fi testing.
const wifiApiBaseUrl = String.fromEnvironment('WIFI_API_BASE_URL');

/// API_BASE_URL can override the Wi-Fi default, for example for an emulator or a tunnel.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: wifiApiBaseUrl == '' ? usbApiBaseUrl : wifiApiBaseUrl,
);

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
  bool get isNetwork => code == 'NETWORK';
  @override
  String toString() => message;
}

String _randomHex(int n) {
  final r = Random.secure();
  return List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
}

/// Settings live in private app storage. Migrate an older cached value if it is still available.
class _Local {
  const _Local(this.directory);
  final Directory directory;

  File _file(Directory folder, String name) => File('${folder.path}/money_anywhere_$name');

  String? _read(File file) {
    try {
      return file.existsSync() ? file.readAsStringSync().trim() : null;
    } on FileSystemException {
      return null;
    }
  }

  String? read(String name) {
    final saved = _read(_file(directory, name));
    final cache = Directory.systemTemp;
    if (saved != null || directory.path == cache.path) return saved;
    final legacy = _read(_file(cache, name));
    if (legacy != null) write(name, legacy);
    return legacy;
  }

  void write(String name, String value) {
    try {
      _file(directory, name).writeAsStringSync(value, flush: true);
    } on FileSystemException {
      // not fatal for the Demo
    }
  }
}

class Api {
  Api({String? baseUrl, Directory? storageDirectory})
      : this._configured(baseUrl, _Local(storageDirectory ?? Directory.systemTemp));

  Api._configured(String? baseUrl, _Local settings)
      : this._forDevice(baseUrl ?? _loadBaseUrl(settings), _loadDeviceId(settings), settings);

  static Future<Api> open() async {
    Directory? directory;
    try {
      if (Platform.isAndroid) {
        const settings = MethodChannel('money_anywhere/local_settings');
        final path = await settings.invokeMethod<String>('settingsDirectory');
        if (path != null) directory = Directory(path);
      } else {
        directory = await getApplicationSupportDirectory();
      }
    } on Exception {
      // Keep the API available if the platform cannot resolve its support directory.
    }
    return Api(storageDirectory: directory);
  }

  Api._forDevice(this.baseUrl, this.deviceId, this._settings);
  final _Local _settings;

  /// Use a separate profile for demos that replace the selected profile's data.
  Api forDemo(String name) => Api._forDevice(baseUrl, '$deviceId-demo-$name', _settings);

  void close() => _http.close();

  /// Server address. Can be changed in the app (ฉัน > server) when USB is unplugged and Wi-Fi is used instead.
  String baseUrl;
  String? get wifiBaseUrl => _wifiBaseUrl(_settings);

  /// No login in the Demo: one random id per install so answers and plans survive closing the app.
  final String deviceId;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 8);

  static String? _wifiBaseUrl(_Local settings) =>
      wifiApiBaseUrl.isNotEmpty ? wifiApiBaseUrl : settings.read('wifi_default');

  static String _loadBaseUrl(_Local settings) {
    if (wifiApiBaseUrl.isNotEmpty && settings.read('wifi_default') != wifiApiBaseUrl) {
      settings.write('wifi_default', wifiApiBaseUrl);
    }
    final wifi = _wifiBaseUrl(settings);
    final saved = settings.read('server');
    if (saved == null || saved.isEmpty) {
      return const bool.hasEnvironment('API_BASE_URL') ? apiBaseUrl : wifi ?? usbApiBaseUrl;
    }

    // Older APKs offered this example address as a Wi-Fi shortcut.
    if (saved == 'http://192.168.1.46:8080' && wifi != null) {
      settings.write('server', wifi);
      return wifi;
    }
    return saved;
  }

  static String _loadDeviceId(_Local settings) {
    final id = settings.read('device_id');
    if (id != null && id.startsWith('device-')) return id;
    final n = 'device-${_randomHex(16)}';
    settings.write('device_id', n);
    return n;
  }

  void setBaseUrl(String url) {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    _settings.write('server', baseUrl);
  }

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);
  Future<Map<String, dynamic>> post(String path, [Object? body, Map<String, String>? headers]) => _send('POST', path, body, headers);
  Future<Map<String, dynamic>> patch(String path, Object body) => _send('PATCH', path, body);
  Future<Map<String, dynamic>> put(String path, Object body) => _send('PUT', path, body);
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(String method, String path, [Object? body, Map<String, String>? headers]) async {
    try {
      final req = await _http.openUrl(method, Uri.parse('$baseUrl$path')).timeout(const Duration(seconds: 10));
      req.headers.set('X-Device-Id', deviceId);
      headers?.forEach(req.headers.set);
      req.headers.contentType = ContentType.json;
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(const Duration(seconds: 40));
      final text = await res.transform(utf8.decoder).join();
      final data = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        throw ApiException(res.statusCode, '${data['code'] ?? 'ERROR'}', '${data['message'] ?? 'ระบบขัดข้อง'}');
      }
      return data;
    } on ApiException {
      rethrow;
    } on Exception {
      throw ApiException(0, 'NETWORK', 'ต่อ server ไม่ได้');
    }
  }

  /// Task state changes always go through events (complete_step, undo, block, snooze, resume, report_outcome).
  Future<Map<String, dynamic>> taskEvent(String taskId, Map<String, Object?> event) =>
      post('/v1/tasks/$taskId/events', event, {'Idempotency-Key': 'k-${_randomHex(12)}'});

  /// Current consent purposes, or null when the person never consented.
  Future<Map<String, bool>?> currentPurposes() async {
    final c = await get('/v1/me/consents');
    final cur = c['current'] as Map<String, dynamic>?;
    if (cur == null) return null;
    return (cur['purposes'] as Map).map((k, v) => MapEntry('$k', v == true));
  }

  /// Records consent. [purposes] is the full set; core is always required to save anything.
  Future<void> setConsent(Map<String, bool> purposes) async {
    final notice = await get('/v1/privacy/notice');
    await post('/v1/me/consents', {'noticeVersion': notice['version'], 'ageConfirmed': true, 'purposes': {...purposes, 'core': true}});
  }

  /// One-click AI button and route consent: keeps purposes already given, adds core (+ ai when asked).
  Future<void> consent({required bool ai}) async {
    final cur = await currentPurposes() ?? {};
    await setConsent({...cur, 'core': true, if (ai) 'ai': true});
  }
}
