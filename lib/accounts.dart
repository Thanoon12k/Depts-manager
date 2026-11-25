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
  const AccountsSummary({super.key,required this.book});
  @override State<AccountsSummary> createState()=>_AccountsSummaryState();
}
class _AccountsSummaryState extends State<AccountsSummary> {
  AccountScope scope=AccountScope.all;
  int period=6;
  int debt(MonthlyBalance m)=>(scope==AccountScope.personal?0:m.general)+(scope==AccountScope.general?0:m.personal);
  int credit(MonthlyBalance m)=>(scope==AccountScope.personal?0:m.shopCredit)+(scope==AccountScope.general?0:m.credit);
  Widget metric(String title,int value,Color color)=>Expanded(child:Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(title,style:const TextStyle(color:AppColors.muted,fontSize:12)),
    FittedBox(fit:BoxFit.scaleDown,child:Text('${iqd(value)} د.ع',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800,color:color))),
  ])));
  @override Widget build(BuildContext context){
    final b=widget.book,all=b.months;
    final months=all.skip(all.length>period?all.length-period:0).toList();
    final owed=debt(all.last),due=credit(all.last);
    final shops=[...b.shops]..sort((a,c)=>b.shopBalance(c.id).abs().compareTo(b.shopBalance(a.id).abs()));
    final people=b.people.values.toList()..sort((a,c)=>c.outstanding.abs().compareTo(a.outstanding.abs()));
    final balances=<int>[if(scope!=AccountScope.personal)for(final s in shops)b.shopBalance(s.id),if(scope!=AccountScope.general)for(final p in people)p.outstanding];
    var peak=1;for(final m in months){if(debt(m)>peak)peak=debt(m);if(credit(m)>peak)peak=credit(m);}
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
      const Text('📊 نظرة مالية شاملة',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800)),
      Wrap(spacing:8,children:[for(final (v,label) in [(AccountScope.all,'الكل'),(AccountScope.general,'الدكاكين'),(AccountScope.personal,'الأشخاص')])
        ChoiceChip(label:Text(label),selected:scope==v,onSelected:(_)=>setState(()=>scope=v))]),
      const SizedBox(height:10),
      Row(children:[metric('اللي عليّ',owed,AppColors.accent),const SizedBox(width:8),metric('اللي إليّ',due,AppColors.credit)]),
      Row(children:[metric('الصافي (عليّ − إليّ)',owed-due,AppColors.text),const SizedBox(width:8),
        metric('تغير الدين عن الشهر السابق',all.length>1?owed-debt(all[all.length-2]):0,AppColors.text)]),
      Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Text('توزيع الأرصدة',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
        const SizedBox(height:12),
        SizedBox(height:140,child:CustomPaint(painter:_BalanceRing(owed,due),child:Center(child:Text('${balances.length}\nحساب',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w800))))),
        const SizedBox(height:10),Text('🟠 عليّ: ${iqd(owed)}   🔵 إليّ: ${iqd(due)}',textAlign:TextAlign.center),
        Text('${balances.where((n)=>n>0).length} مدينة · ${balances.where((n)=>n<0).length} دائنة · ${balances.where((n)=>n==0).length} متصافية',textAlign:TextAlign.center),
      ])),
      Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Text('تطور الأرصدة شهرياً',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
        Wrap(spacing:6,children:[for(final n in [3,6,12])ChoiceChip(label:Text('$n أشهر'),selected:period==n,onSelected:(_)=>setState(()=>period=n))]),
        const Text('حسب وقت التسجيل · الشهر الحالي لحد اليوم',style:TextStyle(fontSize:12,color:AppColors.muted)),
        const SizedBox(height:12),SizedBox(height:145,child:CustomPaint(painter:_BalanceTrend(months.map(debt).toList(),months.map(credit).toList(),peak))),
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(months.first.month),Text(months.last.month)]),
        for(final m in months.reversed)Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Column(children:[
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(m.month),Text('${iqd(debt(m))} / ${iqd(credit(m))}')]),
          LinearProgressIndicator(value:debt(m)/peak,minHeight:8,color:AppColors.accent,backgroundColor:AppColors.line),
          const SizedBox(height:4),LinearProgressIndicator(value:credit(m)/peak,minHeight:6,color:AppColors.credit,backgroundColor:AppColors.line),
        ])),
      ])),
      if(scope!=AccountScope.personal)...[
        const Text('🏪 حسابات الدكاكين',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
        for(final s in shops)detail(s.name,b.shopBalance(s.id),[
          for(final e in b.openEntries(s.id))movement(e.isBuy?'مسواك':'تسديد',e.amount,e.date,e.note,e.isBuy),
          for(final a in b.archive.where((a)=>a.shop==s.id))...[
            Text('أرشيف ${a.from} — ${a.to}',style:const TextStyle(fontWeight:FontWeight.w700)),
            Text('شراء ${iqd(a.bought)} · تسديد ${iqd(a.paid)} د.ع'),
            for(final e in a.entries)movement(e.isBuy?'مسواك':'تسديد',e.amount,e.date,e.note,e.isBuy),
          ],
        ]),
        for(final a in b.archive.where((a)=>!shops.any((s)=>s.id==a.shop)))detail('${a.shopName} · أرشيف',0,[
          for(final e in a.entries)movement(e.isBuy?'مسواك':'تسديد',e.amount,e.date,e.note,e.isBuy),
        ]),
      ],
      if(scope!=AccountScope.general)...[
        const Text('👤 الحسابات الخاصة',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
        for(final p in people)detail(p.name,p.outstanding,[for(final e in p.entries.reversed)movement(e.change>0?'أخذت منه':'انطيته',e.change.abs(),e.date,e.note,e.change>0)]),
      ],
    ]);
  }
  Widget detail(String name,int value,List<Widget> children)=>Panel(edge:value>0?AppColors.accent:value<0?AppColors.credit:AppColors.good,child:ExpansionTile(
    title:Text(name,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(personalBalance(value)),
    children:children.isEmpty?[const Text('ماكو حركات')]:children));
  Widget movement(String label,int value,String date,String note,bool increase)=>ListTile(contentPadding:EdgeInsets.zero,
    title:Text('$label · ${iqd(value)} د.ع',style:TextStyle(color:increase?AppColors.accent:AppColors.good)),
    subtitle:Text([date,if(note.isNotEmpty)note].join(' · ')));
}
class _BalanceRing extends CustomPainter {
  final int owed,credit;
  _BalanceRing(this.owed,this.credit);
  @override void paint(Canvas canvas,Size size){
    final r=(size.width<size.height?size.width:size.height)/2-12,center=size.center(Offset.zero);
    if(r<=0)return;
    final rect=Rect.fromCircle(center:center,radius:r),p=Paint()..style=PaintingStyle.stroke..strokeWidth=18..color=AppColors.line;
    canvas.drawCircle(center,r,p);
    final total=owed+credit;if(total==0)return;
    const pi=3.141592653589793;
    p.color=AppColors.accent;canvas.drawArc(rect,-pi/2,2*pi*owed/total,false,p);
    p.color=AppColors.credit;canvas.drawArc(rect,-pi/2+2*pi*owed/total,2*pi*credit/total,false,p);
  }
  @override bool shouldRepaint(covariant _BalanceRing old)=>old.owed!=owed||old.credit!=credit;
}
class _BalanceTrend extends CustomPainter {
  final List<int> owed,credit;final int peak;
  _BalanceTrend(this.owed,this.credit,this.peak);
  @override void paint(Canvas canvas,Size size){
    final grid=Paint()..color=AppColors.line;
    for(var i=0;i<5;i++){final y=8+(size.height-16)*i/4;canvas.drawLine(Offset(8,y),Offset(size.width-8,y),grid);}
    void series(List<int> values,Color color){
      final points=[for(var i=0;i<values.length;i++)Offset(values.length==1?size.width/2:8+(size.width-16)*i/(values.length-1),size.height-8-(size.height-16)*values[i]/peak)];
      final p=Paint()..color=color..strokeWidth=3..strokeCap=StrokeCap.round;
      for(var i=1;i<points.length;i++)canvas.drawLine(points[i-1],points[i],p);
      for(final point in points)canvas.drawCircle(point,4,p);
    }
    series(owed,AppColors.accent);series(credit,AppColors.credit);
  }
  @override bool shouldRepaint(covariant _BalanceTrend old)=>true;
}
