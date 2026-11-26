import 'package:flutter_test/flutter_test.dart';

import 'package:money_anywhere/home_tab.dart';
import 'package:money_anywhere/money.dart';
import 'package:money_anywhere/opp_tab.dart';

void main() {
  group('toFactValue', () {
    test('bool: first option is true', () {
      final q = {'type': 'bool', 'options': ['ได้รับอยู่แล้ว', 'ยังไม่ได้รับ']};
      expect(toFactValue(q, 'ได้รับอยู่แล้ว'), isTrue);
      expect(toFactValue(q, 'ยังไม่ได้รับ'), isFalse);
    });
    test('number: digits only', () => expect(toFactValue({'type': 'number'}, '12,000 บาท'), 12000));
    test('enum: kept as text', () => expect(toFactValue({'type': 'enum'}, '60-69'), '60-69'));
  });

  group('rankMoney', () {
    final items = [
      {'id': 'tax', 'status': 'check', 'kind': 'once', 'amount': {'basis': 'none'}},
      {'id': 'old', 'status': 'likely', 'kind': 'monthly', 'amount': {'value': 600}},
      {'id': 'gets', 'status': 'check', 'kind': 'monthly', 'alreadyReceiving': true, 'amount': {'value': 700}},
      {'id': 'no', 'status': 'unlikely', 'kind': 'monthly', 'amount': {'basis': 'none'}},
    ];
    test('sourced amount first, already-receiving and unlikely left out', () {
      expect(rankMoney(items).map((i) => i['id']).toList(), ['old', 'tax']);
    });
  });

  test('nextQuestion skips what the person skipped', () {
    final items = [
      {'status': 'need', 'nextQuestion': {'fact': 'work'}},
      {'status': 'need', 'nextQuestion': {'fact': 'taxWithheld'}},
    ];
    expect(nextQuestion(items, {})?['fact'], 'work');
    expect(nextQuestion(items, {'work'})?['fact'], 'taxWithheld');
    expect(nextQuestion(items, {'work', 'taxWithheld'}), isNull);
  });

  test('nextQuestion finishes the program it was asking about first', () {
    final items = [
      {'id': 'unpaid_wages', 'status': 'need', 'nextQuestion': {'fact': 'hasUnpaid'}},
      {'id': 'child_support', 'status': 'need', 'nextQuestion': {'fact': 'lowIncome'}},
    ];
    expect(nextQuestion(items, {})?['fact'], 'hasUnpaid');
    expect(nextQuestion(items, {}, prefer: 'child_support')?['fact'], 'lowIncome');
  });

  test('"ไม่มี" to a number question is 0', () => expect(toFactValue({'type': 'number'}, 'ไม่มีค่ะ'), 0));

  test('baht formats with commas', () {
    expect(baht(7200), '฿7,200');
    expect(baht(600), '฿600');
  });

  test('mock data is always labelled', () => expect(dataLabel('mock'), 'DEMO / MOCK'));

  group('home next step (ui-states.md §3)', () {
    test('active before snoozed before blocked, finished never', () {
      final t = [
        {'id': 'f', 'status': 'finished'},
        {'id': 'b', 'status': 'blocked'},
        {'id': 's', 'status': 'snoozed'},
        {'id': 'a', 'status': 'active'},
      ];
      expect(nextTask(t)?['id'], 'a');
      expect(nextTask(t.where((x) => x['id'] != 'a').toList())?['id'], 's');
      expect(nextTask([t[0], t[1]])?['id'], 'b');
      expect(nextTask([t[0]]), isNull);
    });
  });

  group('opportunity money text', () {
    test('listing range keeps the unit and says where it came from', () {
      expect(oppMoney({'money': {'basis': 'listing', 'min': 400, 'max': 500, 'unit': 'บาท/วัน'}}), '400-500 บาท/วัน (ตามประกาศ)');
    });
    test('unknown money is never invented', () {
      expect(oppMoney({'money': {'basis': 'none'}}), 'ไม่ทราบจำนวนเงิน');
    });
  });
}
