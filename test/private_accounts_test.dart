import 'package:debts_book/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private balances cross zero, keep history and stay separate from shops', () {
    final events = [
      ...startEvents(),
      {'id':'a', 'at':'2024-01-10', 't':'person', 'person':'p', 'name':'محمود'},
      {'id':'b', 'at':'2024-01-11', 't':'receive', 'person':'p', 'date':'2024-01-11', 'amount':600000},
      {'id':'c', 'at':'2024-01-12', 't':'buy', 'shop':'d0', 'date':'2024-01-12', 'amount':3000},
      {'id':'d', 'at':'2024-03-01', 't':'give', 'person':'p', 'date':'2024-03-01', 'amount':800000},
    ];
    final book = Book.replay(events.reversed);
    expect(book.people['p']!.outstanding, -200000);
    expect(book.people['p']!.entries.length, 2);
    expect(book.total, 3000);
    expect(book.archive, isEmpty);
    expect(book.months.take(3).map((m) => m.personal), [600000,600000,0]);
    expect(book.months[2].credit, 200000);
    expect(book.months.last.general, 3000);
  });
}
