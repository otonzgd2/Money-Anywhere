// Pure helpers for the money lane. No UI, so they are unit tested (test/money_test.dart).

/// Turns the option the person tapped (or typed) into the fact value the money engine expects.
/// Bool questions list the "true" option first (contracts/fixtures/reference.json `facts`).
Object? toFactValue(Map<String, dynamic> question, String answer) {
  switch (question['type']) {
    case 'bool':
      final options = (question['options'] as List).cast<String>();
      return answer == options.first;
    case 'number':
      return int.tryParse(answer.replaceAll(RegExp(r'[^0-9]'), ''));
    default:
      return answer;
  }
}

/// How certain the first action is, inside the money lane only (never compared with jobs or skills).
/// Lower is shown first. 8 = already receiving, 9 = not shown.
int tierOf(Map<String, dynamic> item) {
  if (item['alreadyReceiving'] == true) return 8;
  final status = item['status'];
  final hasAmount = (item['amount'] as Map?)?['value'] is num;
  if (status == 'verified') return 0;
  if (status == 'likely' && hasAmount) return 1;
  if (status == 'likely') return 2;
  if (status == 'check') return 3;
  if (status == 'need') return 4;
  return 9;
}

num _amount(Map<String, dynamic> i) => ((i['amount'] as Map?)?['value'] as num?) ?? 0;

/// Items worth showing, most certain first; monthly money before one-off at the same tier.
List<Map<String, dynamic>> rankMoney(List<dynamic> items) {
  final xs = items.cast<Map<String, dynamic>>().where((i) => tierOf(i) < 8).toList();
  xs.sort((a, b) {
    final t = tierOf(a) - tierOf(b);
    if (t != 0) return t;
    final k = (b['kind'] == 'monthly' ? 1 : 0) - (a['kind'] == 'monthly' ? 1 : 0);
    if (k != 0) return k;
    return _amount(b).compareTo(_amount(a));
  });
  return xs;
}

/// The next question to ask: the first program still waiting for an answer, skipping what the person skipped.
Map<String, dynamic>? nextQuestion(List<dynamic> items, Set<String> skipped) {
  for (final i in items.cast<Map<String, dynamic>>()) {
    final q = i['nextQuestion'] as Map<String, dynamic>?;
    if (i['status'] == 'need' && q != null && !skipped.contains(q['fact'])) return q;
  }
  return null;
}

const statusLabel = {
  'verified': '✅ ยืนยันจากหน่วยงาน',
  'likely': '🟢 น่าจะมีสิทธิ์',
  'check': '🟡 ต้องเช็คยอดจริง',
  'need': '❔ ตอบอีกข้อ',
  'unlikely': '⚪ ไม่น่ามีสิทธิ์',
};

/// Label for where the data came from (always shown, never hidden).
String dataLabel(String? dataStatus) => switch (dataStatus) {
      'live' => 'ข้อมูลจากหน่วยงาน',
      'curated' => 'เกณฑ์จากแหล่งสาธารณะ ยังไม่ยืนยันสิทธิ์',
      _ => 'DEMO / MOCK',
    };

String baht(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '฿$b';
}
