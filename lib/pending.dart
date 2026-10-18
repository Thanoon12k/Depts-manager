import 'package:flutter/material.dart';

import 'store.dart';
import 'theme.dart';

/// The queued operations of a book, oldest first, each with its own upload button.
class PendingPage extends StatefulWidget {
  final Store store;
  final String bookKey;
  /// Uploads the given events (null = all queued); returns an error message or null.
  final Future<String?> Function(Set<String>? only) push;
  const PendingPage({super.key, required this.store, required this.bookKey, required this.push});
  @override
  State<PendingPage> createState() => _PendingPageState();
}

class _PendingPageState extends State<PendingPage> {
  final _busy = <String>{}; // ids being uploaded; '*' = all
  String? _error;

  Future<void> _push(Set<String>? only) async {
    final tag = only ?? {'*'};
    setState(() {
      _busy.addAll(tag);
      _error = null;
    });
    final err = await widget.push(only);
    if (!mounted) return;
    setState(() {
      _busy.removeAll(tag);
      _error = err;
    });
  }

  /// One line saying what the operation does, e.g. "🛒 مسواك 7,000 · دكان ابن هذال · غاز".
  String describe(Map<String, dynamic> e, Saved s, Book b) {
    String shop(String? id) => b.shops.where((x) => x.id == id).firstOrNull?.name ?? 'دكان';
    String money(Map<String, dynamic> x) {
      final note = (x['note'] ?? '') as String;
      return '${iqd(x['amount'] as int)} د.ع · ${shop(x['shop'])}${note.isEmpty ? '' : ' · $note'}';
    }
    switch (e['t']) {
      case 'book':
        return '📒 اسم الدفتر: ${e['name']}';
      case 'shop':
        return '🏪 دكان: ${e['name']}';
      case 'unshop':
        return '🗑 حذف دكان: ${shop(e['shop'])}';
      case 'buy':
        return '🛒 مسواك ${money(e)}';
      case 'pay':
        return '💵 تسديد ${money(e)}';
      case 'del':
        final x = s.events.where((x) => x['id'] == e['entry']).firstOrNull;
        return x == null ? '✕ حذف تسجيل' : '✕ حذف ${x['t'] == 'buy' ? 'مسواك' : 'تسديد'} ${money(x)}';
    }
    return '${e['t']}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store.saved(widget.bookKey)!;
    final b = widget.store.book(widget.bookKey);
    final queue = s.queue;
    final all = _busy.contains('*');
    return Scaffold(
      appBar: AppBar(title: Text('⏳ العمليات المعلقة (${queue.length})',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  queue.isEmpty
                      ? '✔ ماكو شي معلق، كل العمليات مرفوعة.'
                      : 'هاي العمليات محفوظة على التلفون وبعدها ما ارتفعت. ارفعها كلها، أو وحدة وحدة.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                if (_error != null) ...[const SizedBox(height: 10), Flash(_error!)],
                if (queue.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Btn(all ? '↻ جاري الرفع...' : '⬆ ارفع الكل (${queue.length})',
                      onTap: all ? null : () => _push(null)),
                ],
              ]),
            ),
            for (final e in queue)
              Panel(
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(describe(e, s, b), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text((e['at'] as String).substring(0, 16),
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Btn(_busy.contains(e['id']) || all ? '↻' : '⬆ ارفع', kind: BtnKind.ghost,
                      onTap: _busy.contains(e['id']) || all ? null : () => _push({e['id'] as String})),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
