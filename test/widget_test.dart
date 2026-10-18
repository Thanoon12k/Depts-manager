import 'dart:convert';

import 'package:debts_book/main.dart';
import 'package:debts_book/store.dart';
import 'package:debts_book/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The server's two RPCs, in memory. [online] false = no internet.
class FakeServer {
  final rows = <({int seq, String book, Map event})>[];
  bool online = true;

  late final client = MockClient((r) async {
    if (!online) throw http.ClientException('no internet');
    final b = jsonDecode(r.body);
    if (r.url.path.endsWith('/debts_push')) {
      var n = 0;
      for (final e in b['p_events']) {
        if (rows.any((x) => x.book == b['p_book'] && x.event['id'] == e['id'])) continue;
        rows.add((seq: rows.length + 1, book: b['p_book'], event: e));
        n++;
      }
      return http.Response('$n', 200);
    }
    final mine = rows.where((x) => x.book == b['p_book'] && x.seq > b['p_after']).toList();
    return http.Response.bytes(
        utf8.encode(jsonEncode({'seq': mine.isEmpty ? b['p_after'] : mine.last.seq, 'events': [for (final x in mine) x.event]})),
        200);
  });
}

Future<(Store, String)> phone(String pin) async {
  final s = await Store.load();
  return (s, await s.create('ذنون', pin));
}

Map<String, dynamic> buy(String shop, int n) => {'t': 'buy', 'shop': shop, 'amount': n, 'date': today(), 'note': ''};
Map<String, dynamic> pay(String shop, int n) => {'t': 'pay', 'shop': shop, 'amount': n, 'date': today(), 'note': ''};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('amounts accept Arabic digits and commas', () {
    expect(parseAmount('١٥٬٠٠٠'), 15000);
    expect(parseAmount('15,000'), 15000);
    expect(parseAmount('0'), null);
    expect(parseAmount('abc'), null);
    expect(iqd(1234567), '1,234,567');
    expect(parseSyncCode(showSyncCode('0123456789abcdef0123456789abcdef')), '0123456789abcdef0123456789abcdef');
  });

  test('paying a shop off archives it and keeps overpayment as credit', () async {
    final (s, k) = await phone('111111');
    await s.record(k, buy('d0', 10000));
    await s.record(k, buy('d0', 5000));
    var b = await s.record(k, pay('d0', 4000));
    expect(b.shopBalance('d0'), 11000);
    expect(b.total, 11000);
    b = await s.record(k, pay('d0', 12000));
    expect(b.archive.single.bought, 15000);
    expect(b.archive.single.paid, 16000);
    expect(b.shopBalance('d0'), -1000);
    expect(b.total, 0);
    b = await s.record(k, buy('d0', 3000)); // the credit is used up by the next purchase
    expect(b.shopBalance('d0'), 2000);
  });

  test('offline changes wait in the queue and upload when the internet is back', () async {
    final server = FakeServer()..online = false;
    final (s, k) = await phone('111111');
    await s.record(k, buy('d1', 7000));
    await expectLater(syncBook(s, k, client: server.client), throwsA(isA<http.ClientException>()));
    expect(s.saved(k)!.pending.length, 6); // book + 4 shops + the purchase
    server.online = true;
    await syncBook(s, k, client: server.client);
    expect(s.saved(k)!.pending, isEmpty);
    expect(server.rows.length, 6);
    await syncBook(s, k, client: server.client); // nothing sent twice
    expect(server.rows.length, 6);
  });

  test('a second phone with the book code gets the same book, both ways', () async {
    final server = FakeServer();
    final (a, ka) = await phone('111111');
    await a.record(ka, buy('d2', 9000));
    await syncBook(a, ka, client: server.client);

    final (b, kb) = await phone('222222');
    await b.join(kb, a.saved(ka)!.sync);
    await syncBook(b, kb, client: server.client);
    expect(b.book(kb).shopBalance('d2'), 9000);
    expect(b.book(kb).shops.length, 4); // default shops are not doubled

    await b.record(kb, pay('d2', 9000));
    await syncBook(b, kb, client: server.client);
    expect(await syncBook(a, ka, client: server.client), true);
    expect(a.book(ka).shopBalance('d2'), 0);
    expect(a.book(ka).archive.single.id, b.book(kb).archive.single.id);
  });

  test('a version 1 book is turned into events and queued', () async {
    SharedPreferences.setMockInitialValues({
      'debts_db': jsonEncode({
        'salt': 'x',
        'tries': {'n': 0},
        'books': {
          'k': {
            'name': 'قديم',
            'shops': [{'id': 's1', 'name': 'دكان'}],
            'entries': [{'id': 'e2', 'shop': 's1', 'kind': 'buy', 'amount': 500, 'date': '2026-10-02', 'note': '', 'created': '2026-10-02 10:00:00'}],
            'archive': [{'id': 'a', 'shop': 's1', 'shop_name': 'دكان', 'from': '2026-10-01', 'to': '2026-10-01', 'closed': '2026-10-01', 'bought': 100, 'paid': 100, 'entries': [
              {'id': 'e0', 'shop': 's1', 'kind': 'buy', 'amount': 100, 'date': '2026-10-01', 'note': '', 'created': '2026-10-01 09:00:00'},
              {'id': 'e1', 'shop': 's1', 'kind': 'pay', 'amount': 100, 'date': '2026-10-01', 'note': '', 'created': '2026-10-01 09:30:00'},
            ]}],
          }
        }
      })
    });
    final s = await Store.load();
    final b = s.book('k');
    expect(b.name, 'قديم');
    expect(b.shopBalance('s1'), 500);
    expect(b.archive.length, 1);
    expect(s.saved('k')!.pending.length, 5);
  });

  testWidgets('first launch creates a book, then the PIN opens it', (t) async {
    final store = await Store.load();
    final server = FakeServer()..online = false;
    await t.pumpWidget(DebtsApp(store: store, sync: (s, k) => syncBook(s, k, client: server.client)));
    expect(find.text('دفتر جديد'), findsOneWidget);
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'ذنون');
    await t.enterText(fields.at(1), '123456');
    await t.enterText(fields.at(2), '123456');
    await t.tap(find.text('إنشاء وفتح'));
    await t.pumpAndSettle();
    expect(find.text('📒 ذنون'), findsOneWidget);
    expect(find.text('⏳ 5'), findsOneWidget); // offline: the new book waits in the queue
    await t.tap(find.text('🔒 قفل'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '000000');
    await t.tap(find.text('فتح'));
    await t.pumpAndSettle();
    expect(find.textContaining('الرمز غلط'), findsOneWidget);
    server.online = true;
    await t.enterText(find.byType(TextField).first, '123456');
    await t.tap(find.text('فتح'));
    await t.pumpAndSettle();
    expect(find.text('☁️ ✔'), findsOneWidget); // back online: uploaded
    expect(server.rows.length, 5);
    await t.pumpWidget(const SizedBox()); // stop the sync timer
  });
}
