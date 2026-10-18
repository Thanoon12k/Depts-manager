// Uploads a book's queued events and downloads the ones made on other phones.
// The server keeps each book as an append-only event log addressed by its sync code
// (Supabase RPCs debts_push / debts_pull). With no internet the events just stay queued.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'store.dart';

const _api = 'https://axncazensmjdqpczvzwf.supabase.co/rest/v1/rpc';
const _key = 'sb_publishable_7hGIGHFa1mcWPMI8mEZKGw_-wgkkSYT';
const _timeout = Duration(seconds: 15);

Future<dynamic> _call(http.Client c, String fn, Map<String, dynamic> body) async {
  final r = await c
      .post(Uri.parse('$_api/$fn'),
          headers: {'apikey': _key, 'authorization': 'Bearer $_key', 'content-type': 'application/json'},
          body: jsonEncode(body))
      .timeout(_timeout);
  if (r.statusCode != 200) throw http.ClientException('${r.statusCode} ${r.body}');
  return jsonDecode(utf8.decode(r.bodyBytes));
}

bool _wellFormed(dynamic e) =>
    e is Map && e['id'] is String && e['at'] is String && e['t'] is String;

/// One round: upload what's queued, then download what's new. Returns whether the book
/// changed from downloaded events. Throws when offline; the queue is then left as it was.
Future<bool> syncBook(Store store, String key, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    return await _round(c, store, key);
  } finally {
    if (client == null) c.close();
  }
}

Future<bool> _round(http.Client c, Store store, String key) async {
  final s = store.saved(key)!;
  final queued = s.events.where((e) => s.pending.contains(e['id'])).toList();
  for (var i = 0; i < queued.length; i += 200) {
    final part = queued.sublist(i, i + 200 > queued.length ? queued.length : i + 200);
    await _call(c, 'debts_push', {'p_book': s.sync, 'p_events': part});
    s.pending.removeAll([for (final e in part) e['id']]);
    await store.save();
  }
  var changed = false;
  while (true) {
    final r = await _call(c, 'debts_pull', {'p_book': s.sync, 'p_after': s.after}) as Map;
    final events = [for (final e in r['events'] as List) if (_wellFormed(e)) Map<String, dynamic>.from(e)];
    changed = store.merge(key, events) || changed;
    s.after = r['seq'] as int;
    await store.save();
    if ((r['events'] as List).length < 1000) return changed;
  }
}
