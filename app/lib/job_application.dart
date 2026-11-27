import 'dart:io';

String jobApplicationDemoUrl(String baseUrl, String title) =>
    '$baseUrl/docs/mockups/job-application.html#title=${Uri.encodeComponent(title)}';

Future<Uri?> reachableJobApplicationUrl(Map? provenance) async {
  if (provenance == null || provenance['dataStatus'] == 'mock') return null;
  final uri = Uri.tryParse(provenance['sourceUrl']?.toString().trim() ?? '');
  if (uri == null || !{'https', 'http'}.contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  const placeholderDomains = {'example.org', 'example.com', 'example.net'};
  if (uri.host.endsWith('.example') || placeholderDomains.any((host) => uri.host == host || uri.host.endsWith('.$host'))) return null;

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final response = await client.getUrl(uri).then((request) => request.close()).timeout(const Duration(seconds: 5));
    return response.statusCode >= 200 && response.statusCode < 300 ? uri : null;
  } on Exception {
    return null;
  } finally {
    client.close(force: true);
  }
}
