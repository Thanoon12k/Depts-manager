import 'package:flutter/material.dart';
import 'store.dart';
import 'theme.dart';

class ShoppingPage extends StatefulWidget {
  final Book book;
  final Future<void> Function(Map<String,dynamic>) record;
  const ShoppingPage({super.key,required this.book,required this.record});
  @override State<ShoppingPage> createState()=>_ShoppingPageState();
}
class _ShoppingPageState extends State<ShoppingPage> {
  DateTime month=DateTime(DateTime.now().year,DateTime.now().month);
  final input=TextEditingController();
  bool busy=false;
  String get keyMonth=>ymd(month).substring(0,7);
  List<ShoppingItem> get items=>widget.book.shopping.values.where((x)=>x.month==keyMonth).toList()
    ..sort((a,b){final c=a.position.compareTo(b.position);return c==0?a.id.compareTo(b.id):c;});
  @override void dispose(){input.dispose();super.dispose();}
  Future<void> save(Map<String,dynamic> event)async{
    if(busy)return;
    setState(()=>busy=true);
    try{await widget.record(event);}catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذّر الحفظ')));
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> add()async{
    final names=input.text.split('\n').map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList();
    if(names.isEmpty||busy)return;
    final existing=items;var position=existing.isEmpty?0:existing.last.position+1;
    final target=keyMonth;
    setState(()=>busy=true);
    try{
      for(final name in names){
        await widget.record({'t':'shopping_add','item':newId(),'month':target,'name':name,'position':position++});
      }
      input.clear();
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذّر إكمال الإضافة؛ راجع القائمة')));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> edit(ShoppingItem item)async{
    var name=item.name,note=item.note,quantity=item.quantity.toString();
    final result=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('تعديل الغرض'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(initialValue:name,onChanged:(v)=>name=v,decoration:const InputDecoration(labelText:'الغرض')),
        const SizedBox(height:8),TextFormField(initialValue:quantity,onChanged:(v)=>quantity=v,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'العدد')),
        const SizedBox(height:8),TextFormField(initialValue:note,onChanged:(v)=>note=v,decoration:const InputDecoration(labelText:'ملاحظة')),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),
        TextButton(onPressed:(){if(name.trim().isNotEmpty&&(int.tryParse(latinDigits(quantity))??0)>0)Navigator.pop(ctx,true);},child:const Text('حفظ'))]));
    if(result==true&&mounted)await save({'t':'shopping_edit','item':item.id,'name':name.trim(),'note':note.trim(),'quantity':int.parse(latinDigits(quantity))});
  }
  void shift(int n)=>setState(()=>month=DateTime(month.year,month.month+n));
  @override Widget build(BuildContext context){
    final list=items,done=list.where((x)=>x.done).length;
    return ReorderableListView.builder(
      padding:const EdgeInsets.fromLTRB(16,8,16,24),buildDefaultDragHandles:false,
      header:Column(children:[
        Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const Text('🛒 قائمة المسواك',style:TextStyle(fontSize:24,fontWeight:FontWeight.w800)),
          const Text('أغراض نخطط نشتريها بنهاية الشهر · مو ديون',style:TextStyle(color:AppColors.muted)),
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            IconButton(tooltip:'الشهر السابق',onPressed:busy?null:()=>shift(-1),icon:const Icon(Icons.chevron_right)),
            Text(keyMonth,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800)),
            IconButton(tooltip:'الشهر التالي',onPressed:busy?null:()=>shift(1),icon:const Icon(Icons.chevron_left)),
          ]),
          TextButton(onPressed:busy?null:()=>setState(()=>month=DateTime(DateTime.now().year,DateTime.now().month)),child:const Text('الشهر الحالي')),
          Text('تم شراء $done من ${list.length}'),
          const SizedBox(height:8),LinearProgressIndicator(value:list.isEmpty?0:done/list.length,color:AppColors.good),
        ])),
        Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          TextField(controller:input,minLines:1,maxLines:5,decoration:const InputDecoration(hintText:'اكتب كل غرض بسطر · مثلاً رز، زيت، شامبو')),
          const SizedBox(height:10),Btn('➕ إضافة الأغراض',onTap:busy?null:add),
        ])),
        if(list.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('بعد ماكو أغراض لهذا الشهر')),
      ]),
      itemCount:list.length,
      onReorder:(oldIndex,newIndex)async{
        if(busy)return;
        if(newIndex>oldIndex)newIndex--;
        final reordered=[...list];reordered.insert(newIndex,reordered.removeAt(oldIndex));
        await save({'t':'shopping_order','month':keyMonth,'items':reordered.map((x)=>x.id).toList()});
      },
      itemBuilder:(context,index){
        final x=list[index];
        return Panel(key:ValueKey(x.id),child:Row(children:[
          Checkbox(value:x.done,onChanged:busy?null:(v)=>save({'t':'shopping_done','item':x.id,'done':v??false})),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(x.name,style:TextStyle(fontWeight:FontWeight.w700,decoration:x.done?TextDecoration.lineThrough:null)),
            if(x.quantity>1||x.note.isNotEmpty)Text([if(x.quantity>1)'العدد: ${x.quantity}',if(x.note.isNotEmpty)x.note].join(' · '),style:const TextStyle(color:AppColors.muted,fontSize:12)),
          ])),
          IconButton(tooltip:'تعديل',onPressed:busy?null:()=>edit(x),icon:const Icon(Icons.edit_outlined,size:20)),
          IconButton(tooltip:'حذف',onPressed:busy?null:()async{if(await confirm(context,'تحذف ${x.name}؟'))await save({'t':'shopping_delete','item':x.id});},icon:const Icon(Icons.delete_outline,size:20)),
          ReorderableDragStartListener(index:index,enabled:!busy,child:const Icon(Icons.drag_handle)),
        ]));
      },
    );
  }
}
