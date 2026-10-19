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
  const DebtsApp({super.key, required this.store, this.sync = syncBook});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'دفتر الدين',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar', 'IQ'),
        supportedLocales: const [Locale('ar', 'IQ')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: appTheme(),
        home: Gate(store: store, sync: sync),
      );
}

/// Shows the PIN screen until a book is open, and locks again after an hour away.
class Gate extends StatefulWidget {
  final Store store;
  final SyncFn sync;
  const Gate({super.key, required this.store, required this.sync});
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
          onKey: (k) => setState(() => _key = k), onLock: () => setState(() => _key = null));
    }
    return LockPage(store: widget.store, onOpen: (k) => setState(() => _key = k));
  }
}

class LockPage extends StatefulWidget {
  final Store store;
  final ValueChanged<String> onOpen;
  const LockPage({super.key, required this.store, required this.onOpen});
  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  final _name = TextEditingController(), _pin = TextEditingController(), _pin2 = TextEditingController();
  late bool _signup = !widget.store.hasBooks;
  String? _msg;

  @override
  void dispose() {
    for (final c in [_name, _pin, _pin2]) {
      c.dispose();
    }
    super.dispose();
  }

  String _read(TextEditingController c) => latinDigits(c.text).trim();

  Future<void> _submit() async {
    final s = widget.store;
    if (s.lockedFor() > 0) return setState(() {});
    final pin = _read(_pin);
    if (_signup) {
      final name = _name.text.trim();
      if (name.isEmpty || !validPin(pin) || pin != _read(_pin2)) {
        return setState(() => _msg = 'اكتب اسمك، والرمز 6 أرقام ونفسه بالخانتين');
      }
      if (s.taken(pin)) {
        final left = await s.failed();
        return setState(() => _msg = left > 0 ? 'هذا الرمز مستخدم، اختار رمز غيره' : null);
      }
      widget.onOpen(await s.create(name.length > 40 ? name.substring(0, 40) : name, pin));
      return;
    }
    final key = validPin(pin) ? await s.unlock(pin) : null;
    if (key != null) return widget.onOpen(key);
    final left = await s.failed();
    _pin.clear();
    setState(() => _msg = left > 0 ? 'الرمز غلط (باقي $left محاولات)' : null);
  }

  Widget _pinField(TextEditingController c, String hint, {bool focus = false}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          autofocus: focus,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, letterSpacing: 6),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]'))],
          decoration: InputDecoration(hintText: hint, counterText: '',
              hintStyle: const TextStyle(fontSize: 16, letterSpacing: 0)),
          onSubmitted: (_) => _submit(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final wait = widget.store.lockedFor();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Panel(
                child: Column(children: [
                  const Text('🔒', style: TextStyle(fontSize: 48)),
                  if (wait > 0) ...[
                    Flash('محاولات غلط كثيرة. جرب بعد ${wait ~/ 60 + 1} دقيقة.'),
                    const SizedBox(height: 10),
                    TextButton(onPressed: () => setState(() {}), child: const Text('تحديث')),
                  ] else ...[
                    Text(_signup ? 'دفتر جديد' : 'دفتر الدين',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    if (_signup)
                      const Text('كل رمز سري إله دفتره الخاص: دكاكينه ومسواكه وأرشيفه',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                    if (_msg != null) ...[const SizedBox(height: 10), Flash(_msg!)],
                    if (_signup) ...[
                      const SizedBox(height: 10),
                      TextField(controller: _name, autofocus: true, maxLength: 40,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(hintText: 'اسمك', counterText: '')),
                      _pinField(_pin, 'رمز من 6 أرقام'),
                      _pinField(_pin2, 'أعد الرمز'),
                    ] else
                      _pinField(_pin, 'الرمز السري', focus: true),
                    const SizedBox(height: 14),
                    SizedBox(width: double.infinity,
                        child: Btn(_signup ? 'إنشاء وفتح' : 'فتح', onTap: _submit)),
                    const SizedBox(height: 8),
                    if (!_signup || widget.store.hasBooks)
                      TextButton(
                        onPressed: () => setState(() {
                          _signup = !_signup;
                          _msg = null;
                          _pin.clear();
                          _pin2.clear();
                        }),
                        child: Text(_signup ? 'عندي دفتر، أفتحه بالرمز' : '➕ دفتر جديد برمز جديد'),
                      ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
