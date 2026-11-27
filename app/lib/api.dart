// Thin client for contracts/openapi.yaml (API 0.7). Walking skeleton: hand-written for the
// endpoints the app uses; task B7 replaces it with a client generated from the contract.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Set with --dart-define=API_BASE_URL=... (docs/guide/run-demo-server.md).
/// Default works over USB after `adb reverse tcp:8080 tcp:8080`.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8080');

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

/// Small key/value file in the app's cache folder (device id, server address). Clearing app data resets it.
class _Local {
  static File _f(String name) => File('${Directory.systemTemp.path}/money_anywhere_$name');
  static String? read(String name) {
    try {
      final f = _f(name);
      return f.existsSync() ? f.readAsStringSync().trim() : null;
    } on FileSystemException {
      return null;
    }
  }

  static void write(String name, String value) {
    try {
      _f(name).writeAsStringSync(value);
    } on FileSystemException {
      // not fatal for the Demo
    }
  }
}

class Api {
  Api({String? baseUrl})
      : baseUrl = baseUrl ?? _Local.read('server') ?? apiBaseUrl,
        deviceId = _loadDeviceId();

  Api._forDevice(this.baseUrl, this.deviceId);

  /// Use a separate profile for demos that replace the selected profile's data.
  Api forDemo(String name) => Api._forDevice(baseUrl, '$deviceId-demo-$name');

  void close() => _http.close();

  /// Server address. Can be changed in the app (ฉัน > server) when USB is unplugged and Wi-Fi is used instead.
  String baseUrl;

  /// No login in the Demo: one random id per install so answers and plans survive closing the app.
  final String deviceId;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 8);

  static String _loadDeviceId() {
    final id = _Local.read('device_id');
    if (id != null && id.startsWith('device-')) return id;
    final n = 'device-${_randomHex(16)}';
    _Local.write('device_id', n);
    return n;
  }

  void setBaseUrl(String url) {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    _Local.write('server', baseUrl);
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
