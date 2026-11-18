import 'package:flutter/material.dart';

import 'store.dart';
import 'theme.dart';

String personalBalance(int value) {
  if (value == 0) return 'الحساب متصافي';
  return "${value > 0 ? 'يطلبني' : 'أطلبه'} ${iqd(value.abs())} د.ع";
}

class PersonalLists extends StatefulWidget {
  final Book book;
  final String? selected;
  final ValueChanged<String> select;
  final Future<void> Function(Map<String, dynamic>) record;
  const PersonalLists({super.key, required this.book, required this.selected,
    required this.select, required this.record});

  @override
  State<PersonalLists> createState() => _PersonalListsState();
}

class _PersonalListsState extends State<PersonalLists> {
  final name = TextEditingController(), amount = TextEditingController(), note = TextEditingController();
  String? error;
  bool busy = false;

  @override
  void didUpdateWidget(PersonalLists oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      amount.clear();
      note.clear();
      error = null;
    }
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save(String kind) async {
    if (busy) return;
    final creating = kind == 'person';
    final person = creating ? newId() : widget.selected!;
    final value = parseAmount(amount.text);
    final label = name.text.trim();
    if (creating ? label.isEmpty : value == null) {
      setState(() => error = creating ? 'اكتب اسم الشخص' : 'اكتب مبلغ صحيح بالدينار');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await widget.record({'t': kind, 'person': person,
        if (creating) 'name': label else ...{'amount': value, 'date': today(), 'note': note.text.trim()}});
      if (!mounted) return;
      if (creating) {
        name.clear();
        widget.select(person);
      } else {
        amount.clear();
        note.clear();
      }
      FocusScope.of(context).unfocus();
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر حفظ العملية');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.book.people[widget.selected];
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (account == null) ...[
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: name, maxLength: 80,
            decoration: const InputDecoration(labelText: 'اسم الشخص', counterText: '')),
          const SizedBox(height: 10),
          Btn('إضافة شخص', onTap: busy ? null : () => save('person')),
        ])),
        if (error != null) Flash(error!),
        for (final item in widget.book.people.entries)
          Card(child: ListTile(title: Text(item.value.name),
            subtitle: Text(personalBalance(item.value.outstanding)),
            trailing: const Icon(Icons.chevron_left), onTap: () => widget.select(item.key))),
      ] else ...[
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(personalBalance(account.outstanding), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: amount, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'المبلغ بالدينار')),
          TextField(controller: note, maxLength: 300,
            decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)', counterText: '')),
          if (error != null) Flash(error!),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Btn('أخذت منه', onTap: busy ? null : () => save('receive'))),
            const SizedBox(width: 8),
            Expanded(child: Btn('انطيته', kind: BtnKind.pay, onTap: busy ? null : () => save('give'))),
          ]),
        ])),
        Text('سجل الحركات', style: Theme.of(context).textTheme.titleMedium),
        if (account.entries.isEmpty) const Text('بعد ماكو حركات'),
        for (final e in account.entries.reversed)
          ListTile(leading: Icon(e.change > 0 ? Icons.south_west : Icons.north_east),
            title: Text("${e.change > 0 ? 'أخذت منه' : 'انطيته'} · ${iqd(e.change.abs())} د.ع"),
            subtitle: Text([e.date, if (e.note.isNotEmpty) e.note].join(' · '))),
      ],
    ]);
  }
}

enum AccountScope { all, general, personal }

class AccountsSummary extends StatefulWidget {
  final Book book;
  const AccountsSummary({super.key, required this.book});
  @override
  State<AccountsSummary> createState() => _AccountsSummaryState();
}

class _AccountsSummaryState extends State<AccountsSummary> {
  AccountScope scope = AccountScope.all;

  int debt(MonthlyBalance m) => switch (scope) {
    AccountScope.general => m.general,
    AccountScope.personal => m.personal,
    AccountScope.all => m.general + m.personal,
  };

  @override
  Widget build(BuildContext context) {
    final months = widget.book.months;
    final peak = months.map(debt).fold<int>(0, (a, b) => a > b ? a : b);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, children: [
        for (final (value, label) in [(AccountScope.all, 'الكل'), (AccountScope.general, 'العام'),
                                     (AccountScope.personal, 'الخاص')])
          ChoiceChip(label: Text(label), selected: scope == value,
            onSelected: (_) => setState(() => scope = value)),
      ]),
      const SizedBox(height: 12),
      Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('اللي عليّ هسه', style: Theme.of(context).textTheme.titleMedium),
        Text('${iqd(debt(months.last))} د.ع', style: Theme.of(context).textTheme.headlineSmall),
        if (scope != AccountScope.general) Text('أطلب من الأشخاص · ${iqd(months.last.credit)} د.ع'),
      ])),
      Text('الدين بنهاية كل شهر', style: Theme.of(context).textTheme.titleLarge),
      const Text('حسب وقت التسجيل · الشهر الحالي لحد اليوم'),
      const SizedBox(height: 14),
      for (final m in months.reversed)
        Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(m.month, textDirection: TextDirection.ltr), Text('${iqd(debt(m))} د.ع'),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: peak == 0 ? 0 : debt(m) / peak, minHeight: 10,
            color: AppColors.accent, backgroundColor: AppColors.line),
        ])),
    ]);
  }
}
