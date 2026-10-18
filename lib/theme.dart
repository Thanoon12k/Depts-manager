import 'package:flutter/material.dart';

/// The apps1monitor hub's dark palette, so the app looks like the web tab.
class AppColors {
  static const bg = Color(0xFF12101A);
  static const panel = Color(0xFF1F1C2B);
  static const panel2 = Color(0xFF282437);
  static const line = Color(0x17FFFFFF);
  static const text = Color(0xFFF3EFE6);
  static const muted = Color(0xFFA7A1B6);
  static const accent = Color(0xFFFF6B3D);
  static const accent2 = Color(0xFFFF9A3C);
  static const good = Color(0xFF3DDC97);
  static const credit = Color(0xFF38BDF8);
  static const bad = Color(0xFFFF6B81);
}

ThemeData appTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Cairo',
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
        primary: AppColors.accent, secondary: AppColors.good, surface: AppColors.panel,
        onSurface: AppColors.text, error: AppColors.bad),
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg, foregroundColor: AppColors.text,
        elevation: 0, scrolledUnderElevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.panel2,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: const TextStyle(color: AppColors.muted),
      labelStyle: const TextStyle(color: AppColors.muted),
      border: border(AppColors.line),
      enabledBorder: border(AppColors.line),
      focusedBorder: border(AppColors.accent, 2),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(), collapsedShape: Border(), iconColor: AppColors.muted,
        collapsedIconColor: AppColors.muted, tilePadding: EdgeInsets.zero),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent,
            textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700))),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.panel2, contentTextStyle: TextStyle(color: AppColors.text,
            fontFamily: 'Cairo')),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  final Color? edge; // colored inline-start border, like the shop cards on the web
  const Panel({super.key, required this.child, this.edge});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
          boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 40, offset: Offset(0, 22), spreadRadius: -22)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: edge == null
              ? null
              : BoxDecoration(border: BorderDirectional(start: BorderSide(color: edge!, width: 6))),
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      );
}

enum BtnKind { main, pay, ghost }

/// The hub's chunky button: gradient fill and a hard offset shadow.
class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final BtnKind kind;
  const Btn(this.label, {super.key, this.onTap, this.kind = BtnKind.main});

  @override
  Widget build(BuildContext context) {
    final (colors, edge, ink) = switch (kind) {
      BtnKind.main => (const [AppColors.accent, AppColors.accent2], const Color(0xFF7A2A12), const Color(0xFF1A0E05)),
      BtnKind.pay => (const [Color(0xFF16A34A), Color(0xFF4ADE80)], const Color(0xFF0A3A1C), const Color(0xFF04210F)),
      BtnKind.ghost => (const [AppColors.panel2, AppColors.panel2], null, AppColors.text),
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(12),
          border: edge == null ? Border.all(color: AppColors.line) : null,
          boxShadow: edge == null ? null : [BoxShadow(color: edge, offset: const Offset(3, 3))],
        ),
        alignment: Alignment.center,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    );
  }
}

class Flash extends StatelessWidget {
  final String text;
  const Flash(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: AppColors.bad.withValues(alpha: .12),
            border: Border.all(color: AppColors.bad.withValues(alpha: .35)),
            borderRadius: BorderRadius.circular(12)),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.bad)),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final bool ok;
  const Pill(this.text, {super.key, this.ok = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
            color: ok ? AppColors.good : AppColors.panel2,
            border: Border.all(color: ok ? Colors.transparent : AppColors.line),
            borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: ok ? const Color(0xFF04210F) : AppColors.muted)),
      );
}

Future<bool> confirm(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.panel,
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('نعم')),
        ],
      ),
    ) ??
    false;
