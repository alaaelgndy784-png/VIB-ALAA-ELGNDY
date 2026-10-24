part of 'main.dart';

/// Owner-only operations: preserve invoices, receipts and account movement audit.
class DataMaintenancePage extends StatefulWidget {
  const DataMaintenancePage({super.key});
  @override State<DataMaintenancePage> createState() => _DataMaintenancePageState();
}

class _DataMaintenancePageState extends State<DataMaintenancePage> {
  static const options = <({String id, String title, bool supported})>[
    (id:'sales', title:'المبيعات — أرشفة الفواتير القديمة', supported:true),
    (id:'purchases', title:'المشتريات — أرشفة الفواتير القديمة', supported:true),
    (id:'customers', title:'العملاء — إخفاء وتصفير الأرصدة', supported:true),
    (id:'suppliers', title:'الموردون — إخفاء وتصفير الأرصدة', supported:true),
    (id:'cash', title:'الصندوق — تصفير الرصيد مع تسجيل حركة', supported:true),
    (id:'expenses', title:'المصروفات — أرشفة السجلات القديمة', supported:true),
    (id:'stockQty', title:'المخزن — تعديل الكمية 0 لجميع المنتجات', supported:true),
    (id:'stockPrice', title:'المخزن — تعديل الأسعار 0 لجميع المنتجات', supported:true),
    (id:'archiveProducts', title:'المخزن — إخفاء جميع المنتجات', supported:true),
  ];
  final selected = <String>{};
  bool processing = false;
  String outcome = '';

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<bool> _confirm() async {
    final input = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(builder: (dialog, redraw) => AlertDialog(
        title: const Text('تأكيد معالجة البيانات'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('أرشفة المبيعات والمشتريات والمصروفات تخفي السجلات القديمة من قوائم المدير فقط، ولا تحذف الفواتير أو سندات القبض أو تغيّر رصيد العملاء والصندوق. باقي عمليات التصفير تغيّر بيانات حقيقية وقد لا يمكن التراجع عنها. اعمل نسخة احتياطية أولًا.'),
          const SizedBox(height: 12),
          Text('عدد الاختيارات: ' + selected.length.toString()),
          const SizedBox(height: 12),
          TextField(controller: input, onChanged: (_) => redraw(() {}),
            decoration: const InputDecoration(labelText:'اكتب كلمة تأكيد بنفسك')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: input.text.trim() == 'تأكيد' ? () => Navigator.pop(dialog, true) : null,
            child: const Text('تنفيذ التغييرات'),
          ),
        ],
      )),
    );
    input.dispose();
    return result == true;
  }

  Future<int> _batchChange(String name,
      Map<String, dynamic>? Function(Map<String, dynamic>) modifier) async {
    final snap = await db.collection(name).get(const GetOptions(source: Source.server));
    if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites) {
      throw StateError('لا يمكن تنفيذ المعالجة بدون نسخة حديثة من السيرفر');
    }
    var count = 0;
    for (var index = 0; index < snap.docs.length; index += 150) {
      final batch = db.batch();
      var changed = 0;
      for (final doc in snap.docs.skip(index).take(150)) {
        final patch = modifier(doc.data());
        if (patch != null && patch.isNotEmpty) {
          batch.update(doc.reference, patch);
          changed++;
        }
      }
      if (changed > 0) {
        await batch.commit();
        count += changed;
      }
    }
    return count;
  }

  Future<void> _run() async {
    if (processing) return;
    if (selected.isEmpty) { _message('اختار بيانات المعالجة الأول'); return; }
    const archives = {'sales','purchases','expenses'};
    if (selected.any(archives.contains) && selected.any((id) => !archives.contains(id))) {
      _message('لأمان الحسابات، نفّذ أرشفة الفواتير والمصروفات لوحدها، وبعدين أي تصفير آخر.');
      return;
    }
    if (!await _confirm() || !mounted) return;
    setState(() { processing = true; outcome = ''; });
    final finished = <String>[];
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('يجب تسجيل الدخول بالمدير');
      final profile = await db.collection('users').doc(uid).get(
        const GetOptions(source: Source.server));
      if (profile.data()?['role'] != 'owner' || profile.data()?['active'] != true) {
        throw StateError('المعالجة للمدير الفعّال فقط');
      }
      // Check server connectivity before any write.
      final current = await db.collection('settings').doc('main').get(
        const GetOptions(source: Source.server));
      if (current.metadata.isFromCache || current.metadata.hasPendingWrites) {
        throw StateError('المعالجة تتطلب الإنترنت ومزامنة مكتملة');
      }
      for (final id in selected.toList()) {
        int count = 0;
        if (id == 'sales' || id == 'purchases' || id == 'expenses') {
          final field = switch (id) {
            'sales' => 'managerArchivedSalesBefore',
            'purchases' => 'managerArchivedPurchasesBefore',
            _ => 'managerArchivedExpensesBefore',
          };
          // No deletion, no invoices mutated, and no balance corrections:
          // only the manager's server-synchronized view boundary changes.
          await db.collection('users').doc(uid).update({
            field: FieldValue.serverTimestamp(),
          });
          finished.add('$id: تم إخفاء القديم');
          if (mounted) setState(() { outcome = finished.join(' | '); });
          continue;
        } else if (id == 'customers' || id == 'suppliers') {
          count = await _batchChange(id, (data) =>
            data['active'] == false && (data['balance'] ?? 0) == 0 &&
              (data['openingBalance'] ?? 0) == 0 ? null : {
              'active':false, 'balance':0, 'openingBalance':0,
              'updatedAt':FieldValue.serverTimestamp(),
            });
        } else if (id == 'stockQty') {
          count = await _batchChange('stock', (data) =>
            (data['quantity'] as num? ?? 0) == 0 ? null : {'quantity':0});
        } else if (id == 'stockPrice') {
          count = await _batchChange('products', (data) =>
            (data['price'] as num? ?? 0) == 0 &&
              (data['purchasePrice'] as num? ?? 0) == 0 ? null : {
              'price':0, 'purchasePrice':0,
              'updatedAt':FieldValue.serverTimestamp(),
            });
        } else if (id == 'archiveProducts') {
          count = await _batchChange('products', (data) =>
            data['active'] == false ? null : {
              'active':false, 'updatedAt':FieldValue.serverTimestamp(),
            });
        } else if (id == 'cash') {
          final cashRef = db.collection('settings').doc('cash');
          await db.runTransaction((tx) async {
            final snap = await tx.get(cashRef);
            final old = (snap.data()?['balance'] as num?)?.toDouble() ?? 0.0;
            if (old == 0) return;
            tx.set(db.collection('accountMovements').doc(), {
              'accountType':'cash','kind':'manual_reset','amount':old.abs(),
              'delta': -old, 'balanceBefore':old, 'balanceAfter':0,
              'reason':'معالجة بيانات الصندوق بواسطة المدير',
              'actorId':uid, 'createdAt':FieldValue.serverTimestamp(),
            });
            tx.set(cashRef, {
              'balance':0, 'updatedAt':FieldValue.serverTimestamp(),
            }, SetOptions(merge:true));
          });
          count = 1;
        } else {
          throw StateError('الخيار غير آمن دون تسوية القيود المحاسبية: ' + id);
        }
        finished.add(id + ': ' + count.toString());
        if (mounted) setState(() { outcome = finished.join(' | '); });
      }
      await db.collection('settings').doc(
        'maintenance_' + DateTime.now().microsecondsSinceEpoch.toString()).set({
          'operations':selected.toList(), 'summary':finished,
          'by':uid, 'createdAt':FieldValue.serverTimestamp(),
        });
      if (mounted) {
        setState(() { selected.clear(); });
        _message('تمت المعالجة. الفواتير المؤرشفة ما زالت محفوظة، والرصيد لم يتغير بسبب الأرشفة.');
      }
    } catch (e) {
      if (mounted) _message('المعالجة لم تكتمل بالكامل: ' + e.toString() +
        (finished.isNotEmpty ? ' | تم: ' + finished.join(', ') : ''));
    } finally {
      if (mounted) setState(() { processing = false; });
    }
  }

  Future<void> _restoreHistory(String id) async {
    if (processing) return;
    final category = switch (id) {
      'sales' => 'المبيعات',
      'purchases' => 'المشتريات',
      _ => 'المصروفات',
    };
    final field = switch (id) {
      'sales' => 'managerArchivedSalesBefore',
      'purchases' => 'managerArchivedPurchasesBefore',
      _ => 'managerArchivedExpensesBefore',
    };
    final accepted = await showDialog<bool>(context:context,
      builder:(dialog) => AlertDialog(
        title:Text('إظهار سجلات ' + category),
        content:Text('هترجع السجلات المؤرشفة تظهر في قوائم المدير. مش هيتم تغيير أي أرصدة.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(dialog,true),child:const Text('إظهار السجلات')),
        ],
      ));
    if (accepted != true || !mounted) return;
    setState(() => processing = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('لا يوجد مدير مسجل');
      final profile = await db.collection('users').doc(uid).get(
        const GetOptions(source:Source.server));
      if (profile.data()?['role'] != 'owner' || profile.data()?['active'] != true) {
        throw StateError('العملية للمدير فقط');
      }
      await db.collection('users').doc(uid).update({field:FieldValue.delete()});
      await db.collection('settings').doc(
        'maintenance_' + DateTime.now().microsecondsSinceEpoch.toString()).set({
          'operations':['restore_' + id], 'by':uid,
          'createdAt':FieldValue.serverTimestamp(),
        });
      _message('تم استرجاع عرض سجلات ' + category);
    } catch(e) {
      _message('تعذر إظهار السجلات: ' + e.toString());
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  void _openAccountDirectory() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(data: managerTheme(context), child: Scaffold(
        appBar: AppBar(title: const Text('تسوية حساب عميل / مورد')),
        body: const Accounts(),
      )),
    )));
  }

  void _yearEndInfo() {
    showDialog<void>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('إقفال السنة المالية'),
      content: const Text(
        'يلزم أولًا مراجعة الذمم والمخزون والصندوق وتصدير نسخة احتياطية، ثم اعتماد أرصدة افتتاحية متطابقة للفترة التالية. '
        'الإقفال الآلي غير مفعّل حاليًا حتى لا تختفي فواتير أو تتغير أرصدة بدون قيود صحيحة.'),
      actions: [FilledButton(onPressed:() => Navigator.pop(dialog),
        child: const Text('تمام'))],
    ));
  }

  @override Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      const Text('معالجة البيانات', textAlign: TextAlign.center,
        style: TextStyle(color:gold, fontSize:24, fontWeight:FontWeight.bold)),
      const SizedBox(height:10),
      const Text('اختار ما تريد. أرشفة المبيعات والمشتريات والمصروفات تخفي القديم من قوائم المدير فقط؛ السجلات والسندات والفلوس تظل محفوظة.',
        textAlign:TextAlign.right),
      const SizedBox(height:8),
      for (final option in options)
        CheckboxListTile(
          dense:true, controlAffinity:ListTileControlAffinity.leading,
          value:selected.contains(option.id),
          onChanged: processing || !option.supported ? null : (value) =>
            setState(() { if (value == true) { selected.add(option.id); }
              else { selected.remove(option.id); } }),
          title:Text(option.title,
            style:TextStyle(color:option.supported ? Colors.redAccent : Colors.grey)),
          subtitle: {'sales','purchases','expenses'}.contains(option.id)
            ? const Text('إخفاء القديم فقط — لا يمس الأرصدة أو السندات')
            : option.supported ? null :
              const Text('محمي: يلزم تسوية محاسبية قبل الإلغاء'),
        ),
      const SizedBox(height:12),
      if (managerArchivedSalesBefore != null ||
          managerArchivedPurchasesBefore != null ||
          managerArchivedExpensesBefore != null) ...[
        const Text('السجلات المؤرشفة — استرجاع العرض', style: TextStyle(color: gold)),
        Wrap(spacing:6, runSpacing:4, children:[
          if (managerArchivedSalesBefore != null)
            OutlinedButton(onPressed:processing ? null : ()=>_restoreHistory('sales'),
              child:const Text('إظهار المبيعات')),
          if (managerArchivedPurchasesBefore != null)
            OutlinedButton(onPressed:processing ? null : ()=>_restoreHistory('purchases'),
              child:const Text('إظهار المشتريات')),
          if (managerArchivedExpensesBefore != null)
            OutlinedButton(onPressed:processing ? null : ()=>_restoreHistory('expenses'),
              child:const Text('إظهار المصروفات')),
        ]),
      ],
      const SizedBox(height:16),
      FilledButton.icon(
        onPressed:processing ? null : _run,
        icon:processing ? const SizedBox(width:16,height:16,
          child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.delete_sweep_outlined),
        label:Text(selected.isNotEmpty && selected.every((id) =>
          {'sales','purchases','expenses'}.contains(id))
          ? 'أرشفة البيانات المحددة' : 'معالجة البيانات المحددة'),
      ),
      const SizedBox(height:8),
      OutlinedButton.icon(onPressed:processing ? null : _openAccountDirectory,
        icon:const Icon(Icons.rule_folder_outlined),
        label:const Text('تسوية حساب عميل / مورد')),
      const SizedBox(height:8),
      OutlinedButton.icon(onPressed:processing ? null : _yearEndInfo,
        icon:const Icon(Icons.event_busy_outlined),
        label:const Text('إقفال السنة المالية')),
      if (outcome.isNotEmpty) Padding(padding:const EdgeInsets.all(8),
        child:Text('نتائج العمليات: ' + outcome, style:const TextStyle(color:Colors.greenAccent))),
      const SizedBox(height:10),
      const Text('مهم: لم يتم حذف سجلات الفواتير أو سندات القبض أو حركات الحسابات من الأرشيف.',
        style:TextStyle(color:Colors.orangeAccent,fontSize:12)),
    ],
  );
}
