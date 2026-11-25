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
  String date = today();
  final scroll = ScrollController();
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
    scroll.dispose();
    name.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save(String kind) async {
    if (busy) return;
    final creating = kind == 'person';
    final person = creating ? newId() : widget.selected;
    final value = parseAmount(amount.text);
    final label = name.text.trim();
    if (creating ? label.isEmpty : value == null || person == null) {
      setState(() => error = creating ? 'اكتب اسم الشخص' : 'اكتب مبلغ صحيح بالدينار');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await widget.record({'t': kind, 'person': person,
        if (creating) 'name': label else ...{'amount': value, 'date': date, 'note': note.text.trim()}});
      if (!mounted) return;
      if (creating) {
        name.clear();
        widget.select(person!);
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
    final people = widget.book.people.entries.toList()
      ..sort((a,b)=>b.value.outstanding.compareTo(a.value.outstanding));
    final owed = people.fold<int>(0,(s,p)=>s+(p.value.outstanding>0?p.value.outstanding:0));
    final credit = people.fold<int>(0,(s,p)=>s+(p.value.outstanding<0?-p.value.outstanding:0));
    return ListView(controller:scroll,padding:const EdgeInsets.fromLTRB(16,8,16,32),children:[
      Panel(child:Row(children:[const Text('🧾',style:TextStyle(fontSize:44)),const SizedBox(width:14),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('مجموع اللي علي هسه',style:TextStyle(color:AppColors.muted,fontSize:13)),
          Text('${iqd(owed)} د.ع',style:const TextStyle(fontSize:34,fontWeight:FontWeight.w800,color:AppColors.accent)),
          Text('أطلب من الأشخاص ${iqd(credit)} د.ع',style:const TextStyle(color:AppColors.credit)),
        ]))])),
      Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Text('تسجيل جديد',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
        const Text('الشخص',style:TextStyle(color:AppColors.muted,fontSize:13)),
        DropdownButtonFormField<String>(key:ValueKey(widget.selected),initialValue:widget.book.people.containsKey(widget.selected)?widget.selected:null,
          hint:const Text('— اختار —'),isExpanded:true,
          items:[for(final p in people) DropdownMenuItem(value:p.key,child:Text(p.value.name))],
          onChanged:(v){if(v!=null)widget.select(v);}),
        const SizedBox(height:10),
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            const Text('المبلغ (دينار)'),TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(hintText:'مثلاً 15000'))])),
          const SizedBox(width:8),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            const Text('التاريخ'),InkWell(onTap:()async{
              final d=await showDatePicker(context:context,initialDate:DateTime.parse(date),firstDate:DateTime(2020),lastDate:DateTime.now().add(const Duration(days:365)));
              if(d!=null&&mounted)setState(()=>date=ymd(d));
            },child:InputDecorator(decoration:const InputDecoration(suffixIcon:Icon(Icons.event,size:18)),child:Text(date)))])),
        ]),
        const SizedBox(height:10),const Text('التفاصيل (اختياري)'),
        TextField(controller:note,maxLength:300,decoration:const InputDecoration(counterText:'',hintText:'ملاحظة...')),
        if(error!=null)Flash(error!),const SizedBox(height:14),
        Row(children:[Expanded(child:Btn('💸 أخذت منه',onTap:busy?null:()=>save('receive'))),const SizedBox(width:8),
          Expanded(child:Btn('💵 انطيته',kind:BtnKind.pay,onTap:busy?null:()=>save('give')))]),
      ])),
      for(final p in people) _personCard(p.key,p.value),
      Panel(child:ExpansionTile(title:const Text('الأشخاص · إضافة، تعديل اسم، حذف',style:TextStyle(fontWeight:FontWeight.w800)),children:[
        TextField(controller:name,maxLength:80,decoration:const InputDecoration(hintText:'اسم الشخص الجديد',counterText:'')),
        const SizedBox(height:8),Btn('➕ إضافة',onTap:busy?null:()=>save('person')),
        for(final p in people) ListTile(title:Text(p.value.name),trailing:Row(mainAxisSize:MainAxisSize.min,children:[
          IconButton(tooltip:'تعديل الاسم',icon:const Icon(Icons.edit_outlined),onPressed:()async{
            var value=p.value.name;
            final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('تعديل الاسم'),
              content:TextFormField(initialValue:value,maxLength:80,onChanged:(v)=>value=v),
              actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),
                TextButton(onPressed:(){if(value.trim().isNotEmpty)Navigator.pop(ctx,value.trim());},child:const Text('حفظ'))]));
            if(result!=null&&mounted)await widget.record({'t':'person','person':p.key,'name':result});
          }),
          IconButton(tooltip:'حذف شخص بلا حركات',icon:const Icon(Icons.delete_outline),onPressed:p.value.entries.isEmpty?()async{
            if(await confirm(context,'تحذف ${p.value.name}؟'))await widget.record({'t':'unperson','person':p.key});
          }:null),
        ])),
      ])),
    ]);
  }
  Widget _personCard(String id,PersonalAccount p) {
    final b=p.outstanding,edge=b>0?AppColors.accent:b<0?AppColors.credit:AppColors.good;
    return Panel(edge:edge,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('👤 ${p.name}',style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800)),
      Text(b==0?'✔ صفر':'${iqd(b.abs())} د.ع',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800,color:b>0?AppColors.text:edge)),
      Text(b==0?'ما علي شي':b>0?'يطلبني · ${p.entries.length} تسجيل':'أطلبه · ${p.entries.length} تسجيل',style:const TextStyle(color:AppColors.muted,fontSize:13)),
      const SizedBox(height:10),Row(children:[
        Expanded(child:Btn('📝 سجّل',kind:BtnKind.ghost,onTap:(){widget.select(id);if(scroll.hasClients)scroll.animateTo(0,duration:const Duration(milliseconds:300),curve:Curves.easeOut);})),
        if(b!=0)...[const SizedBox(width:8),Expanded(child:Btn(b>0?'💵 سدد الكل':'💵 استلم الكل',kind:BtnKind.pay,onTap:()async{
          if(await confirm(context,'تصفّي حساب ${p.name}؟'))await widget.record({'t':b>0?'give':'receive','person':id,'amount':b.abs(),'date':today(),'note':'تصفية الحساب'});
        }))]]),
      if(p.entries.isNotEmpty)ExpansionTile(title:const Text('التفاصيل',style:TextStyle(color:AppColors.muted,fontSize:14)),
        children:[for(final e in p.entries.reversed)ListTile(contentPadding:EdgeInsets.zero,
          title:Text("${e.change>0?'أخذت منه':'انطيته'} · ${iqd(e.change.abs())} د.ع"),subtitle:Text([e.date,if(e.note.isNotEmpty)e.note].join(' · ')),
          trailing:IconButton(icon:const Icon(Icons.close,size:18),onPressed:()async{
            if(await confirm(context,'تحذف هذا التسجيل؟'))await widget.record({'t':'personal_del','person':id,'entry':e.id});
          }))]),
    ]));
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
