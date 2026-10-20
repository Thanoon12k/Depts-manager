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

/// A phone with its own storage and the book of [pin].
Future<(Store, String)> phone(String pin) async {
  SharedPreferences.setMockInitialValues({});
  final s = await Store.load();
  return (s, await s.create(pin));
}

Map<String, dynamic> buy(String shop, int n) => {'t': 'buy', 'shop': shop, 'amount': n, 'date': today(), 'note': ''};
Map<String, dynamic> pay(String shop, int n) => {'t': 'pay', 'shop': shop, 'amount': n, 'date': today(), 'note': ''};

/// The app wired to [server] instead of the internet.
DebtsApp app(Store store, FakeServer server) => DebtsApp(
      store: store,
      sync: (s, k, {only}) => syncBook(s, k, only: only, client: server.client),
      exists: (code) => bookExists(code, client: server.client),
    );

Future<void> openPin(WidgetTester t, String pin) async {
  await t.enterText(find.byType(TextField).first, pin);
  await t.tap(find.text('فتح'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('amounts accept Arabic digits and commas', () {
    expect(parseAmount('١٥٬٠٠٠'), 15000);
    expect(parseAmount('15,000'), 15000);
    expect(parseAmount('0'), null);
    expect(parseAmount('abc'), null);
    expect(iqd(1234567), '1,234,567');
    expect(validPin('١٢٣٤٥٦'), false); // the lock page turns Arabic digits to Latin first
    expect(validPin(latinDigits('١٢٣٤٥٦')), true);
    expect(validPin('1234'), false);
    expect(syncCodeFor('1234'), syncCodeFor('1234'));
    expect(syncCodeFor('1234'), isNot(syncCodeFor('4321')));
  });

  test('paying a shop off archives it and keeps overpayment as credit', () async {
    final (s, k) = await phone('1111');
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
    final (s, k) = await phone('1111');
    await s.record(k, buy('d1', 7000));
    await expectLater(syncBook(s, k, client: server.client), throwsA(isA<http.ClientException>()));
    expect(s.saved(k)!.pending.length, 5); // 4 shops + the purchase
    server.online = true;
    await syncBook(s, k, client: server.client);
    expect(s.saved(k)!.pending, isEmpty);
    expect(server.rows.length, 5);
    await syncBook(s, k, client: server.client); // nothing sent twice
    expect(server.rows.length, 5);
  });

  test('a second phone with the same PIN gets the same book, both ways', () async {
    final server = FakeServer();
    final (a, ka) = await phone('1111');
    await a.record(ka, buy('d2', 9000));
    await a.record(ka, {'t': 'shop', 'shop': 'd0', 'name': 'أبو علي'});
    await syncBook(a, ka, client: server.client);

    final (b, kb) = await phone('1111');
    expect(b.saved(kb)!.sync, a.saved(ka)!.sync);
    await syncBook(b, kb, client: server.client);
    expect(server.rows.length, 6); // the default shops are stored once
    expect(b.book(kb).shopBalance('d2'), 9000);
    expect(b.book(kb).shops.length, 4);
    expect(b.book(kb).shops.firstWhere((s) => s.id == 'd0').name, 'أبو علي'); // the rename wins

    await b.record(kb, pay('d2', 9000));
    await syncBook(b, kb, client: server.client);
    expect(await syncBook(a, ka, client: server.client), true);
    expect(a.book(ka).shopBalance('d2'), 0);
    expect(a.book(ka).archive.single.id, b.book(kb).archive.single.id);

    final (c, kc) = await phone('2222'); // another PIN is another book
    await syncBook(c, kc, client: server.client);
    expect(c.book(kc).shopBalance('d2'), 0);
    expect(c.book(kc).archive, isEmpty);
  });

  test('a book from an older version moves to its PIN code when opened', () async {
    final server = FakeServer();
    final (a, ka) = await phone('123456');
    a.saved(ka)!.sync = '0123456789abcdef0123456789abcdef'; // the random code older versions made
    await a.record(ka, buy('d1', 4000));
    expect(await a.unlock('123456'), ka);
    expect(a.saved(ka)!.sync, syncCodeFor('123456'));
    await syncBook(a, ka, client: server.client);
    expect(await bookExists(syncCodeFor('123456'), client: server.client), true);
  });

  test('one queued operation can be uploaded on its own', () async {
    final server = FakeServer();
    final (s, k) = await phone('1111');
    await s.record(k, buy('d1', 7000));
    final last = s.saved(k)!.queue.firstWhere((e) => e['t'] == 'buy');
    await syncBook(s, k, only: {last['id']}, client: server.client);
    expect(server.rows.single.event['amount'], 7000);
    expect(s.saved(k)!.pending.length, 4);
    await syncBook(s, k, only: {}, client: server.client); // download only
    expect(s.saved(k)!.pending.length, 4);
  });

  testWidgets('manual mode: operations stay queued until pushed from the pending list', (t) async {
    t.view.physicalSize = const Size(1080, 2400); // a phone screen, so the whole list shows
    addTearDown(t.view.reset);
    final server = FakeServer();
    final (store, key) = await phone('123456');
    store.saved(key)!.auto = false;
    await store.record(key, buy('d0', 2500));
    await t.pumpWidget(app(store, server));
    await openPin(t, '123456');
    expect(server.rows, isEmpty); // nothing went up by itself
    await t.tap(find.text('⏳ 5'));
    await t.pumpAndSettle();
    expect(find.text('⏳ العمليات المعلقة (5)'), findsOneWidget);
    await t.scrollUntilVisible(find.textContaining('🛒 مسواك 2,500 د.ع · دكان أحمد أنس'), 200);
    expect(find.textContaining('🛒 مسواك 2,500 د.ع · دكان أحمد أنس'), findsOneWidget);
    await t.tap(find.text('⬆ ارفع').first);
    await t.pumpAndSettle();
    expect(server.rows.length, 1);
    expect(find.text('⏳ العمليات المعلقة (4)'), findsOneWidget);
    await t.tap(find.text('⬆ ارفع الكل (4)'));
    await t.pumpAndSettle();
    expect(server.rows.length, 5);
    expect(find.textContaining('ماكو شي معلق'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
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

  testWidgets('a new PIN asks before making a book; the same PIN on another phone opens it', (t) async {
    final server = FakeServer();
    await t.pumpWidget(app(await Store.load(), server));
    await openPin(t, '12');
    expect(find.text('الرمز 6 أرقام'), findsOneWidget);
    await openPin(t, '٤٤٤٤٤٤'); // Arabic digits work too
    expect(find.textContaining('ماكو دفتر بهذا الرمز'), findsOneWidget);
    await t.tap(find.text('نعم'));
    await t.pumpAndSettle();
    expect(find.text('مجموع اللي علي هسه'), findsOneWidget);
    expect(find.text('☁️ ✔'), findsOneWidget); // uploaded right away
    await t.pumpWidget(const SizedBox()); // stop the sync timer

    SharedPreferences.setMockInitialValues({}); // another phone
    await t.pumpWidget(app(await Store.load(), server));
    await openPin(t, '444444');
    expect(find.textContaining('ماكو دفتر'), findsNothing); // found on the server: opens directly
    expect(find.text('مجموع اللي علي هسه'), findsOneWidget);
    expect(server.rows.length, 4); // still one copy of the book
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('offline, a new PIN still opens after asking, and its changes wait', (t) async {
    final server = FakeServer()..online = false;
    await t.pumpWidget(app(await Store.load(), server));
    await openPin(t, '123456');
    expect(find.textContaining('ماكو إنترنت حتى أدور'), findsOneWidget);
    await t.tap(find.text('نعم'));
    await t.pumpAndSettle();
    expect(find.text('⏳ 4'), findsOneWidget);
    await t.tap(find.text('🔒 قفل'));
    await t.pumpAndSettle();
    server.online = true;
    await openPin(t, '123456'); // on this phone now: no question
    expect(find.text('☁️ ✔'), findsOneWidget);
    expect(server.rows.length, 4);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a 4-digit book from version 1.5 still opens on another phone; no new ones', (t) async {
    final server = FakeServer();
    final (a, ka) = await phone('4321'); // made by version 1.5
    await a.record(ka, buy('d1', 3000));
    await syncBook(a, ka, client: server.client);

    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(app(await Store.load(), server));
    await openPin(t, '9999'); // not on the server: 4 digits can't start a book
    expect(find.text('الرمز 6 أرقام'), findsOneWidget);
    await openPin(t, '4321');
    expect(find.text('مجموع اللي علي هسه'), findsOneWidget);
    expect(find.textContaining('3,000', findRichText: true), findsWidgets); // its purchase came down
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the app opens even when a saved book is unreadable', (t) async {
    SharedPreferences.setMockInitialValues({
      'debts_db': jsonEncode({'salt': 'x', 'books': {'bad': {'events': 'nonsense'}}})
    });
    await t.pumpWidget(const Boot());
    expect(find.text('دفتر الدين'), findsOneWidget); // the splash, not an empty screen
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(find.text('الرمز (6 أرقام)'), findsOneWidget);
  });
}
