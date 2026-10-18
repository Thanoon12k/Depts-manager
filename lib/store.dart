// The debts book (دفتر الدين): purchases on credit per shop, payments, and an archive.
//
// Each shop has an open account: purchases add to the debt, payments subtract. When a
// payment brings a shop's balance to zero (or below), its open entries move to the archive
// as one closed account; any overpayment carries into the new account as credit.
//
// Each 6-digit PIN opens its own book, so several people can keep separate books on one
// phone. Everything is stored on the phone (shared_preferences), nothing goes online.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultShops = ['دكان أحمد أنس', 'دكان ابن هذال', 'دكان عمار (مخضر)', 'مول حبش'];
const maxTries = 5;
const lockMinutes = 15;

const _dbKey = 'debts_db';
final _rand = Random.secure();

String newId() => List.generate(8, (_) => _rand.nextInt(16).toRadixString(16)).join();

String two(int n) => n.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String today() => ymd(DateTime.now());
String now() {
  final d = DateTime.now();
  return '${ymd(d)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
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
  Entry({required this.id, required this.shop, required this.kind, required this.amount,
      required this.date, required this.note, required this.created});
  bool get isBuy => kind == 'buy';

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
      id: j['id'], shop: j['shop'], kind: j['kind'], amount: j['amount'],
      date: j['date'], note: j['note'] ?? '', created: j['created'] ?? '');
  Map<String, dynamic> toJson() => {'id': id, 'shop': shop, 'kind': kind, 'amount': amount,
      'date': date, 'note': note, 'created': created};
}

class Shop {
  final String id;
  String name;
  Shop(this.id, this.name);
  factory Shop.fromJson(Map<String, dynamic> j) => Shop(j['id'], j['name']);
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class Closed {
  final String id, shop, shopName, from, to, closed;
  final int bought, paid;
  final List<Entry> entries;
  Closed({required this.id, required this.shop, required this.shopName, required this.from,
      required this.to, required this.closed, required this.bought, required this.paid,
      required this.entries});

  factory Closed.fromJson(Map<String, dynamic> j) => Closed(
      id: j['id'], shop: j['shop'], shopName: j['shop_name'], from: j['from'], to: j['to'],
      closed: j['closed'], bought: j['bought'], paid: j['paid'],
      entries: [for (final e in j['entries']) Entry.fromJson(e)]);
  Map<String, dynamic> toJson() => {'id': id, 'shop': shop, 'shop_name': shopName,
      'from': from, 'to': to, 'closed': closed, 'bought': bought, 'paid': paid,
      'entries': [for (final e in entries) e.toJson()]};
}

int balance(Iterable<Entry> entries) =>
    entries.fold(0, (s, e) => s + (e.isBuy ? e.amount : -e.amount));

int _byDate(Entry a, Entry b) {
  final c = a.date.compareTo(b.date);
  return c != 0 ? c : a.created.compareTo(b.created);
}

class Book {
  String name;
  final List<Shop> shops;
  final List<Entry> entries;
  final List<Closed> archive;
  Book(this.name, this.shops, this.entries, this.archive);

  factory Book.create(String name) =>
      Book(name, [for (final n in defaultShops) Shop(newId(), n)], [], []);
  factory Book.fromJson(Map<String, dynamic> j) => Book(
      j['name'] ?? '',
      [for (final s in j['shops']) Shop.fromJson(s)],
      [for (final e in j['entries']) Entry.fromJson(e)],
      [for (final a in j['archive']) Closed.fromJson(a)]);
  Map<String, dynamic> toJson() => {'name': name,
      'shops': [for (final s in shops) s.toJson()],
      'entries': [for (final e in entries) e.toJson()],
      'archive': [for (final a in archive) a.toJson()]};

  /// The shop's open entries, newest first.
  List<Entry> openEntries(String shopId) =>
      entries.where((e) => e.shop == shopId).toList()..sort((a, b) => _byDate(b, a));

  int shopBalance(String shopId) => balance(entries.where((e) => e.shop == shopId));

  /// What I owe in total right now (credits at a shop don't lower another shop's debt).
  int get total => shops.fold(0, (s, sh) => s + max(shopBalance(sh.id), 0));

  /// Adds a purchase or a payment. Returns true when the payment paid the shop off.
  bool add(Shop shop, String kind, int amount, String date, String note) {
    entries.add(Entry(id: newId(), shop: shop.id, kind: kind == 'buy' ? 'buy' : 'pay',
        amount: amount, date: date, note: note, created: now()));
    return kind != 'buy' && _settleIfZero(shop);
  }

  /// Archives the shop's open account once it is paid off; keeps any overpayment as credit.
  bool _settleIfZero(Shop shop) {
    final items = openEntries(shop.id)..sort(_byDate);
    final bal = balance(items);
    if (items.isEmpty || bal > 0 || !items.any((e) => e.isBuy)) return false;
    archive.insert(0, Closed(
        id: newId(), shop: shop.id, shopName: shop.name, from: items.first.date,
        to: items.last.date, closed: today(),
        bought: items.where((e) => e.isBuy).fold(0, (s, e) => s + e.amount),
        paid: items.where((e) => !e.isBuy).fold(0, (s, e) => s + e.amount),
        entries: items));
    entries.removeWhere((e) => e.shop == shop.id);
    if (bal < 0) {
      entries.add(Entry(id: newId(), shop: shop.id, kind: 'pay', amount: -bal, date: today(),
          note: 'رصيد زايد من الحساب السابق', created: now()));
    }
    return true;
  }
}

/// All books on this phone, keyed by a hash of their PIN, plus the wrong-PIN counter.
class Store {
  final SharedPreferences _p;
  final Map<String, dynamic> _db;
  Store._(this._p, this._db);

  static Future<Store> load() async {
    final p = await SharedPreferences.getInstance();
    Map<String, dynamic> db;
    try {
      db = jsonDecode(p.getString(_dbKey) ?? '{}');
    } catch (_) {
      db = {};
    }
    db.putIfAbsent('salt', () => List.generate(16, (_) => newId()).join());
    db.putIfAbsent('books', () => <String, dynamic>{});
    db.putIfAbsent('tries', () => <String, dynamic>{'n': 0});
    return Store._(p, db);
  }

  Map<String, dynamic> get _books => _db['books'];
  Map<String, dynamic> get _tries => _db['tries'];
  bool get hasBooks => _books.isNotEmpty;

  String pinKey(String pin) => sha256.convert(utf8.encode('${_db['salt']}:$pin')).toString();

  Future<void> _save() => _p.setString(_dbKey, jsonEncode(_db));

  Future<void> saveBook(String key, Book b) {
    _books[key] = b.toJson();
    return _save();
  }

  Book? book(String key) => _books[key] == null ? null : Book.fromJson(_books[key]);
  bool taken(String pin) => _books.containsKey(pinKey(pin));

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
    await _save();
    return left;
  }

  Future<void> clearTries() {
    _db['tries'] = <String, dynamic>{'n': 0};
    return _save();
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
    await saveBook(key, Book.create(name));
    return key;
  }

  /// Moves the book to a new PIN; returns its new key.
  Future<String> changePin(String oldKey, String newPin) async {
    final key = pinKey(newPin);
    _books[key] = _books.remove(oldKey);
    await _save();
    return key;
  }
}
