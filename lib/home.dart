import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pending.dart';
import 'store.dart';
import 'sync.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  final Store store;
  final String bookKey;
  final ValueChanged<String> onKey; // the book moved to a new PIN
  final VoidCallback onLock;
  /// Uploads and downloads the book; tests pass a fake.
  final SyncFn sync;
  const HomePage({super.key, required this.store, required this.bookKey, required this.onKey,
      required this.onLock, this.sync = syncBook});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const every = Duration(seconds: 30);
  late Book _b = widget.store.book(widget.bookKey);
  final _amount = TextEditingController(), _note = TextEditingController(), _code = TextEditingController();
  final _scroll = ScrollController(), _amountFocus = FocusNode();
  String? _shop;
  String _date = today();
  bool _syncing = false, _offline = false;
  String? _lastSync;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(every, (_) => _sync());
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    for (final c in [_amount, _note, _code]) {
      c.dispose();
    }
    _scroll.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _sync();
  }

  Saved get _saved => widget.store.saved(widget.bookKey)!;
  int get _pending => _saved.pending.length;

  /// Uploads the queue and pulls other phones' changes; offline just leaves the queue.
  /// With automatic upload off, only a [manual] call uploads (all, or the events in [only]);
  /// the automatic calls then just download. Returns an error message, or null.
  Future<String?> _sync({bool manual = false, Set<String>? only}) async {
    if (!mounted) return null;
    if (_syncing) return 'جاري رفع ثاني، جرب بعد شوية';
    setState(() => _syncing = true);
    String? err;
    try {
      final push = manual || _saved.auto ? only : const <String>{};
      final changed = await widget.sync(widget.store, widget.bookKey, only: push);
      if (!mounted) return null;
      if (changed) _b = widget.store.book(widget.bookKey);
      _offline = false;
      _lastSync = now().substring(11, 16);
    } catch (_) {
      _offline = true;
      err = 'ماكو إنترنت، العمليات باقية بالقائمة';
    }
    if (mounted) setState(() => _syncing = false);
    return err;
  }

  Future<void> _openPending() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PendingPage(store: widget.store, bookKey: widget.bookKey,
            push: (only) => _sync(manual: true, only: only))));
    if (mounted) setState(() {});
  }

  Future<void> _setAuto(bool on) async {
    setState(() => _saved.auto = on);
    await widget.store.save();
    if (on) _sync();
  }

  Future<void> _record(Map<String, dynamic> event) async {
    final b = await widget.store.record(widget.bookKey, event);
    setState(() => _b = b);
    _sync();
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Shop? _shopById(String? id) => _b.shops.where((s) => s.id == id).firstOrNull;

  Future<void> _add(String kind) async {
    final shop = _shopById(_shop);
    final amount = parseAmount(_amount.text);
    if (shop == null || amount == null) return _say('اختار الدكان واكتب المبلغ صح (أرقام بس)');
    final note = _note.text.trim();
    final closed = _b.archive.length;
    await _record({'t': kind, 'shop': shop.id, 'amount': amount, 'date': _date,
        'note': note.length > 300 ? note.substring(0, 300) : note});
    _amount.clear();
    _note.clear();
    if (mounted) FocusScope.of(context).unfocus();
    _say(_b.archive.length > closed ? '✔ حساب ${shop.name} تصفّر وانتقل للأرشيف'
        : (kind == 'buy' ? '✔ انسجل المسواك' : '✔ انسجل التسديد'));
  }

  Future<void> _payAll(Shop shop) async {
    final bal = _b.shopBalance(shop.id);
    if (bal <= 0 ||
        !await confirm(context, 'تسدد كل دين ${shop.name} (${iqd(bal)} د.ع)؟ الحساب راح يتصفر وينتقل للأرشيف.')) {
      return;
    }
    await _record({'t': 'pay', 'shop': shop.id, 'amount': bal, 'date': today(), 'note': ''});
    _say('✔ حساب ${shop.name} تصفّر وانتقل للأرشيف');
  }

  Future<void> _delete(Entry e) async {
    if (!await confirm(context, 'تحذف هذا التسجيل؟')) return;
    await _record({'t': 'del', 'entry': e.id});
  }

  void _pick(Shop shop) {
    setState(() => _shop = shop.id);
    _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    _amountFocus.requestFocus();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.parse(_date),
        firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d != null) setState(() => _date = ymd(d));
  }

  @override
  Widget build(BuildContext context) {
    final shops = [..._b.shops]..sort((a, b) => _b.shopBalance(b.id).compareTo(_b.shopBalance(a.id)));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(children: [
          Text('🧾 ', style: TextStyle(fontSize: 24)),
          Text('دفتر ', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('الدين', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent)),
        ]),
        actions: [
          _syncChip(),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Btn('🔒 قفل', kind: BtnKind.ghost, onTap: widget.onLock),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _sync(manual: true),
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _hero(),
              _form(),
              for (final s in shops) _shopCard(s),
              _shopsEditor(),
              _syncEditor(),
              _pinEditor(),
              _archive(),
            ],
          ),
        ),
      ),
    );
  }

  /// "☁️" when everything is uploaded, "⏳ 3" while changes wait for the internet.
  Widget _syncChip() {
    final n = _pending;
    final (label, color) = _syncing
        ? ('↻', AppColors.muted)
        : n > 0 ? ('⏳ $n', AppColors.accent2) : ('☁️ ✔', AppColors.good);
    return InkWell(
      onTap: n > 0 ? _openPending : () => _sync(manual: true),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: AppColors.panel, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line)),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    );
  }

  Widget _hero() => Panel(
        child: Row(children: [
          const Text('🧾', style: TextStyle(fontSize: 44)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('📒 ${_b.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const Text('مجموع اللي علي هسه', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              Text.rich(TextSpan(children: [
                TextSpan(text: iqd(_b.total)),
                const TextSpan(text: ' د.ع', style: TextStyle(fontSize: 16)),
              ]), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.accent, height: 1.2)),
              if (_pending > 0 && (_offline || !_saved.auto))
                Text(
                    _saved.auto
                        ? '📴 ماكو إنترنت: $_pending تسجيل محفوظ بالقائمة، يرتفع لحاله أول ما يرجع'
                        : '⏳ $_pending عملية معلقة، الرفع يدوي: دوس ⏳ فوق وارفعها',
                    style: const TextStyle(color: AppColors.accent2, fontSize: 12)),
            ]),
          ),
        ]),
      );

  Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 13)));

  Widget _form() => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('تسجيل جديد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          _label('الدكان'),
          DropdownButtonFormField<String>(
            key: ValueKey(_shop),
            initialValue: _shopById(_shop)?.id,
            hint: const Text('— اختار —'),
            isExpanded: true,
            dropdownColor: AppColors.panel2,
            items: [for (final s in _b.shops) DropdownMenuItem(value: s.id, child: Text(s.name))],
            onChanged: (v) => setState(() => _shop = v),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _label('المبلغ (دينار)'),
                TextField(
                  controller: _amount,
                  focusNode: _amountFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹,٬]'))],
                  decoration: const InputDecoration(hintText: 'مثلاً 15000'),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _label('التاريخ'),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(suffixIcon: Icon(Icons.event, size: 18)),
                    child: Text(_date),
                  ),
                ),
              ]),
            ),
          ]),
          _label('التفاصيل (اختياري)'),
          TextField(controller: _note, decoration: const InputDecoration(hintText: 'خبز، بيض، غاز...')),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Btn('🛒 مسواك (دين)', onTap: () => _add('buy'))),
            const SizedBox(width: 8),
            Expanded(child: Btn('💵 تسديد', kind: BtnKind.pay, onTap: () => _add('pay'))),
          ]),
        ]),
      );

  Widget _entryRow(Entry e, {bool deletable = false}) {
    final waiting = _saved.pending.contains(e.id);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${e.isBuy ? '+' : '−'}${iqd(e.amount)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: e.isBuy ? AppColors.accent : AppColors.good)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e.isBuy ? 'مسواك' : 'تسديد'}${e.note.isEmpty ? '' : ' · ${e.note}'}', style: const TextStyle(fontSize: 14)),
            Text('${e.date}${waiting ? ' · ⏳ ينتظر الرفع' : ''}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
        if (deletable)
          InkWell(
            onTap: () => _delete(e),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.panel2, borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.line)),
              child: const Text('✕', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
          ),
      ]),
    );
  }

  Widget _shopCard(Shop s) {
    final items = _b.openEntries(s.id);
    final bal = balance(items);
    final edge = bal > 0 ? AppColors.accent : (bal < 0 ? AppColors.credit : AppColors.good);
    TextSpan money(int n) => TextSpan(children: [
          TextSpan(text: iqd(n)),
          const TextSpan(text: ' د.ع', style: TextStyle(fontSize: 14, color: AppColors.muted)),
        ]);
    return Panel(
      edge: edge,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text.rich(bal == 0 ? const TextSpan(text: '✔ صفر') : money(bal.abs()),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: bal > 0 ? AppColors.text : edge)),
        Text(
          bal > 0 ? 'دين من ${items.last.date} · ${items.length} تسجيل'
              : bal < 0 ? 'رصيد إلي عنده (دافع زايد)' : 'ما علي شي',
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Btn('🛒 سجّل', kind: BtnKind.ghost, onTap: () => _pick(s))),
          if (bal > 0) ...[
            const SizedBox(width: 8),
            Expanded(child: Btn('💵 سدد الكل', kind: BtnKind.pay, onTap: () => _payAll(s))),
          ],
        ]),
        if (items.isNotEmpty)
          ExpansionTile(
            title: const Text('التفاصيل', style: TextStyle(color: AppColors.muted, fontSize: 14)),
            children: [for (final e in items) _entryRow(e, deletable: true)],
          ),
      ]),
    );
  }

  Widget _shopsEditor() => Panel(
        child: ExpansionTile(
          title: const Text.rich(TextSpan(children: [
            TextSpan(text: '🏪 الدكاكين ', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: 'إضافة، تعديل اسم، حذف', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ])),
          children: [
            _ShopRow(key: const ValueKey('new'), name: '', hint: 'اسم الدكان الجديد', saveLabel: '➕ إضافة',
                onSave: (name) => _record({'t': 'shop', 'shop': newId(), 'name': name})),
            for (final s in _b.shops)
              _ShopRow(
                key: ValueKey(s.id),
                name: s.name,
                saveLabel: 'حفظ',
                onSave: (name) async {
                  await _record({'t': 'shop', 'shop': s.id, 'name': name});
                  _say('✔ انحفظ');
                },
                onRemove: () async {
                  if (_b.openEntries(s.id).isNotEmpty) return _say('ما ينحذف: الدكان بي حساب مفتوح، سدده أول');
                  if (!await confirm(context, 'تحذف ${s.name}؟')) return;
                  if (_shop == s.id) _shop = null;
                  await _record({'t': 'unshop', 'shop': s.id});
                },
              ),
          ],
        ),
      );

  Widget _syncEditor() {
    final n = _pending;
    final code = _saved.sync;
    return Panel(
      child: ExpansionTile(
        title: Text.rich(TextSpan(children: [
          const TextSpan(text: '☁️ المزامنة ', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: n > 0 ? '$n تسجيل بالقائمة' : 'كل شي مرفوع',
              style: TextStyle(color: n > 0 ? AppColors.accent2 : AppColors.muted, fontSize: 13)),
        ])),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            n == 0
                ? '✔ كل التسجيلات مرفوعة${_lastSync == null ? '' : ' (آخر مزامنة $_lastSync)'}.'
                : !_saved.auto ? '$n عملية معلقة. الرفع يدوي: شوفها وارفعها من العمليات المعلقة.'
                : _offline ? '📴 ماكو إنترنت. التسجيلات محفوظة بالقائمة على التلفون، وترتفع لحالها أول ما يرجع الإنترنت.'
                : 'جاري رفع $n تسجيل...',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _saved.auto,
            onChanged: _setAuto,
            activeThumbColor: AppColors.good,
            title: const Text('⚡ رفع تلقائي', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(_saved.auto ? 'العمليات ترتفع لحالها أول ما يكون إنترنت' : 'العمليات تبقى معلقة لحد ما ترفعها انت',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
          Row(children: [
            Expanded(child: Btn('📋 المعلقة ($n)', kind: BtnKind.ghost, onTap: _openPending)),
            const SizedBox(width: 8),
            Expanded(child: Btn(_syncing ? '↻ جاري...' : '⬆ ارفع الكل', kind: BtnKind.ghost,
                onTap: () async {
                  final err = await _sync(manual: true);
                  if (err != null) _say(err);
                })),
          ]),
          const SizedBox(height: 14),
          const Text('كود الدفتر: اكتبه بتلفون ثاني حتى يصير نفس الدفتر بالتلفونين. لا تنطيه لأحد.',
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: SelectableText(showSyncCode(code), textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
            Btn('📋 نسخ', kind: BtnKind.ghost, onTap: () async {
              await Clipboard.setData(ClipboardData(text: code));
              _say('✔ انسخ الكود');
            }),
          ]),
          const SizedBox(height: 14),
          const Text('عندك الدفتر بتلفون ثاني؟ اكتب كوده هنا:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(controller: _code, textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(hintText: 'xxxx-xxxx-...')),
            ),
            const SizedBox(width: 8),
            Btn('ربط', onTap: () async {
              final c = parseSyncCode(_code.text);
              if (c == null) return _say('الكود لازم 32 حرف/رقم');
              if (c == code) return _say('هذا كود نفس الدفتر');
              if (!await confirm(context, 'تربط هذا الدفتر بالكود؟ تسجيلات هذا التلفون راح تندمج ويا الدفتر الثاني.')) return;
              await widget.store.join(widget.bookKey, c);
              _code.clear();
              setState(() {});
              await _sync(manual: true);
              if (mounted) _say(_offline ? 'انربط. راح يتزامن أول ما يرجع الإنترنت' : '✔ انربط وتزامن');
            }),
          ]),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _pinEditor() => Panel(child: _PinEditor(onChange: (oldPin, newPin) async {
        final s = widget.store;
        if (!validPin(oldPin) || s.pinKey(oldPin) != widget.bookKey) return 'الرمز الحالي غلط';
        if (!validPin(newPin)) return 'الرمز الجديد لازم 6 أرقام';
        if (s.taken(newPin)) return 'هذا الرمز مستخدم، اختار رمز غيره';
        widget.onKey(await s.changePin(widget.bookKey, newPin));
        _say('✔ تغيّر الرمز');
        return null;
      }));

  Widget _archive() => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text.rich(TextSpan(children: [
            TextSpan(text: '🗄️ الأرشيف ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            TextSpan(text: 'الحسابات اللي تصفرت', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ])),
          if (_b.archive.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 6),
                child: Text('لسه ماكو حساب متصفر.', style: TextStyle(color: AppColors.muted))),
          for (final a in _b.archive)
            ExpansionTile(
              title: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(a.shopName, style: const TextStyle(fontWeight: FontWeight.w800)),
                Pill('${a.from} ← ${a.to}'),
                Pill('مسواك ${iqd(a.bought)}'),
                const Pill('مسدد ✔', ok: true),
              ]),
              children: [for (final e in a.entries) _entryRow(e)],
            ),
        ]),
      );
}

class _ShopRow extends StatefulWidget {
  final String name, saveLabel;
  final String? hint;
  final Future<void> Function(String) onSave;
  final VoidCallback? onRemove;
  const _ShopRow({super.key, required this.name, required this.saveLabel, required this.onSave,
      this.hint, this.onRemove});
  @override
  State<_ShopRow> createState() => _ShopRowState();
}

class _ShopRowState extends State<_ShopRow> {
  late final _c = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: TextField(controller: _c, maxLength: 60,
              decoration: InputDecoration(hintText: widget.hint, counterText: ''))),
          const SizedBox(width: 8),
          Btn(widget.saveLabel, kind: widget.onRemove == null ? BtnKind.main : BtnKind.ghost, onTap: () async {
            final name = _c.text.trim();
            if (name.isEmpty) return;
            await widget.onSave(name);
            if (widget.onRemove == null) _c.clear();
          }),
          if (widget.onRemove != null) ...[
            const SizedBox(width: 6),
            Btn('🗑', kind: BtnKind.ghost, onTap: widget.onRemove),
          ],
        ]),
      );
}

class _PinEditor extends StatefulWidget {
  /// Returns an error message, or null when the PIN changed.
  final Future<String?> Function(String oldPin, String newPin) onChange;
  const _PinEditor({required this.onChange});
  @override
  State<_PinEditor> createState() => _PinEditorState();
}

class _PinEditorState extends State<_PinEditor> {
  final _old = TextEditingController(), _new = TextEditingController();
  String? _msg;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController c, String hint) => TextField(
        controller: c,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]'))],
        decoration: InputDecoration(hintText: hint, counterText: ''),
      );

  @override
  Widget build(BuildContext context) => ExpansionTile(
        title: const Text('🔑 تغيير الرمز السري', style: TextStyle(fontWeight: FontWeight.w800)),
        children: [
          if (_msg != null) ...[Flash(_msg!), const SizedBox(height: 8)],
          Row(children: [
            Expanded(child: _field(_old, 'الرمز الحالي')),
            const SizedBox(width: 8),
            Expanded(child: _field(_new, 'الرمز الجديد (6 أرقام)')),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Btn('تغيير', onTap: () async {
              final err = await widget.onChange(latinDigits(_old.text).trim(), latinDigits(_new.text).trim());
              if (!mounted) return;
              setState(() => _msg = err);
              if (err == null) {
                _old.clear();
                _new.clear();
              }
            }),
          ),
          const SizedBox(height: 6),
        ],
      );
}
