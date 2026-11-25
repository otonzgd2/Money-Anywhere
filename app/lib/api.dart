// Thin client for contracts/openapi.yaml (API 0.6). Walking skeleton: hand-written for the
// endpoints this slice uses; task B7 replaces it with a client generated from the contract.
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
  @override
  String toString() => message;
}

class Api {
  Api({String? baseUrl})
      : baseUrl = baseUrl ?? apiBaseUrl,
        deviceId = _loadDeviceId();

  final String baseUrl;

  /// No login in the Demo: one random id per install, kept in the app's cache folder so answers and plans
  /// survive closing the app. Clearing app data starts a new synthetic person.
  final String deviceId;

  static String _loadDeviceId() {
    try {
      final f = File('${Directory.systemTemp.path}/money_anywhere_device_id');
      if (f.existsSync()) {
        final id = f.readAsStringSync().trim();
        if (id.startsWith('device-')) return id;
      }
      final id = 'device-${_randomHex(16)}';
      f.writeAsStringSync(id);
      return id;
    } on FileSystemException {
      return 'device-${_randomHex(16)}';
    }
  }
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  static String _randomHex(int n) {
    final r = Random.secure();
    return List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);
  Future<Map<String, dynamic>> post(String path, [Object? body]) => _send('POST', path, body);
  Future<Map<String, dynamic>> patch(String path, Object body) => _send('PATCH', path, body);

  Future<Map<String, dynamic>> _send(String method, String path, [Object? body]) async {
    try {
      final req = await _http.openUrl(method, Uri.parse('$baseUrl$path')).timeout(const Duration(seconds: 15));
      req.headers.set('X-Device-Id', deviceId);
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
      throw ApiException(0, 'NETWORK', 'ต่อ server ไม่ได้ ตรวจว่าเปิด server และต่อสาย/Wi-Fi แล้ว');
    }
  }

  /// Records consent for the given purposes (core is always required to save anything).
  Future<void> consent({required bool ai}) async {
    final notice = await get('/v1/privacy/notice');
    await post('/v1/me/consents', {
      'noticeVersion': notice['version'],
      'ageConfirmed': true,
      'purposes': {'core': true, 'ai': ai},
    });
  }
}
