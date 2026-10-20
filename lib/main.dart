import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'home.dart';
import 'store.dart';
import 'sync.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark); // dark status bar icons on the light app
  // Show errors on screen instead of a blank one.
  ErrorWidget.builder = (d) => Material(
        color: AppColors.bg,
        child: Padding(padding: const EdgeInsets.all(16), child: Text('صار خطأ:\n${d.exception}',
            textDirection: TextDirection.rtl, style: const TextStyle(color: AppColors.bad))),
      );
  // The first frame is drawn right away; the book loads behind the splash.
  runApp(const Boot());
}

/// Loads the saved books, then opens the app. Any failure is shown with a retry button,
/// so the phone never sits on an empty screen.
class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  Store? _store;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await Store.load().timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _store = s);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store != null) return DebtsApp(store: store);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'IQ'),
      supportedLocales: const [Locale('ar', 'IQ')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: appTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('📒', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 8),
              const Text('دفتر الدين', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              if (_error == null)
                const CircularProgressIndicator()
              else ...[
                Flash('ما گدرت أفتح البيانات: $_error'),
                const SizedBox(height: 12),
                Btn('إعادة المحاولة', onTap: _load),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class DebtsApp extends StatelessWidget {
  final Store store;
  final SyncFn sync;
  final ExistsFn exists;
  const DebtsApp({super.key, required this.store, this.sync = syncBook, this.exists = bookExists});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'دفتر الدين',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar', 'IQ'),
        supportedLocales: const [Locale('ar', 'IQ')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: appTheme(),
        home: Gate(store: store, sync: sync, exists: exists),
      );
}

/// Shows the PIN screen until a book is open, and locks again after an hour away.
class Gate extends StatefulWidget {
  final Store store;
  final SyncFn sync;
  final ExistsFn exists;
  const Gate({super.key, required this.store, required this.sync, required this.exists});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> with WidgetsBindingObserver {
  static const relock = Duration(hours: 1);
  String? _key;
  DateTime? _away;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) _away = DateTime.now();
    if (s == AppLifecycleState.resumed && _away != null &&
        DateTime.now().difference(_away!) > relock) {
      setState(() => _key = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    if (key != null) {
      return HomePage(store: widget.store, bookKey: key, sync: widget.sync,
          onLock: () => setState(() => _key = null));
    }
    return LockPage(store: widget.store, exists: widget.exists, onOpen: (k) => setState(() => _key = k));
  }
}

/// One field: the book's PIN. The same PIN opens the same book on any phone.
class LockPage extends StatefulWidget {
  final Store store;
  final ExistsFn exists;
  final ValueChanged<String> onOpen;
  const LockPage({super.key, required this.store, required this.exists, required this.onOpen});
  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final s = widget.store;
    final pin = latinDigits(_pin.text).trim();
    final key = RegExp(r'^\d{4,6}$').hasMatch(pin) ? await s.unlock(pin) : null; // already on this phone
    if (key != null) return widget.onOpen(key);
    final old = RegExp(r'^\d{4}$').hasMatch(pin); // 4-digit books from version 1.5 open, but no new ones
    if (!validPin(pin) && !old) return setState(() => _msg = 'الرمز 6 أرقام');
    setState(() {
      _busy = true;
      _msg = null;
    });
    bool? found; // null: no internet to check
    try {
      found = await widget.exists(syncCodeFor(pin)).timeout(const Duration(seconds: 15));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    if (old && found != true) {
      return setState(() => _msg = found == null ? 'ماكو إنترنت حتى أدور على الدفتر' : 'الرمز 6 أرقام');
    }
    if (found != true &&
        !await confirm(context, found == false
            ? 'ماكو دفتر بهذا الرمز. تسوي دفتر جديد بيه؟'
            : 'ماكو إنترنت حتى أدور على الدفتر. تفتحه على هذا التلفون؟ إذا هو موجود بتلفون ثاني، ينزل أول ما يرجع الإنترنت.')) {
      return;
    }
    widget.onOpen(await s.create(pin));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Panel(
                  child: Column(children: [
                    const Text('📒', style: TextStyle(fontSize: 48)),
                    const Text('دفتر الدين', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    const Text('اكتب رمز دفترك. نفس الرمز يفتح نفس الدفتر بأي موبايل.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                    if (_msg != null) ...[const SizedBox(height: 10), Flash(_msg!)],
                    const SizedBox(height: 10),
                    TextField(
                      controller: _pin,
                      autofocus: true,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 26, letterSpacing: 10),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]'))],
                      decoration: const InputDecoration(hintText: 'الرمز (6 أرقام)', counterText: '',
                          hintStyle: TextStyle(fontSize: 16, letterSpacing: 0)),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(width: double.infinity,
                        child: _busy ? const Center(child: CircularProgressIndicator()) : Btn('فتح', onTap: _submit)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
