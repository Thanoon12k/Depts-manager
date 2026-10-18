// The debts book (دفتر الدين): purchases on credit per shop, payments, and an archive.
//
// Each shop has an open account: purchases add to the debt, payments subtract. When a
// payment brings a shop's balance to zero (or below), its open entries move to the archive
// as one closed account; any overpayment carries into the new account as credit.
//
// A book is a log of change events; the shops, balances and archive are rebuilt by replaying
// it in time order. New events wait in a queue on the phone and are uploaded whenever there is
// internet (see sync.dart), so the same book can be kept on several phones.
//
// Each 6-digit PIN opens its own book on this phone, so several people can keep separate books.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultShops = ['دكان أحمد أنس', 'دكان ابن هذال', 'دكان عمار (مخضر)', 'مول حبش'];
const creditNote = 'رصيد زايد من الحساب السابق';
const maxTries = 5;
const lockMinutes = 15;

const _dbKey = 'debts_db';
final _rand = Random.secure();

String hex(int chars) => List.generate(chars, (_) => _rand.nextInt(16).toRadixString(16)).join();
String newId() => hex(16);

String two(int n) => n.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String today() => ymd(DateTime.now());
String now() {
  final d = DateTime.now();
  return '${ymd(d)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}.${d.millisecond.toString().padLeft(3, '0')}';
}

/// Arabic and Persian digits to Latin ones.
String latinDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩', fa = '۰۱۲۳۴۵۶۷۸۹';
  return s.split('').map((c) {
    final i = ar.contains(c) ? ar.indexOf(c) : fa.indexOf(c);
    return i >= 0 ? '$i' : c;
  }).join();
}

int? parseAmount(String raw) {
  final t = latinDigits(raw).replaceAll(RegExp(r'[,٬\s]'), '');
  if (!RegExp(r'^\d{1,10}$').hasMatch(t)) return null;
  final n = int.parse(t);
  return n > 0 && n < 10000000000 ? n : null;
}

bool validPin(String p) => RegExp(r'^\d{6}$').hasMatch(p);

/// A sync code as typed by a person: 32 hex characters, spaces and dashes ignored.
String? parseSyncCode(String raw) {
  final t = latinDigits(raw).toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^[0-9a-f]{32}$').hasMatch(t) ? t : null;
}

/// "0123456789abcdef..." -> "0123-4567-89ab-..."
String showSyncCode(String c) => [for (var i = 0; i < c.length; i += 4) c.substring(i, min(i + 4, c.length))].join('-');

/// 1234567 -> "1,234,567"
String iqd(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class Entry {
  final String id, shop, kind, date, note, created; // kind: buy | pay
  final int amount;
  Entry({
    required this.id,
    required this.shop,
    required this.kind,
    required this.amount,
    required this.date,
    required this.note,
    required this.created,
  });
  bool get isBuy => kind == 'buy';
}

class Shop {
  final String id;
  String name;
  Shop(this.id, this.name);
}

class Closed {
  final String id, shop, shopName, from, to, closed;
  final int bought, paid;
  final List<Entry> entries;
  Closed({
    required this.id,
    required this.shop,
    required this.shopName,
    required this.from,
    required this.to,
    required this.closed,
    required this.bought,
    required this.paid,
    required this.entries,
  });
}

int balance(Iterable<Entry> entries) => entries.fold(0, (s, e) => s + (e.isBuy ? e.amount : -e.amount));

int _byDate(Entry a, Entry b) {
  final c = a.date.compareTo(b.date);
  return c != 0 ? c : a.created.compareTo(b.created);
}

/// Events in replay order: by time, then id, so every phone rebuilds the same book.
int byTime(Map a, Map b) {
  final c = (a['at'] as String).compareTo(b['at']);
  return c != 0 ? c : (a['id'] as String).compareTo(b['id']);
}

/// The events that start a new book. Default shops get fixed ids, so two phones joining
/// the same book don't end up with each shop twice.
List<Map<String, dynamic>> startEvents(String name) {
  final at = now();
  return [
    {'id': newId(), 'at': at, 't': 'book', 'name': name},
    for (var i = 0; i < defaultShops.length; i++)
      {'id': newId(), 'at': at, 't': 'shop', 'shop': 'd$i', 'name': defaultShops[i]},
  ];
}

/// The state of a book: what its events add up to.
class Book {
  String name = '';
  final List<Shop> shops = [];
  final List<Entry> entries = [];
  final List<Closed> archive = []; // newest first

  Book.replay(Iterable<Map<String, dynamic>> events) {
    final names = <String, String>{}; // last known name of every shop, removed ones too
    for (final e in [...events]..sort(byTime)) {
      try {
        _apply(e, names);
      } on TypeError {
        // a malformed event (e.g. from a newer app version): skip it
      }
    }
  }

  void _apply(Map<String, dynamic> e, Map<String, String> names) {
    final shopId = e['shop'] as String?;
    Shop? shop = shops.where((s) => s.id == shopId).firstOrNull;
    switch (e['t']) {
      case 'book':
        name = e['name'];
      case 'shop':
        names[shopId!] = e['name'];
        shop == null ? shops.add(Shop(shopId, e['name'])) : shop.name = e['name'];
      case 'unshop':
        if (shop != null && openEntries(shop.id).isEmpty) shops.remove(shop);
      case 'del':
        entries.removeWhere((x) => x.id == e['entry']);
      case 'buy' || 'pay':
        if (shop == null) {
          // removed on another phone meanwhile: bring it back
          shop = Shop(shopId!, names[shopId] ?? '؟');
          shops.add(shop);
        }
        entries.add(
          Entry(
            id: e['id'],
            shop: shop.id,
            kind: e['t'],
            amount: e['amount'],
            date: e['date'],
            note: e['note'] ?? '',
            created: e['at'],
          ),
        );
        if (e['t'] == 'pay') _settleIfZero(shop, e);
    }
  }

  /// The shop's open entries, newest first.
  List<Entry> openEntries(String shopId) =>
      entries.where((e) => e.shop == shopId).toList()..sort((a, b) => _byDate(b, a));

  int shopBalance(String shopId) => balance(entries.where((e) => e.shop == shopId));

  /// What I owe in total right now (credits at a shop don't lower another shop's debt).
  int get total => shops.fold(0, (s, sh) => s + max(shopBalance(sh.id), 0));

  /// Archives the shop's open account once it is paid off; keeps any overpayment as credit.
  void _settleIfZero(Shop shop, Map<String, dynamic> e) {
    final items = openEntries(shop.id)..sort(_byDate);
    final bal = balance(items);
    if (items.isEmpty || bal > 0 || !items.any((x) => x.isBuy)) return;
    final day = (e['at'] as String).substring(0, 10);
    archive.insert(
      0,
      Closed(
        id: 'a${e['id']}',
        shop: shop.id,
        shopName: shop.name,
        from: items.first.date,
        to: items.last.date,
        closed: day,
        bought: items.where((x) => x.isBuy).fold(0, (s, x) => s + x.amount),
        paid: items.where((x) => !x.isBuy).fold(0, (s, x) => s + x.amount),
        entries: items,
      ),
    );
    entries.removeWhere((x) => x.shop == shop.id);
    if (bal < 0) {
      entries.add(
        Entry(
          id: 'c${e['id']}',
          shop: shop.id,
          kind: 'pay',
          amount: -bal,
          date: day,
          note: creditNote,
          created: e['at'],
        ),
      );
    }
  }
}

/// A book on this phone: its event log, the events not uploaded yet, and where the last
/// download stopped.
class Saved {
  String sync; // the book's code on the server; the same code on two phones = the same book
  final List<Map<String, dynamic>> events;
  final Set<String> pending;
  int after;
  bool auto = true; // false: queued events go up only when the person pushes them
  Saved(this.sync, this.events, this.pending, this.after);

  /// The queued events, oldest first.
  List<Map<String, dynamic>> get queue => events.where((e) => pending.contains(e['id'])).toList()..sort(byTime);

  factory Saved.fromJson(Map<String, dynamic> j) {
    if (j['events'] == null) return Saved._fromV1(j);
    return Saved(
      j['sync'],
      [for (final e in j['events']) Map<String, dynamic>.from(e)],
      {...(j['pending'] as List).cast<String>()},
      j['after'] ?? 0,
    )..auto = j['auto'] ?? true;
  }
  Map<String, dynamic> toJson() => {
    'sync': sync,
    'events': events,
    'pending': [...pending],
    'after': after,
    'auto': auto,
  };

  /// A book saved by version 1 (plain shops/entries/archive): turned into events, all queued.
  factory Saved._fromV1(Map<String, dynamic> j) {
    const at = '0000-00-00 00:00:00.000';
    final ev = <Map<String, dynamic>>[
      {'id': newId(), 'at': at, 't': 'book', 'name': j['name'] ?? ''},
      for (final s in j['shops'] ?? []) {'id': newId(), 'at': at, 't': 'shop', 'shop': s['id'], 'name': s['name']},
    ];
    final old = [for (final a in j['archive'] ?? []) ...a['entries'], ...j['entries'] ?? []];
    for (final x in old) {
      if (x['note'] == creditNote) continue; // replay makes these again
      ev.add({
        'id': newId(),
        'at': '${x['created']}.000',
        't': x['kind'],
        'shop': x['shop'],
        'amount': x['amount'],
        'date': x['date'],
        'note': x['note'] ?? '',
      });
    }
    return Saved(hex(32), ev, {for (final e in ev) e['id']}, 0);
  }
}

/// All books on this phone, keyed by a hash of their PIN, plus the wrong-PIN counter.
class Store {
  final SharedPreferences _p;
  final Map<String, dynamic> _db;
  final Map<String, Saved> _books = {};
  Store._(this._p, this._db) {
    (_db['books'] as Map<String, dynamic>).forEach((k, v) => _books[k] = Saved.fromJson(v));
  }

  static Future<Store> load() async {
    final p = await SharedPreferences.getInstance();
    Map<String, dynamic> db;
    try {
      db = jsonDecode(p.getString(_dbKey) ?? '{}');
    } catch (_) {
      db = {};
    }
    db.putIfAbsent('salt', () => hex(32));
    db.putIfAbsent('books', () => <String, dynamic>{});
    db.putIfAbsent('tries', () => <String, dynamic>{'n': 0});
    return Store._(p, db);
  }

  Map<String, dynamic> get _tries => _db['tries'];
  bool get hasBooks => _books.isNotEmpty;

  String pinKey(String pin) => sha256.convert(utf8.encode('${_db['salt']}:$pin')).toString();

  Future<void> save() {
    _db['books'] = {for (final e in _books.entries) e.key: e.value.toJson()};
    return _p.setString(_dbKey, jsonEncode(_db));
  }

  Saved? saved(String key) => _books[key];
  Book book(String key) => Book.replay(_books[key]!.events);
  bool taken(String pin) => _books.containsKey(pinKey(pin));

  /// Records a change in the book (and queues it for upload); returns the new state.
  Future<Book> record(String key, Map<String, dynamic> event) async {
    final s = _books[key]!;
    final e = {'id': newId(), 'at': now(), ...event};
    s.events.add(e);
    s.pending.add(e['id']);
    await save();
    return book(key);
  }

  /// Adds events downloaded from the server; returns whether any were new.
  bool merge(String key, Iterable<Map<String, dynamic>> events) {
    final s = _books[key]!;
    final have = {for (final e in s.events) e['id']};
    final fresh = events.where((e) => have.add(e['id'])).toList();
    s.events.addAll(fresh);
    return fresh.isNotEmpty;
  }

  /// Points this book at another phone's book: everything here is uploaded into it.
  Future<void> join(String key, String code) {
    final s = _books[key]!;
    s.sync = code;
    s.after = 0;
    s.pending.addAll([for (final e in s.events) e['id']]);
    return save();
  }

  /// Seconds left before PINs may be tried again (0 = not locked).
  int lockedFor() {
    final until = (_tries['until'] ?? 0) as int;
    return max(((until - DateTime.now().millisecondsSinceEpoch) / 1000).ceil(), 0);
  }

  /// Counts a wrong PIN (or a taken one at sign-up); returns tries left (0 = now locked).
  Future<int> failed() async {
    final t = DateTime.now().millisecondsSinceEpoch;
    if ((_tries['last'] ?? 0) < t - lockMinutes * 60000) _tries['n'] = 0;
    _tries['n'] = (_tries['n'] ?? 0) + 1;
    _tries['last'] = t;
    var left = maxTries - (_tries['n'] as int);
    if (left <= 0) {
      _tries['n'] = 0;
      _tries['until'] = t + lockMinutes * 60000;
      left = 0;
    }
    await save();
    return left;
  }

  Future<void> clearTries() {
    _db['tries'] = <String, dynamic>{'n': 0};
    return save();
  }

  /// Opens the book of [pin], or null.
  Future<String?> unlock(String pin) async {
    final key = pinKey(pin);
    if (!_books.containsKey(key)) return null;
    await clearTries();
    return key;
  }

  Future<String> create(String name, String pin) async {
    final key = pinKey(pin);
    final ev = startEvents(name);
    _books[key] = Saved(hex(32), ev, {for (final e in ev) e['id']}, 0);
    await save();
    return key;
  }

  /// Moves the book to a new PIN; returns its new key.
  Future<String> changePin(String oldKey, String newPin) async {
    final key = pinKey(newPin);
    _books[key] = _books.remove(oldKey)!;
    await save();
    return key;
  }
}
