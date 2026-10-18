import 'package:debts_book/main.dart';
import 'package:debts_book/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('amounts accept Arabic digits and commas', () {
    expect(parseAmount('١٥٬٠٠٠'), 15000);
    expect(parseAmount('15,000'), 15000);
    expect(parseAmount('0'), null);
    expect(parseAmount('abc'), null);
    expect(iqd(1234567), '1,234,567');
  });

  test('paying a shop off archives it and keeps overpayment as credit', () {
    final b = Book.create('me');
    final shop = b.shops.first;
    expect(b.add(shop, 'buy', 10000, '2026-10-01', 'خبز'), false);
    expect(b.add(shop, 'buy', 5000, '2026-10-02', ''), false);
    expect(b.total, 15000);
    expect(b.add(shop, 'pay', 4000, '2026-10-03', ''), false);
    expect(b.shopBalance(shop.id), 11000);
    expect(b.add(shop, 'pay', 12000, '2026-10-04', ''), true);
    expect(b.archive.single.bought, 15000);
    expect(b.archive.single.paid, 16000);
    expect(b.shopBalance(shop.id), -1000);
    expect(b.total, 0);
    // a credit alone never settles; the next purchase eats it
    b.add(shop, 'buy', 3000, '2026-10-05', '');
    expect(b.shopBalance(shop.id), 2000);
  });

  testWidgets('first launch creates a book, then the PIN opens it', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.load();
    await t.pumpWidget(DebtsApp(store: store));
    expect(find.text('دفتر جديد'), findsOneWidget);
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'ذنون');
    await t.enterText(fields.at(1), '123456');
    await t.enterText(fields.at(2), '123456');
    await t.tap(find.text('إنشاء وفتح'));
    await t.pumpAndSettle();
    expect(find.text('📒 ذنون'), findsOneWidget);
    expect(store.taken('123456'), true);
    await t.tap(find.text('🔒 قفل'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '000000');
    await t.tap(find.text('فتح'));
    await t.pumpAndSettle();
    expect(find.textContaining('الرمز غلط'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '123456');
    await t.tap(find.text('فتح'));
    await t.pumpAndSettle();
    expect(find.text('تسجيل جديد'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
