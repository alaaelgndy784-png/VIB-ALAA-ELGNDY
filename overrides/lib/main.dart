import 'dart:typed_data';
import 'dart:io';
import 'package:tesseract_ocr/tesseract_ocr.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' show DateFormat;
import 'package:local_auth/local_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VibBootstrap());
}

const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBDjNjPOhmTt0SbYUfCTQM8IteDCBxGfWk',
  appId: '1:200962643703:android:5874257a144d31822c65f2',
  messagingSenderId: '200962643703', projectId: 'vib-sales',
  storageBucket: 'vib-sales.firebasestorage.app',
);

class VibBootstrap extends StatefulWidget {
  const VibBootstrap({super.key});
  @override State<VibBootstrap> createState() => _VibBootstrapState();
}

class _VibBootstrapState extends State<VibBootstrap> {
  late Future<FirebaseApp> initialization;
  @override void initState() { super.initState(); initialization = Firebase.initializeApp(options: firebaseOptions); }
  @override Widget build(BuildContext context) => FutureBuilder<FirebaseApp>(future: initialization, builder: (context, snapshot) {
    if (snapshot.hasError) return MaterialApp(debugShowCheckedModeBanner: false, home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(backgroundColor: const Color(0xFF111111), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off, color: Color(0xFFD6AC55), size: 64), const SizedBox(height: 16), const Text('تعذر الاتصال بخدمة VIB', style: TextStyle(color: Colors.white, fontSize: 22)), const SizedBox(height: 12), FilledButton(onPressed: () => setState(() => initialization = Firebase.initializeApp(options: firebaseOptions)), child: const Text('إعادة المحاولة')),
    ]))))));
    if (snapshot.connectionState == ConnectionState.done) return const VibApp();
    return const MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(backgroundColor: Color(0xFF111111), body: Center(child: CircularProgressIndicator(color: Color(0xFFD6AC55)))));
  });
}

const gold = Color(0xFFD6AC55);
final db = FirebaseFirestore.instance;

class VibApp extends StatelessWidget {
  const VibApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'VIB المبيعات',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF111111),
      colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF171717), foregroundColor: gold),
    ),
    home: const Directionality(textDirection: TextDirection.rtl, child: Gate()),
  );
}

class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, auth) {
      if (!auth.hasData) return const LoginPage();
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('users').doc(auth.data!.uid).snapshots(),
        builder: (context, user) {
          if (user.hasError) return const Center(child: Text('تعذر تحميل الحساب'));
          if (!user.hasData) return const Center(child: CircularProgressIndicator());
          final data = user.data!.data();
          if (data == null || data['active'] != true || !['owner', 'employee'].contains(data['role'])) {
            return Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('الحساب غير مفعّل. المدير يحدد فرعك ويفعّل دخولك.'),
              if (data == null) FilledButton(
                onPressed: () async {
                  final person = FirebaseAuth.instance.currentUser;
                  final email = person?.email ?? '';
                  final rawPhone = email.split('@').first;
                  if (person == null || rawPhone.isEmpty) return;
                  final accountPhone = '+$rawPhone';
                  try {
                    await db.collection('users').doc(person.uid).set({
                      'role': 'pending', 'active': false, 'name': accountPhone,
                      'phone': accountPhone, 'createdAt': FieldValue.serverTimestamp(),
                    });
                  } catch (_) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تعذر إرسال طلب التفعيل')));
                  }
                },
                child: const Text('طلب تفعيل الحساب'),
              ),
              TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('خروج')),
            ])));
          }
          final home = Home(uid: auth.data!.uid, role: data['role'] as String, branchId: (data['branchId'] ?? '') as String, name: (data['name'] ?? '') as String);
          return data['role'] == 'owner' ? OwnerSecurity(child: home) : home;
        },
      );
    },
  );
}

class OwnerSecurity extends StatefulWidget {
  final Widget child;
  const OwnerSecurity({super.key, required this.child});
  @override State<OwnerSecurity> createState() => _OwnerSecurityState();
}

class _OwnerSecurityState extends State<OwnerSecurity> {
  final auth = LocalAuthentication();
  final password = TextEditingController();
  bool unlocked = false, checking = true, busy = false;
  String message = '';
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => biometric()); }
  Future<void> biometric() async {
    setState(() { checking = true; message = ''; });
    try {
      final available = await auth.canCheckBiometrics && await auth.isDeviceSupported();
      if (!available) throw Exception('البصمة غير متاحة على الجهاز');
      final ok = await auth.authenticate(localizedReason: 'استخدم بصمتك لفتح VIB MANAGER', options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true));
      if (mounted) setState(() { unlocked = ok; checking = false; if (!ok) message = 'لم يتم التحقق من البصمة'; });
    } catch (_) { if (mounted) setState(() { checking = false; message = 'استخدم الرقم السري كبديل'; }); }
  }
  Future<void> verifyPassword() async {
    if (password.text.length < 6) return;
    setState(() { busy = true; message = ''; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.email == null) throw Exception();
      await user!.reauthenticateWithCredential(EmailAuthProvider.credential(email: user.email!, password: password.text));
      if (mounted) setState(() => unlocked = true);
    } catch (_) { if (mounted) setState(() => message = 'الرقم السري غير صحيح'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) {
    if (unlocked) return widget.child;
    return Scaffold(body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.fingerprint, size: 86, color: gold), const Text('حماية VIB MANAGER', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 18),
      if (checking) const CircularProgressIndicator() else FilledButton.icon(onPressed: biometric, icon: const Icon(Icons.fingerprint), label: const Text('فتح بالبصمة')),
      const SizedBox(height: 18), TextField(controller: password, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الرقم السري البديل')),
      const SizedBox(height: 10), FilledButton(onPressed: busy ? null : verifyPassword, child: const Text('فتح بالرقم السري')),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(message, style: const TextStyle(color: Colors.redAccent))),
      TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('تسجيل الخروج')),
    ])))));
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final phone = TextEditingController(), pin = TextEditingController();
  String? error;
  bool busy = false;
  String? normalizedPhone() {
    var value = phone.text.replaceAll(RegExp(r'\D'), '');
    if (value.startsWith('00')) value = value.substring(2);
    if (value.startsWith('0')) value = '20${value.substring(1)}';
    if (!value.startsWith('20') || value.length != 12) return null;
    return '+$value';
  }

  String emailFor(String value) => '${value.replaceAll('+', '')}@vib.local';

  Future<void> login({required bool create}) async {
    setState(() { busy = true; error = null; });
    try {
      final number = normalizedPhone();
      final password = pin.text.trim();
      if (number == null) throw Exception('اكتب رقم مصري صحيح مثل 01012345678');
      if (!RegExp(r'^\d{6,}$').hasMatch(password)) throw Exception('الرقم السري لازم يكون 6 أرقام على الأقل');
      if (create) {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailFor(number), password: password);
        await db.collection('users').doc(credential.user!.uid).set({
          'role': 'pending', 'active': false, 'name': number, 'phone': number,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailFor(number), password: password);
      }
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' || 'invalid-credential' => 'الرقم أو الرقم السري غير صحيح',
        'email-already-in-use' => 'الرقم مسجل بالفعل؛ اضغط دخول',
        'weak-password' => 'اختر رقمًا سريًا أقوى',
        _ => e.message ?? 'تعذر تسجيل الدخول',
      };
      if (mounted) setState(() => error = message);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Padding(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('VIB', style: TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: gold)),
      const Text('المبيعات والمخزون', style: TextStyle(fontSize: 20)), const SizedBox(height: 28),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف المصري')),
      const SizedBox(height: 12),
      TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'رقم سري من 6 أرقام أو أكثر')),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
      const SizedBox(height: 18),
      FilledButton(onPressed: busy ? null : () => login(create: false), child: const Text('دخول')),
      TextButton(onPressed: busy ? null : () => login(create: true), child: const Text('إنشاء حساب جديد')),
      const Text('التسجيل مجاني ولا يرسل رسالة SMS. المدير يفعّل حساب الموظف ويحدد فرعه.'),
    ]),
  ))));
}

class Home extends StatefulWidget {
  final String uid, role, branchId, name;
  const Home({super.key, required this.uid, required this.role, required this.branchId, required this.name});
  @override
  State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final owner = widget.role == 'owner';
    final labels = owner ? ['المنتجات', 'المبيعات', 'المشتريات', 'الحسابات', 'الإدارة'] : ['المنتجات', 'مبيعاتي'];
    return Scaffold(
      appBar: AppBar(title: Text('VIB | ${widget.name}'), actions: [IconButton(tooltip: 'خروج', onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout))]),
      body: switch(page) {
        0 => Products(owner: owner, uid: widget.uid, branchId: widget.branchId),
        1 => Sales(owner: owner, branchId: widget.branchId),
        2 => const Purchases(),
        3 => const Accounts(),
        _ => const Management(),
      },
      bottomNavigationBar: NavigationBar(selectedIndex: page, onDestinationSelected: (i) => setState(() => page = i), destinations: [
        const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'المنتجات'),
        NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), label: labels[1]),
        if (owner) const NavigationDestination(icon: Icon(Icons.shopping_cart_checkout), label: 'المشتريات'),
        if (owner) const NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'الحسابات'),
        if (owner) const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: 'الإدارة'),
      ]),
    );
  }
}

class Products extends StatelessWidget {
  final bool owner;
  final String uid, branchId;
  const Products({super.key, required this.owner, required this.uid, required this.branchId});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db.collection('products').snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return const Center(child: Text('تعذر تحميل المنتجات'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snap.data!.docs.where((d) => d.data()['active'] == true).toList();
      return Column(children: [
        if (owner) Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: () => productDialog(context), icon: const Icon(Icons.add), label: const Text('إضافة منتج'))),
        Expanded(child: docs.isEmpty ? const Center(child: Text('لا توجد منتجات بعد')) : ListView.builder(itemCount: docs.length, itemBuilder: (context, i) {
          final d = docs[i], p = d.data();
          return ListTile(title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db.collection('stock').doc('${owner ? 'main' : branchId}_${d.id}').snapshots(),
            builder: (context, stock) => Text('${p['name'] ?? ''}  •  المتوفر: ${(stock.data?.data()?['quantity'] as num?)?.toInt() ?? 0}'),
          ), subtitle: Text('السعر: ${p['price'] ?? 0} ج.م'), trailing: owner
            ? Wrap(children: [IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit), onPressed: () => productDialog(context, id: d.id, data: p)), IconButton(tooltip: 'المخزون الرئيسي', icon: const Icon(Icons.warehouse), onPressed: () => mainStockDialog(context, d.id, '${p['name']}'))])
            : FilledButton.icon(icon: const Icon(Icons.receipt_long),
                label: const Text('فاتورة بيع'),
                onPressed: () => saleDialog(context, d.id, p, uid, branchId)));
        })),
      ]);
    },
  );
}

Future<void> productDialog(BuildContext context, {String? id, Map<String, dynamic>? data}) async {
  final name = TextEditingController(text: '${data?['name'] ?? ''}');
  final price = TextEditingController(text: '${data?['price'] ?? ''}');
  final purchasePrice = TextEditingController(text: '${data?['purchasePrice'] ?? ''}');
  final category = TextEditingController(text: '${data?['category'] ?? ''}');
  await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(title: Text(id == null ? 'منتج جديد' : 'تعديل المنتج'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
    TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المنتج')),
    TextField(controller: category, decoration: const InputDecoration(labelText: 'الفئة')),
    TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر')),
    TextField(controller: purchasePrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'تكلفة شراء الوحدة لتقرير الأرباح')),
  ])), actions: [
    TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
    FilledButton(onPressed: () async {
      final amount = double.tryParse(price.text);
      final unitCost = purchasePrice.text.trim().isEmpty ? null : double.tryParse(purchasePrice.text.trim());
      if (name.text.trim().isEmpty || amount == null || !amount.isFinite || amount < 0 ||
          (purchasePrice.text.trim().isNotEmpty && (unitCost == null || !unitCost.isFinite || unitCost < 0))) return;
      final ref = id == null ? db.collection('products').doc() : db.collection('products').doc(id);
      try { await ref.set({'name': name.text.trim(), 'category': category.text.trim().isEmpty ? 'غير مصنف' : category.text.trim(), 'price': amount,
        if (unitCost != null) 'purchasePrice': unitCost,
        'active': true, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        if (dialogContext.mounted) Navigator.pop(dialogContext);
      } catch (_) { if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('فشل حفظ المنتج'))); }
    }, child: const Text('حفظ')),
  ]));
}

Future<void> saleDialog(BuildContext context, String productId, Map<String, dynamic> product, String uid, String branchId, {bool owner = false}) async {
  final quantity = TextEditingController(text: '1');
  final customerPhone = TextEditingController();
  final reason = TextEditingController();
  bool allowShortage = false, allowBelowCost = false;
  final saleRef = db.collection('sales').doc();
  await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, update) => AlertDialog(title: Text('فاتورة بيع: ${product['name']}'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Text('سعر الوحدة: ${product['price'] ?? 0} ج.م'),
    TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية')),
    TextField(controller: customerPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم هاتف الزبون (اختياري للواتساب)')),
    if (owner) SwitchListTile(title: const Text('السماح بالبيع رغم نقص الكمية'), value: allowShortage, onChanged: (v) => update(() => allowShortage = v)),
    if (owner) SwitchListTile(title: const Text('السماح بالبيع أقل من التكلفة'), value: allowBelowCost, onChanged: (v) => update(() => allowBelowCost = v)),
    if (owner && (allowShortage || allowBelowCost)) TextField(controller: reason, decoration: const InputDecoration(labelText: 'سبب الاستثناء (إلزامي)')),
  ])),
    actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')), FilledButton(onPressed: () async {
      final qty = int.tryParse(quantity.text);
      if (qty == null || qty <= 0) return;
      if ((allowShortage || allowBelowCost) && reason.text.trim().isEmpty) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('سجل سبب الاستثناء أولًا')));
        return;
      }
      try {
        await db.runTransaction((tx) async {
          final stockRef = db.collection('stock').doc('${branchId}_$productId');
          final stock = await tx.get(stockRef);
          final current = (stock.data()?['quantity'] as num?)?.toInt() ?? 0;
          if (current < qty && !(owner && allowShortage)) throw Exception('الكمية غير متاحة في الفرع');
          final price = (product['price'] as num?)?.toDouble() ?? 0;
          final cost = (product['purchasePrice'] as num?)?.toDouble();
          if (cost != null && price < cost && !(owner && allowBelowCost)) throw Exception('سعر البيع أقل من التكلفة؛ يحتاج موافقة المدير');
          tx.set(stockRef, {'branchId': branchId, 'productId': productId, 'quantity': current - qty, 'lastSaleId': saleRef.id}, SetOptions(merge: true));
          tx.set(saleRef, {'branchId': branchId, 'employeeId': uid, 'customerPhone': customerPhone.text.trim(), 'productId': productId, 'productName': product['name'], 'quantity': qty, 'unitPrice': price, 'total': qty * price, 'status': 'completed', 'createdAt': FieldValue.serverTimestamp(), if (owner && (allowShortage || allowBelowCost)) 'managerOverride': {'reason': reason.text.trim(), 'shortage': current < qty, 'belowCost': cost != null && price < cost, 'actorId': uid}});
          tx.set(db.collection('stockMovements').doc(), {'productId': productId, 'productName': product['name'], 'branchId': branchId, 'kind': 'sale', 'quantity': -qty, 'balanceAfter': current - qty, 'referenceId': saleRef.id, 'actorId': uid, 'createdAt': FieldValue.serverTimestamp()});
        });
        if (dialogContext.mounted) {
          Navigator.pop(dialogContext);
          try {
            final saved = await saleRef.get();
            if (context.mounted && saved.data() != null) {
              await exportInvoicePdf(context, 'sales', saleRef.id, saved.data()!);
            }
          } catch (_) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم حفظ الفاتورة؛ افتح مبيعاتي لعرضها')));
          }
        }
      } catch (e) { if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('تعذر البيع: $e'))); }
    }, child: const Text('تأكيد البيع'))])));
}

class Sales extends StatelessWidget {
  final bool owner;
  final String branchId;
  const Sales({super.key, required this.owner, required this.branchId});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: (owner ? db.collection('sales') : db.collection('sales').where('branchId', isEqualTo: branchId)).snapshots(),
    builder: (context, snap) {
    if (snap.hasError) return const Center(child: Text('تعذر عرض المبيعات'));
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final rows = snap.data!.docs.where((d) => owner || d.data()['branchId'] == branchId).toList()..sort((a,b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
    return Column(children: [Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(icon: const Icon(Icons.add_shopping_cart), label: const Text('عملية بيع جديدة'), onPressed: () => newSaleDialog(context, owner, branchId))), Expanded(child: rows.isEmpty ? const Center(child: Text('لا توجد مبيعات بعد')) : ListView(children: rows.map((d) { final s = d.data(); return ListTile(
      title: Text('${s['productName']} × ${s['quantity']}'),
      subtitle: Text('فرع: ${s['branchId']} • ${formatDate(s['createdAt'])}${s['status'] == 'returned' ? ' • مرتجع' : ''}'),
      trailing: Text('${s['total']} ج.م'),
      onTap: () => invoiceActions(context, 'sales', d.id, s, canReturn: owner),
    ); }).toList()))]);
  });
}

Future<void> newSaleDialog(BuildContext context, bool owner, String branchId) async {
  try {
    final products = await db.collection('products').get();
    if (!context.mounted) return;
    final available = products.docs.where((p) => p.data()['active'] == true).toList();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (sheet) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(sheet).height * .7, child: Column(children: [const ListTile(title: Text('اختار الصنف لعملية البيع')), Expanded(child: ListView(children: available.map((p) => ListTile(title: Text('${p.data()['name']}'), subtitle: Text('${p.data()['price'] ?? 0} ج.م'), onTap: () { Navigator.pop(sheet); saleDialog(context, p.id, p.data(), FirebaseAuth.instance.currentUser!.uid, owner ? 'main' : branchId, owner: owner); })).toList()))]))));
  } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحميل الأصناف: $e'))); }
}

class Branches extends StatelessWidget {
  const Branches({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('branches').snapshots(), builder: (context, snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    return Column(children: [FilledButton.icon(onPressed: () => branchDialog(context), icon: const Icon(Icons.add), label: const Text('فرع جديد')), Expanded(child: ListView(children: snap.data!.docs.map((d) => ListTile(title: Text('${d.data()['name'] ?? d.id}'), subtitle: Text('رمز الفرع: ${d.id}'), trailing: IconButton(icon: const Icon(Icons.inventory), onPressed: () => stockDialog(context, d.id)))).toList()))]);
  });
}
Future<void> branchDialog(BuildContext context) async {
  final name = TextEditingController();
  await showDialog<void>(context: context, builder: (c) => AlertDialog(title: const Text('فرع جديد'), content: TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الفرع')), actions: [FilledButton(onPressed: () async { if (name.text.trim().isEmpty) return; await db.collection('branches').add({'name': name.text.trim(), 'active': true}); if (c.mounted) Navigator.pop(c); }, child: const Text('حفظ'))]));
}
Future<void> stockDialog(BuildContext context, String branchId) async {
  final id = TextEditingController(), qty = TextEditingController();
  await showDialog<void>(context: context, builder: (c) => AlertDialog(title: const Text('نقل من المخزون الرئيسي'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: id, decoration: const InputDecoration(labelText: 'رمز المنتج')), TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية'))]), actions: [FilledButton(onPressed: () async {
    final q = int.tryParse(qty.text), p = id.text.trim(); if (q == null || q <= 0 || p.isEmpty) return;
    try { await db.runTransaction((tx) async {
      final mainRef = db.collection('stock').doc('main_$p'), branchRef = db.collection('stock').doc('${branchId}_$p');
      final main = await tx.get(mainRef), branch = await tx.get(branchRef), product = await tx.get(db.collection('products').doc(p));
      final available = (main.data()?['quantity'] as num?)?.toInt() ?? 0;
      if (available < q) throw Exception('المخزون الرئيسي غير كافٍ');
      tx.set(mainRef, {'branchId': 'main', 'productId': p, 'quantity': available - q});
      tx.set(branchRef, {'branchId': branchId, 'productId': p, 'quantity': ((branch.data()?['quantity'] as num?)?.toInt() ?? 0) + q});
      final transferId = db.collection('stockMovements').doc().id;
      tx.set(db.collection('stockMovements').doc(), {'productId': p, 'productName': product.data()?['name'] ?? p, 'branchId': 'main', 'kind': 'transfer_out', 'quantity': -q, 'balanceAfter': available - q, 'referenceId': transferId, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
      tx.set(db.collection('stockMovements').doc(), {'productId': p, 'productName': product.data()?['name'] ?? p, 'branchId': branchId, 'kind': 'transfer_in', 'quantity': q, 'balanceAfter': ((branch.data()?['quantity'] as num?)?.toInt() ?? 0) + q, 'referenceId': transferId, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
    }); if (c.mounted) Navigator.pop(c);
    } catch (e) { if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('$e'))); }
  }, child: const Text('نقل'))]));
}

class Staff extends StatelessWidget {
  const Staff({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('users').snapshots(), builder: (context, snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    return ListView(children: snap.data!.docs.map((d) {
      final data = d.data();
      return ListTile(
        title: Text('${data['name'] ?? data['phone'] ?? d.id}'),
        subtitle: Text('${data['phone'] ?? ''} • ${data['role'] == 'pending' ? 'بانتظار التفعيل' : (data['branchId'] ?? 'المدير')}'),
        trailing: data['role'] == 'owner' ? const Icon(Icons.verified_user) :
          TextButton(onPressed: () => assignEmployee(context, d.id, data), child: const Text('تحديد الفرع')),
      );
    }).toList());
  });
}

class Management extends StatelessWidget {
  const Management({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Card(child: ListTile(leading: const Icon(Icons.inventory_2, color: gold), title: const Text('جرد المخزون حسب الفئة'), subtitle: const Text('المتاح وسعر الشراء وسعر البيع لكل صنف'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('جرد المخزون')), body: const InventoryAudit()))))),
    Card(child: ListTile(leading: const Icon(Icons.trending_up, color: gold), title: const Text('تقرير الأرباح'), subtitle: const Text('يومي وأسبوعي وشهري حسب تكلفة شراء الأصناف'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('تقرير الأرباح')), body: const ProfitReport()))))),
    Card(child: ListTile(leading: const Icon(Icons.payments, color: gold), title: const Text('الصندوق'), subtitle: const Text('إضافة وخصم ومراجعة الحركات'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('الصندوق')), body: const CashBox()))))),
    Card(child: ListTile(leading: const Icon(Icons.receipt, color: gold), title: const Text('المصروفات'), subtitle: const Text('مصروفات المحل والرواتب وخصمها من الصندوق'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('المصروفات')), body: const Expenses()))))),
    Card(child: ListTile(leading: const Icon(Icons.store, color: gold), title: const Text('الفروع والمخزون'), subtitle: const Text('إضافة الفروع ونقل البضاعة إليها'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('الفروع')), body: const Branches()))))),
    Card(child: ListTile(leading: const Icon(Icons.people, color: gold), title: const Text('الموظفون والصلاحيات'), subtitle: const Text('تفعيل الموظف وتحديد فرعه'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('الموظفون')), body: const Staff()))))),
    Card(child: ListTile(leading: const Icon(Icons.history, color: gold), title: const Text('سجل حركات الحسابات'), subtitle: const Text('التحصيلات والمدفوعات محفوظة بالتاريخ'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('حركات الحسابات')), body: const AccountMovements()))))),
    Card(child: ListTile(leading: const Icon(Icons.swap_vert, color: gold), title: const Text('تقرير حركة صنف'), subtitle: const Text('مبيعات ومشتريات ومرتجعات ورصيد كل حركة'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('تقرير حركة صنف')), body: const ItemMovementReport()))))),
    Card(child: ListTile(leading: const Icon(Icons.settings, color: gold), title: const Text('الإعدادات والطباعة'), subtitle: const Text('بيانات الشركة وتجهيز الفواتير للطباعة'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('الإعدادات')), body: const AppSettings()))))),
  ]);
}

class InventoryAudit extends StatefulWidget {
  const InventoryAudit({super.key});
  @override State<InventoryAudit> createState() => _InventoryAuditState();
}

class Expenses extends StatelessWidget {
  const Expenses({super.key});
  @override Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: () => expenseDialog(context), icon: const Icon(Icons.add), label: const Text('تسجيل مصروف'))),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('accountMovements').where('accountType', isEqualTo: 'expenses').snapshots(), builder: (context, snap) {
      if (snap.hasError) return const Center(child: Text('تعذر تحميل المصروفات'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snap.data!.docs.toList()..sort((a,b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
      final total = rows.fold<double>(0, (sum, row) => sum + ((row.data()['amount'] as num?)?.toDouble() ?? 0));
      return Column(children: [ListTile(title: const Text('إجمالي المصروفات المسجلة'), trailing: Text('${total.toStringAsFixed(2)} ج.م')), Expanded(child: ListView(children: rows.map((row) { final data = row.data(); return ListTile(title: Text('${data['reason'] ?? ''}'), subtitle: Text('${data['category'] ?? 'عام'} • ${formatDate(data['createdAt'])}'), trailing: Text('${data['amount']} ج.م')); }).toList()))]);
    }))]);
}

Future<void> expenseDialog(BuildContext context) async {
  final category = TextEditingController(), reason = TextEditingController(), amount = TextEditingController();
  await showDialog<void>(context: context, builder: (dialog) => AlertDialog(title: const Text('مصروف جديد'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
    TextField(controller: category, decoration: const InputDecoration(labelText: 'الفئة، مثل إيجار أو رواتب')),
    TextField(controller: reason, decoration: const InputDecoration(labelText: 'وصف المصروف')),
    TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ')),
  ])), actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إلغاء')), FilledButton(onPressed: () async {
    final value = double.tryParse(amount.text.trim());
    if (value == null || !value.isFinite || value <= 0 || reason.text.trim().isEmpty) return;
    try {
      await db.runTransaction((tx) async {
        final cashRef = db.collection('settings').doc('cash'), snap = await tx.get(cashRef);
        final before = (snap.data()?['balance'] as num?)?.toDouble() ?? 0;
        if (before < value) throw Exception('رصيد الصندوق غير كافٍ');
        final ref = db.collection('accountMovements').doc();
        tx.set(cashRef, {'balance': before - value, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        tx.set(ref, {'accountType': 'expenses', 'category': category.text.trim().isEmpty ? 'عام' : category.text.trim(), 'reason': reason.text.trim(), 'amount': value, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
        tx.set(db.collection('accountMovements').doc(), {'accountType': 'cash', 'kind': 'expense', 'accountId': ref.id, 'accountName': category.text.trim(), 'amount': value, 'delta': -value, 'balanceBefore': before, 'balanceAfter': before - value, 'reason': reason.text.trim(), 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
      });
      if (dialog.mounted) Navigator.pop(dialog);
    } catch (e) { if (dialog.mounted) ScaffoldMessenger.of(dialog).showSnackBar(SnackBar(content: Text('تعذر حفظ المصروف: $e'))); }
  }, child: const Text('حفظ المصروف'))]));
}

class _InventoryAuditState extends State<InventoryAudit> {
  String category = 'الكل';
  @override Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db.collection('products').snapshots(), builder: (context, products) {
      if (products.hasError) return const Center(child: Text('تعذر تحميل الأصناف'));
      if (!products.hasData) return const Center(child: CircularProgressIndicator());
      final rows = products.data!.docs.where((p) => p.data()['active'] == true).toList();
      final categories = {'الكل', ...rows.map((p) => '${p.data()['category'] ?? 'غير مصنف'}')}.toList()..sort();
      final selected = categories.contains(category) ? category : 'الكل';
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('stock').snapshots(), builder: (context, stock) {
        if (stock.hasError) return const Center(child: Text('تعذر تحميل المخزون'));
        if (!stock.hasData) return const Center(child: CircularProgressIndicator());
        final amounts = <String, int>{};
        for (final entry in stock.data!.docs) {
          final data = entry.data();
          final id = '${data['productId'] ?? ''}';
          if (id.isNotEmpty) amounts[id] = (amounts[id] ?? 0) + ((data['quantity'] as num?)?.toInt() ?? 0);
        }
        final filtered = rows.where((p) => selected == 'الكل' || '${p.data()['category'] ?? 'غير مصنف'}' == selected).toList()..sort((a,b) => '${a.data()['name']}'.compareTo('${b.data()['name']}'));
        return Column(children: [Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<String>(value: selected, decoration: const InputDecoration(labelText: 'الفئة'), items: categories.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => category = v ?? 'الكل'))),
          Text('عدد الأصناف: ${filtered.length}'), Expanded(child: ListView(children: filtered.map((p) { final data = p.data(); return Card(child: ListTile(title: Text('${data['name']}'), subtitle: Text('الفئة: ${data['category'] ?? 'غير مصنف'}\nسعر الشراء: ${data['purchasePrice'] ?? 'غير مسجل'} ج.م • سعر البيع: ${data['price'] ?? 0} ج.م'), isThreeLine: true, trailing: Text('متوفر\n${amounts[p.id] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(color: gold)))); }).toList())) ]);
      });
    });
}

class ProfitReport extends StatefulWidget {
  const ProfitReport({super.key});
  @override State<ProfitReport> createState() => _ProfitReportState();
}

class _ProfitReportState extends State<ProfitReport> {
  String period = 'day';
  @override Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (period) {
      'week' => today.subtract(Duration(days: today.weekday - 1)),
      'month' => DateTime(now.year, now.month, 1),
      _ => today,
    };
    final end = switch (period) {
      'week' => start.add(const Duration(days: 7)),
      'month' => DateTime(now.year, now.month + 1, 1),
      _ => start.add(const Duration(days: 1)),
    };
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'day', label: Text('يومي')),
          ButtonSegment(value: 'week', label: Text('أسبوعي')),
          ButtonSegment(value: 'month', label: Text('شهري'))],
        selected: {period}, onSelectionChanged: (v) => setState(() => period = v.first))),
      Text('من ${DateFormat('dd/MM/yyyy').format(start)} إلى ${DateFormat('dd/MM/yyyy').format(end.subtract(const Duration(days: 1)))}'),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('products').snapshots(),
        builder: (context, productsSnap) {
          if (productsSnap.hasError) return const Center(child: Text('تعذر تحميل تكلفة الأصناف'));
          if (!productsSnap.hasData) return const Center(child: CircularProgressIndicator());
          final products = {for (final p in productsSnap.data!.docs) p.id: p.data()};
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('sales')
              .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
              .where('createdAt', isLessThan: Timestamp.fromDate(end)).snapshots(),
            builder: (context, salesSnap) {
              if (salesSnap.hasError) return const Center(child: Text('تعذر تحميل المبيعات'));
              if (!salesSnap.hasData) return const Center(child: CircularProgressIndicator());
              final sales = salesSnap.data!.docs.where((d) => d.data()['status'] != 'returned').toList();
              double revenue = 0, knownCost = 0;
              int missingCost = 0;
              for (final item in sales) {
                final sale = item.data();
                final qty = (sale['quantity'] as num?)?.toDouble() ?? 0;
                revenue += (sale['total'] as num?)?.toDouble() ?? 0;
                final cost = products['${sale['productId']}']?['purchasePrice'];
                if (cost is num && cost >= 0) {
                  knownCost += qty * cost.toDouble();
                } else { missingCost++; }
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('accountMovements').where('accountType', isEqualTo: 'expenses').snapshots(), builder: (context, expensesSnap) {
                if (expensesSnap.hasError) return const Center(child: Text('تعذر تحميل المصروفات'));
                if (!expensesSnap.hasData) return const Center(child: CircularProgressIndicator());
                final expenses = expensesSnap.data!.docs.where((d) { final date = (d.data()['createdAt'] as Timestamp?)?.toDate(); return date != null && !date.isBefore(start) && date.isBefore(end); }).fold<double>(0, (sum, d) => sum + ((d.data()['amount'] as num?)?.toDouble() ?? 0));
              return ListView(padding: const EdgeInsets.all(16), children: [
                ListTile(title: const Text('عدد فواتير البيع'), trailing: Text('${sales.length}')),
                ListTile(title: const Text('إجمالي المبيعات'), trailing: Text('${revenue.toStringAsFixed(2)} ج.م')),
                ListTile(title: const Text('تكلفة الأصناف المعروفة'), trailing: Text('${knownCost.toStringAsFixed(2)} ج.م')),
                ListTile(title: const Text('المصروفات'), trailing: Text('${expenses.toStringAsFixed(2)} ج.م')),
                ListTile(title: const Text('الربح الإجمالي التقديري'),
                  trailing: Text('${(revenue - knownCost).toStringAsFixed(2)} ج.م',
                    style: const TextStyle(color: gold, fontWeight: FontWeight.bold))),
                ListTile(title: const Text('الربح بعد المصروفات'), trailing: Text('${(revenue - knownCost - expenses).toStringAsFixed(2)} ج.م')),
                if (missingCost > 0) Text('الربح المعروض تقديري: تكلفة الشراء غير مسجلة في $missingCost فاتورة، ولذلك قد يكون الربح الفعلي أقل. أضف تكلفة شراء الأصناف أولًا.'),
                const SizedBox(height: 16),
                const Text('هذا تقدير حسب سعر الشراء المسجل حاليًا للصنف. يشمل المصروفات المسجلة في الفترة، وقد يختلف إذا تغيرت التكلفة بعد البيع.'),
              ]);
              });
            },
          );
        },
      )),
    ]);
  }
}

class Purchases extends StatelessWidget {
  const Purchases({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, children: [
      FilledButton.icon(onPressed: () => purchaseDialog(context), icon: const Icon(Icons.add), label: const Text('فاتورة مشتريات جديدة')),
      OutlinedButton.icon(onPressed: () => scannedPurchaseDialog(context), icon: const Icon(Icons.camera_alt), label: const Text('تصوير فاتورة مشتريات')),
    ])),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('purchases').orderBy('createdAt', descending: true).limit(300).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Text('تعذر تحميل المشتريات'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.docs.isEmpty) return const Center(child: Text('لا توجد فواتير مشتريات بعد'));
        return ListView(children: snap.data!.docs.map((d) { final p = d.data(); return Card(child: ListTile(
          title: Text('فاتورة ${p['invoiceNumber'] ?? d.id.substring(0, 6)} • ${p['supplierName'] ?? ''}'),
          subtitle: Text('${p['productName'] ?? ''} × ${p['quantity'] ?? 0}\n${formatDate(p['createdAt'])}${p['status'] == 'returned' ? ' • مرتجع' : ''}'),
          isThreeLine: true, trailing: Text('${p['total'] ?? 0} ج.م', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
          onTap: () => invoiceActions(context, 'purchases', d.id, p),
        )); }).toList());
      },
    )),
  ]);
}

String formatDate(dynamic value) => value is Timestamp ? DateFormat('dd/MM/yyyy HH:mm').format(value.toDate()) : 'جارٍ الحفظ';

class ScannedLine {
  String? productId;
  final quantity = TextEditingController(text: '1');
  final cost = TextEditingController();
  ScannedLine({this.productId});
  void dispose() { quantity.dispose(); cost.dispose(); }
}

String _ocrKey(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0621-\u064a]'), '');
String _ocrNumber(String value) => value.replaceAllMapped(RegExp(r'[٠-٩]'), (m) => '${m.group(0)!.runes.first - 0x660}').replaceAll('٫', '.').replaceAll('٬', '');

Future<void> scannedPurchaseDialog(BuildContext context) async {
  final products = await db.collection('products').where('active', isEqualTo: true).get();
  final suppliers = await db.collection('suppliers').get();
  if (!context.mounted) return;
  if (products.docs.isEmpty || suppliers.docs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف الأصناف والمورد أولًا'))); return;
  }
  final source = await showModalBottomSheet<ImageSource>(context: context, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
    ListTile(leading: const Icon(Icons.camera_alt), title: const Text('التقاط صورة'), onTap: () => Navigator.pop(c, ImageSource.camera)),
    ListTile(leading: const Icon(Icons.photo_library), title: const Text('اختيار صورة'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
  ])));
  if (source == null) return;
  XFile? photo;
  try { photo = await ImagePicker().pickImage(source: source, imageQuality: 90, maxWidth: 2400); }
  catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر فتح الكاميرا: $e'))); return; }
  if (photo == null || !context.mounted) return;
  final notice = ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري قراءة الفاتورة...'), duration: Duration(minutes: 1)));
  String text = '';
  try { text = await TesseractOcr.extractText(photo.path, config: const OCRConfig(language: 'ara+eng', engine: OCREngine.tesseract)); }
  catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذرت القراءة التلقائية. يمكنك إدخال الفاتورة يدويًا.'))); }
  notice.close();
  if (!context.mounted) return;
  String? supplierId;
  final whole = _ocrKey(text);
  for (final s in suppliers.docs) {
    final name = _ocrKey('${s.data()['name'] ?? ''}');
    if (name.length >= 3 && whole.contains(name)) { supplierId = s.id; break; }
  }
  final lines = <ScannedLine>[];
  for (final row in text.split('\n')) {
    final normalized = _ocrKey(row);
    for (final p in products.docs) {
      final name = _ocrKey('${p.data()['name'] ?? ''}');
      if (name.length >= 3 && normalized.contains(name) && !lines.any((e) => e.productId == p.id)) {
        lines.add(ScannedLine(productId: p.id)); break;
      }
    }
  }
  if (lines.isEmpty) lines.add(ScannedLine());
  final invoice = TextEditingController();
  final paid = TextEditingController(text: '0');
  final markup = TextEditingController();
  bool saving = false;
  await showDialog<void>(context: context, barrierDismissible: false, builder: (outer) => StatefulBuilder(builder: (c, update) => AlertDialog(
    title: const Text('مراجعة فاتورة المشتريات'),
    content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Image.file(File(photo!.path), height: 140),
      const Text('راجع المورد والكمية وسعر الشراء لكل صنف؛ القراءة من الصورة قد تخطئ.', style: TextStyle(color: gold)),
      ExpansionTile(title: const Text('النص المستخرج من الصورة'), children: [SelectableText(text.isEmpty ? 'لم يتم التعرف على النص' : text)]),
      DropdownButtonFormField<String>(initialValue: supplierId, isExpanded: true, decoration: const InputDecoration(labelText: 'المورد *'), items: suppliers.docs.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}', overflow: TextOverflow.ellipsis))).toList(), onChanged: saving ? null : (v) => update(() => supplierId = v)),
      TextField(controller: invoice, decoration: const InputDecoration(labelText: 'رقم فاتورة المورد')),
      for (var i = 0; i < lines.length; i++) Card(key: ObjectKey(lines[i]), child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
        Row(children: [Expanded(child: Text('الصنف ${i + 1}')), IconButton(icon: const Icon(Icons.delete), onPressed: saving || lines.length == 1 ? null : () => update(() => lines.removeAt(i).dispose()))]),
        DropdownButtonFormField<String>(initialValue: lines[i].productId, isExpanded: true, decoration: const InputDecoration(labelText: 'الصنف المسجل *'), items: products.docs.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}', overflow: TextOverflow.ellipsis))).toList(), onChanged: saving ? null : (v) => update(() => lines[i].productId = v)),
        TextField(controller: lines[i].quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية *')),
        TextField(controller: lines[i].cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر الشراء للوحدة *')),
      ]))),
      TextButton.icon(onPressed: saving || lines.length >= 30 ? null : () => update(() => lines.add(ScannedLine())), icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
      TextField(controller: paid, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المدفوع للمورد الآن')),
      TextField(controller: markup, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'زيادة سعر البيع % (اختياري؛ مثل 5 أو 10)'), onChanged: (_) => update(() {})),
      if (double.tryParse(_ocrNumber(markup.text.replaceAll(',', '.'))) case final percent?)
        for (final row in lines)
          if (row.productId != null && double.tryParse(_ocrNumber(row.cost.text.replaceAll(',', '.'))) case final cost?)
            Text('${products.docs.firstWhere((p) => p.id == row.productId).data()['name']}: سعر البيع المقترح ${(cost * (1 + percent / 100)).toStringAsFixed(2)} ج.م'),
    ]))),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(c), child: const Text('إلغاء')), FilledButton(onPressed: saving ? null : () async {
      final entries = <({String id, int qty, double cost})>[];
      var total = 0.0;
      for (final row in lines) {
        final qty = int.tryParse(_ocrNumber(row.quantity.text.trim()));
        final cost = double.tryParse(_ocrNumber(row.cost.text.trim().replaceAll(',', '.')));
        if (row.productId == null || qty == null || qty <= 0 || cost == null || !cost.isFinite || cost < 0 || entries.any((e) => e.id == row.productId)) {
          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('راجع كل صنف وكمية وسعر؛ لا تكرر الصنف'))); return;
        }
        entries.add((id: row.productId!, qty: qty, cost: cost)); total += qty * cost;
      }
      final payment = double.tryParse(_ocrNumber(paid.text.trim().replaceAll(',', '.')));
      final increase = markup.text.trim().isEmpty ? null : double.tryParse(_ocrNumber(markup.text.trim().replaceAll(',', '.')));
      if (markup.text.trim().isNotEmpty && (increase == null || !increase.isFinite || increase < 0 || increase > 1000)) {
        ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('اكتب نسبة زيادة صحيحة من 0 إلى 1000'))); return;
      }
      if (supplierId == null || payment == null || !payment.isFinite || payment < 0 || payment > total) {
        ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('اختر المورد وتأكد من المبلغ المدفوع'))); return;
      }
      update(() => saving = true);
      try {
        final supplier = suppliers.docs.firstWhere((e) => e.id == supplierId).data();
        final group = db.collection('purchases').doc().id;
        await db.runTransaction((tx) async {
          final supplierRef = db.collection('suppliers').doc(supplierId);
          final supplierSnap = await tx.get(supplierRef);
          if (!supplierSnap.exists) throw StateError('المورد غير موجود');
          final stocks = <String, DocumentSnapshot<Map<String, dynamic>>>{};
          for (final e in entries) { stocks[e.id] = await tx.get(db.collection('stock').doc('main_${e.id}')); }
          final before = (supplierSnap.data()?['balance'] as num?)?.toDouble() ?? 0;
          final due = total - payment;
          final actor = FirebaseAuth.instance.currentUser!.uid;
          var paymentRemaining = payment;
          tx.update(supplierRef, {'balance': before + due, 'updatedAt': FieldValue.serverTimestamp()});
          for (final e in entries) {
            final p = products.docs.firstWhere((d) => d.id == e.id).data();
            final old = (stocks[e.id]?.data()?['quantity'] as num?)?.toInt() ?? 0;
            final ref = db.collection('purchases').doc();
            final lineTotal = e.qty * e.cost;
            final linePaid = paymentRemaining < lineTotal ? paymentRemaining : lineTotal;
            paymentRemaining -= linePaid;
            tx.set(db.collection('stock').doc('main_${e.id}'), {'branchId': 'main', 'productId': e.id, 'quantity': old + e.qty}, SetOptions(merge: true));
            tx.update(db.collection('products').doc(e.id), {'purchasePrice': e.cost, if (increase != null) 'price': double.parse((e.cost * (1 + increase / 100)).toStringAsFixed(2)), 'updatedAt': FieldValue.serverTimestamp()});
            tx.set(ref, {'invoiceNumber': invoice.text.trim(), 'scanGroupId': group, 'source': 'camera', 'supplierId': supplierId, 'supplierName': supplier['name'], 'productId': e.id, 'productName': p['name'], 'quantity': e.qty, 'unitCost': e.cost, 'total': lineTotal, 'paid': linePaid, 'due': lineTotal - linePaid, 'status': 'completed', 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
            tx.set(db.collection('stockMovements').doc(), {'productId': e.id, 'productName': p['name'], 'branchId': 'main', 'kind': 'purchase', 'quantity': e.qty, 'balanceAfter': old + e.qty, 'referenceId': ref.id, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
          }
          tx.set(db.collection('accountMovements').doc(), {'accountType': 'suppliers', 'accountId': supplierId, 'accountName': supplier['name'], 'kind': 'purchase', 'amount': due, 'balanceBefore': before, 'balanceAfter': before + due, 'referenceId': group, 'paid': payment, 'createdAt': FieldValue.serverTimestamp(), 'actorId': actor});
        });
        if (c.mounted) Navigator.pop(c);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الفاتورة وتحديث المخزون وحساب المورد')));
      } catch (e) {
        if (c.mounted) { update(() => saving = false); ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'))); }
      }
    }, child: const Text('تأكيد وحفظ'))],
  )));
  for (final row in lines) { row.dispose(); }
  invoice.dispose(); paid.dispose(); markup.dispose();
}

Future<void> purchaseDialog(BuildContext context) async {
  final products = await db.collection('products').where('active', isEqualTo: true).get();
  final suppliers = await db.collection('suppliers').get();
  if (!context.mounted) return;
  if (products.docs.isEmpty || suppliers.docs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف منتجًا وموردًا أولًا')));
    return;
  }
  String productId = products.docs.first.id, supplierId = suppliers.docs.first.id;
  final quantity = TextEditingController(text: '1'), cost = TextEditingController(), paid = TextEditingController(text: '0'), invoice = TextEditingController();
  await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (c, setLocal) => AlertDialog(
    title: const Text('فاتورة مشتريات جديدة'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(initialValue: supplierId, decoration: const InputDecoration(labelText: 'المورد'), items: suppliers.docs.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}'))).toList(), onChanged: (v) { if (v != null) setLocal(() => supplierId = v); }),
      DropdownButtonFormField<String>(initialValue: productId, decoration: const InputDecoration(labelText: 'المنتج'), items: products.docs.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}'))).toList(), onChanged: (v) { if (v != null) setLocal(() => productId = v); }),
      TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية')),
      TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر الشراء للوحدة')),
      TextField(controller: paid, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المدفوع الآن')),
      TextField(controller: invoice, decoration: const InputDecoration(labelText: 'رقم فاتورة المورد (اختياري)')),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')), FilledButton(onPressed: () async {
      final qty = int.tryParse(quantity.text.trim()), unitCost = double.tryParse(cost.text.trim()), paidNow = double.tryParse(paid.text.trim()) ?? 0;
      if (qty == null || qty <= 0 || unitCost == null || unitCost < 0 || paidNow < 0 || paidNow > qty * unitCost) return;
      final product = products.docs.firstWhere((d) => d.id == productId).data(), supplier = suppliers.docs.firstWhere((d) => d.id == supplierId).data();
      try {
        await db.runTransaction((tx) async {
          final stockRef = db.collection('stock').doc('main_$productId'), supplierRef = db.collection('suppliers').doc(supplierId);
          final stockSnap = await tx.get(stockRef), supplierSnap = await tx.get(supplierRef);
          final oldQty = (stockSnap.data()?['quantity'] as num?)?.toInt() ?? 0;
          final oldBalance = (supplierSnap.data()?['balance'] as num?)?.toDouble() ?? 0;
          final total = qty * unitCost, due = total - paidNow, purchaseRef = db.collection('purchases').doc();
          tx.set(stockRef, {'branchId': 'main', 'productId': productId, 'quantity': oldQty + qty}, SetOptions(merge: true));
          tx.update(db.collection('products').doc(productId), {'purchasePrice': unitCost, 'updatedAt': FieldValue.serverTimestamp()});
          tx.update(supplierRef, {'balance': oldBalance + due, 'updatedAt': FieldValue.serverTimestamp()});
          tx.set(purchaseRef, {'invoiceNumber': invoice.text.trim(), 'supplierId': supplierId, 'supplierName': supplier['name'], 'productId': productId, 'productName': product['name'], 'quantity': qty, 'unitCost': unitCost, 'total': total, 'paid': paidNow, 'due': due, 'status': 'completed', 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
          tx.set(db.collection('stockMovements').doc(), {'productId': productId, 'productName': product['name'], 'branchId': 'main', 'kind': 'purchase', 'quantity': qty, 'balanceAfter': oldQty + qty, 'referenceId': purchaseRef.id, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
          tx.set(db.collection('accountMovements').doc(), {'accountType': 'suppliers', 'accountId': supplierId, 'accountName': supplier['name'], 'kind': 'purchase', 'amount': due, 'balanceBefore': oldBalance, 'balanceAfter': oldBalance + due, 'referenceId': purchaseRef.id, 'createdAt': FieldValue.serverTimestamp(), 'actorId': FirebaseAuth.instance.currentUser!.uid});
        });
        if (c.mounted) Navigator.pop(c);
      } catch (e) { if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('تعذر حفظ الفاتورة: $e'))); }
    }, child: const Text('حفظ الفاتورة'))],
  )));
}

class AccountMovements extends StatelessWidget {
  const AccountMovements({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db.collection('accountMovements').orderBy('createdAt', descending: true).limit(500).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return const Center(child: Text('تعذر تحميل الحركات'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.docs.isEmpty) return const Center(child: Text('لا توجد حركات بعد'));
      return ListView(children: snap.data!.docs.map((d) { final m = d.data(); return ListTile(title: Text('${m['accountName'] ?? ''} • ${movementName('${m['kind']}')}'), subtitle: Text(formatDate(m['createdAt'])), trailing: Text('${m['amount'] ?? 0} ج.م')); }).toList());
    },
  );
}

String movementName(String kind) => switch (kind) { 'purchase' => 'مشتريات', 'payment' => 'سداد مورد', 'collection' => 'تحصيل عميل', 'sale' => 'مبيعات', 'sales_return' => 'مرتجع مبيعات', 'purchase_return' => 'مرتجع مشتريات', 'transfer_in' => 'تحويل وارد', 'transfer_out' => 'تحويل صادر', 'adjustment' => 'تسوية مخزون', _ => kind };

Future<void> assignEmployee(BuildContext context, String uid, Map<String, dynamic> data) async {
  final name = TextEditingController(text: '${data['name'] ?? ''}');
  final branches = await db.collection('branches').get();
  if (!context.mounted) return;
  if (branches.docs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف فرعًا أولًا')));
    return;
  }
  String selected = branches.docs.any((d) => d.id == data['branchId'])
      ? data['branchId'] as String : branches.docs.first.id;
  bool enabled = data['active'] == true;
  bool canPrint = data['canPrint'] == true;
  await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
    builder: (c, setDialogState) => AlertDialog(
      title: const Text('صلاحيات الموظف'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الموظف')),
        DropdownButtonFormField<String>(initialValue: selected,
          decoration: const InputDecoration(labelText: 'الفرع'),
          items: branches.docs.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}'))).toList(),
          onChanged: (v) { if (v != null) setDialogState(() => selected = v); }),
        SwitchListTile(title: const Text('تفعيل الدخول'), value: enabled,
          onChanged: (v) => setDialogState(() => enabled = v)),
        SwitchListTile(title: const Text('السماح بطباعة الفواتير'), value: canPrint,
          onChanged: (v) => setDialogState(() => canPrint = v)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(onPressed: () async {
          if (name.text.trim().isEmpty) return;
          try {
            await db.collection('users').doc(uid).update({
              'name': name.text.trim(), 'role': 'employee', 'branchId': selected,
              'active': enabled, 'canPrint': canPrint,
            });
            if (c.mounted) Navigator.pop(c);
          } catch (_) {
            if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('تعذر حفظ صلاحيات الموظف')));
          }
        }, child: const Text('حفظ'))],
    ),
  ));
}

Future<void> mainStockDialog(BuildContext context, String productId, String name) async {
  final desired = TextEditingController();
  final reason = TextEditingController();
  final stockRef = db.collection('stock').doc('main_$productId');
  final current = await stockRef.get();
  if (!context.mounted) return;
  final original = (current.data()?['quantity'] as num?)?.toInt() ?? 0;
  desired.text = '$original';
  await showDialog<void>(context: context, builder: (c) => AlertDialog(
    title: Text('تسوية المخزون الرئيسي: $name'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('الرصيد الحالي: $original'),
      TextField(controller: desired, keyboardType: const TextInputType.numberWithOptions(signed: true),
        decoration: const InputDecoration(labelText: 'الرصيد الصحيح بعد التسوية')),
      TextField(controller: reason, maxLength: 160,
        decoration: const InputDecoration(labelText: 'سبب التسوية')),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')), FilledButton(onPressed: () async {
      final target = int.tryParse(desired.text.trim());
      if (target == null || reason.text.trim().isEmpty) {
        ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('اكتب الرصيد الصحيح وسبب التسوية')));
        return;
      }
      try {
        await db.runTransaction((tx) async {
          final snapshot = await tx.get(stockRef);
          final before = (snapshot.data()?['quantity'] as num?)?.toInt() ?? 0;
          if (before != original) throw Exception('الرصيد اتغير؛ افتح التسوية مرة تانية');
          if (before == target) throw Exception('الرصيد الجديد مطابق للحالي');
          tx.set(stockRef, {'branchId': 'main', 'productId': productId, 'quantity': target});
          tx.set(db.collection('stockAdjustments').doc(), {
            'productId': productId, 'productName': name, 'branchId': 'main',
            'before': before, 'after': target, 'delta': target - before,
            'reason': reason.text.trim(), 'actorId': FirebaseAuth.instance.currentUser!.uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.set(db.collection('stockMovements').doc(), {'productId': productId, 'productName': name, 'branchId': 'main', 'kind': 'adjustment', 'quantity': target - before, 'balanceAfter': target, 'reason': reason.text.trim(), 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
        });
        if (c.mounted) Navigator.pop(c);
      } catch (e) { if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('تعذر التسوية: $e'))); }
    }, child: const Text('حفظ التسوية'))],
  ));
}

class Accounts extends StatefulWidget {
  const Accounts({super.key});
  @override
  State<Accounts> createState() => _AccountsState();
}
class _AccountsState extends State<Accounts> {
  bool suppliers = false;
  @override
  Widget build(BuildContext context) {
    final collection = suppliers ? 'suppliers' : 'customers';
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(children: [SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('العملاء')), ButtonSegment(value: true, label: Text('الموردون'))],
        selected: {suppliers}, onSelectionChanged: (values) => setState(() => suppliers = values.first)),
        const SizedBox(height: 8), FilledButton.icon(onPressed: () => createAccountDialog(context, collection, suppliers), icon: const Icon(Icons.person_add), label: Text(suppliers ? 'إضافة مورد' : 'إضافة عميل')),
      ])),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection(collection).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('تعذر تحميل الذمم'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs.toList()..sort((a,b) =>
              '${a.data()['name'] ?? ''}'.compareTo('${b.data()['name'] ?? ''}'));
          if (docs.isEmpty) return const Center(child: Text('لا توجد حسابات بعد'));
          return ListView.builder(itemCount: docs.length, itemBuilder: (context, index) {
            final d = docs[index], account = d.data();
            return ListTile(
              title: Text('${account['name'] ?? ''}'),
              subtitle: Text('هاتف: ${account['phone'] ?? 'غير مسجل'}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                Text('${account['balance'] ?? 0} ج.م', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
                const Text('الرصيد الحالي'),
              ]),
              onTap: () => accountDialog(context, collection, d.id, account),
            );
          });
        },
      )),
    ]);
  }
}

Future<void> createAccountDialog(BuildContext context, String collection, bool supplier) async {
  final name = TextEditingController(), phone = TextEditingController(), opening = TextEditingController(text: '0');
  await showDialog<void>(context: context, builder: (c) => AlertDialog(
    title: Text(supplier ? 'إضافة مورد' : 'إضافة عميل'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
      TextField(controller: opening, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي')),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')), FilledButton(onPressed: () async {
      final balance = double.tryParse(opening.text.trim());
      if (name.text.trim().isEmpty || balance == null || !balance.isFinite) return;
      try {
        final ref = db.collection(collection).doc();
        await db.runTransaction((tx) async {
          tx.set(ref, {'name': name.text.trim(), 'phone': phone.text.trim(), 'openingBalance': balance, 'balance': balance, 'active': true, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
          if (balance != 0) tx.set(db.collection('accountMovements').doc(), {'accountType': collection, 'accountId': ref.id, 'accountName': name.text.trim(), 'kind': 'opening', 'amount': balance.abs(), 'balanceBefore': 0, 'balanceAfter': balance, 'createdAt': FieldValue.serverTimestamp(), 'actorId': FirebaseAuth.instance.currentUser!.uid});
        });
        if (c.mounted) Navigator.pop(c);
      } catch (e) { if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'))); }
    }, child: const Text('حفظ'))],
  ));
}

Future<void> accountDialog(BuildContext context, String collection, String id, Map<String, dynamic> account) async {
  final amount = TextEditingController();
  final isSupplier = collection == 'suppliers';
  await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
    title: Text('${account['name'] ?? ''}'),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('رصيد البداية: ${account['openingBalance'] ?? 0} ج.م'),
      Text('الرصيد الحالي: ${account['balance'] ?? 0} ج.م'),
      const SizedBox(height: 14),
      TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: isSupplier ? 'مبلغ السداد' : 'مبلغ التحصيل')),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
      FilledButton(onPressed: () async {
        final paid = double.tryParse(amount.text.trim());
        if (paid == null || !paid.isFinite || paid <= 0) return;
        try {
          await db.runTransaction((tx) async {
            final ref = db.collection(collection).doc(id);
            final snapshot = await tx.get(ref);
            final cashRef = db.collection('settings').doc('cash');
            final cash = await tx.get(cashRef);
            final balance = (snapshot.data()?['balance'] as num?)?.toDouble();
            if (balance == null || paid > balance) throw Exception('المبلغ أكبر من الرصيد الحالي');
            final beforeCash = (cash.data()?['balance'] as num?)?.toDouble() ?? 0;
            final cashDelta = isSupplier ? -paid : paid;
            if (beforeCash + cashDelta < 0) throw Exception('رصيد الصندوق لا يكفي');
            tx.update(ref, {'balance': balance - paid, 'updatedAt': FieldValue.serverTimestamp()});
            tx.set(db.collection('accountMovements').doc(), {
              'accountType': collection, 'accountId': id, 'accountName': snapshot.data()?['name'],
              'kind': isSupplier ? 'payment' : 'collection', 'amount': paid,
              'balanceBefore': balance, 'balanceAfter': balance - paid,
              'createdAt': FieldValue.serverTimestamp(),
              'actorId': FirebaseAuth.instance.currentUser!.uid,
            });
            tx.set(cashRef, {'balance': beforeCash + cashDelta,
              'updatedAt': FieldValue.serverTimestamp()});
            tx.set(db.collection('accountMovements').doc(), {
              'accountType': 'cash',
              'kind': isSupplier ? 'supplierPayment' : 'customerCollection',
              'accountId': id, 'accountName': snapshot.data()?['name'],
              'amount': paid, 'delta': cashDelta,
              'balanceBefore': beforeCash, 'balanceAfter': beforeCash + cashDelta,
              'reason': isSupplier ? 'سداد مورد' : 'تحصيل عميل',
              'actorId': FirebaseAuth.instance.currentUser!.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
          });
          if (dialogContext.mounted) Navigator.pop(dialogContext);
        } catch (e) {
          if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('تعذر تسجيل الحركة: $e')));
        }
      }, child: Text(isSupplier ? 'تسجيل السداد' : 'تسجيل التحصيل'))],
  ));
}

class CashBox extends StatelessWidget {
  const CashBox({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('settings').doc('cash').snapshots(),
      builder: (context, snap) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('رصيد الصندوق: ${snap.data?.data()?['balance'] ?? 0} ج.م',
          style: const TextStyle(fontSize: 22, color: gold)),
      ),
    ),
    Wrap(spacing: 12, children: [
      FilledButton.icon(onPressed: () => cashDialog(context, true),
        icon: const Icon(Icons.add), label: const Text('إضافة للصندوق')),
      OutlinedButton.icon(onPressed: () => cashDialog(context, false),
        icon: const Icon(Icons.remove), label: const Text('خصم من الصندوق')),
    ]),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('accountMovements').where('accountType', isEqualTo: 'cash').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Text('تعذر عرض حركة الصندوق'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!.docs.toList()..sort((a, b) =>
          ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
          .compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
        if (rows.isEmpty) return const Center(child: Text('لا توجد حركات للصندوق'));
        return ListView.builder(itemCount: rows.length, itemBuilder: (context, i) {
          final m = rows[i].data();
          final date = m['createdAt'] is Timestamp
            ? DateFormat('dd/MM/yyyy HH:mm').format((m['createdAt'] as Timestamp).toDate())
            : 'جارٍ الحفظ';
          return ListTile(title: Text('${m['reason'] ?? ''}'),
            subtitle: Text('$date • بواسطة ${m['actorId'] ?? ''}'),
            trailing: Text('${(m['delta'] as num?)?.toDouble() ?? 0} ج.م',
              style: const TextStyle(color: gold)));
        });
      },
    )),
  ]);
}

Future<void> cashDialog(BuildContext context, bool deposit) async {
  final amount = TextEditingController(), reason = TextEditingController();
  await showDialog<void>(context: context, builder: (c) => AlertDialog(
    title: Text(deposit ? 'إضافة للصندوق' : 'خصم من الصندوق'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'المبلغ')),
      TextField(controller: reason, maxLength: 160,
        decoration: const InputDecoration(labelText: 'سبب الحركة')),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
      FilledButton(onPressed: () async {
        final value = double.tryParse(amount.text.trim());
        if (value == null || !value.isFinite || value <= 0 || reason.text.trim().isEmpty) {
          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('اكتب مبلغ صحيح وسبب الحركة')));
          return;
        }
        try {
          await db.runTransaction((tx) async {
            final ref = db.collection('settings').doc('cash');
            final snapshot = await tx.get(ref);
            final before = (snapshot.data()?['balance'] as num?)?.toDouble() ?? 0;
            final delta = deposit ? value : -value;
            if (before + delta < 0) throw Exception('رصيد الصندوق لا يكفي');
            tx.set(ref, {'balance': before + delta, 'updatedAt': FieldValue.serverTimestamp()});
            tx.set(db.collection('accountMovements').doc(), {
              'accountType': 'cash',
              'kind': deposit ? 'deposit' : 'withdrawal', 'amount': value,
              'delta': delta, 'balanceBefore': before, 'balanceAfter': before + delta,
              'reason': reason.text.trim(),
              'actorId': FirebaseAuth.instance.currentUser!.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
          });
          if (c.mounted) Navigator.pop(c);
        } catch (e) {
          if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('تعذر حفظ الحركة: $e')));
        }
      }, child: const Text('حفظ الحركة'))],
  ));
}

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});
  @override State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  final company = TextEditingController(text: 'VIB للتجارة والتوزيع');
  final phone = TextEditingController(), whatsapp = TextEditingController(), address = TextEditingController();
  String paper = 'a4';
  bool loading = true, saving = false;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    final d = (await db.collection('settings').doc('main').get()).data();
    if (d != null) {
      company.text = '${d['companyName'] ?? company.text}'; phone.text = '${d['phone'] ?? ''}';
      whatsapp.text = '${d['whatsapp'] ?? ''}'; address.text = '${d['address'] ?? ''}';
      paper = ['a4', '58', '80'].contains(d['paperSize']) ? '${d['paperSize']}' : 'a4';
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> save() async {
    if (company.text.trim().isEmpty) return;
    setState(() => saving = true);
    try {
      await db.collection('settings').doc('main').set({'companyName': company.text.trim(), 'phone': phone.text.trim(), 'whatsapp': whatsapp.text.trim(), 'address': address.text.trim(), 'paperSize': paper, 'updatedAt': FieldValue.serverTimestamp(), 'updatedBy': FirebaseAuth.instance.currentUser!.uid}, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'))); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override Widget build(BuildContext context) => loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
    TextField(controller: company, decoration: const InputDecoration(labelText: 'اسم الشركة على الفاتورة')),
    TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
    TextField(controller: whatsapp, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم واتساب')),
    TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
    const SizedBox(height: 12), const Text('إعدادات الطباعة', style: TextStyle(color: gold, fontSize: 20)),
    DropdownButtonFormField<String>(value: paper, decoration: const InputDecoration(labelText: 'مقاس ورق الفاتورة'), items: const [DropdownMenuItem(value: 'a4', child: Text('A4 عادي')), DropdownMenuItem(value: '58', child: Text('إيصال حراري 58 مم')), DropdownMenuItem(value: '80', child: Text('إيصال حراري 80 مم'))], onChanged: (v) => setState(() => paper = v ?? 'a4')),
    const SizedBox(height: 20), FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.save), label: const Text('حفظ الإعدادات')),
    const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => printTestPage(context, paper), icon: const Icon(Icons.print), label: const Text('اختيار الطابعة وطباعة صفحة تجربة')),
    const Text('طابعة البلوتوث تظهر في شاشة الطباعة إذا كانت متصلة بالموبايل ولها خدمة طباعة متوافقة.'),
    const SizedBox(height: 14), const Card(child: ListTile(leading: Icon(Icons.cloud_done, color: gold), title: Text('حفظ البيانات طويل المدة'), subtitle: Text('الفواتير والحركات لا تُحذف وتظل محفوظة في قاعدة البيانات.'))),
  ]);
}

PdfPageFormat invoicePageFormat(String paper) => switch (paper) {
  '58' => PdfPageFormat(58 * PdfPageFormat.mm, 180 * PdfPageFormat.mm, marginAll: 3 * PdfPageFormat.mm),
  '80' => PdfPageFormat(80 * PdfPageFormat.mm, 180 * PdfPageFormat.mm, marginAll: 4 * PdfPageFormat.mm),
  _ => PdfPageFormat.a4,
};

Future<void> printTestPage(BuildContext context, String paper) async {
  try {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final pdf = pw.Document();
    pdf.addPage(pw.Page(pageFormat: invoicePageFormat(paper), build: (_) => pw.Center(child: pw.Text('VIB للتجارة والتوزيع\nتجربة الطباعة\n${paper == 'a4' ? 'A4' : '$paper مم'}', textAlign: pw.TextAlign.center,
      style: pw.TextStyle(font: font, fontSize: paper == 'a4' ? 22 : 11)))));
    await Printing.layoutPdf(name: 'VIB-PRINT-TEST.pdf', onLayout: (_) => pdf.save());
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر فتح الطباعة: $e')));
  }
}

Future<void> invoiceActions(BuildContext context, String type, String id, Map<String, dynamic> data, {bool canReturn = true}) async {
  final returned = data['status'] == 'returned';
  final profile = (await db.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get()).data();
  if (!context.mounted) return;
  final canPrint = profile?['role'] == 'owner' || profile?['canPrint'] == true;
  await showModalBottomSheet<void>(context: context, builder: (c) => SafeArea(child: Wrap(children: [
    ListTile(leading: const Icon(Icons.picture_as_pdf, color: gold), title: const Text('حفظ أو مشاركة الفاتورة PDF'), onTap: () { Navigator.pop(c); exportInvoicePdf(context, type, id, data); }),
    if (type == 'sales' && profile?['role'] == 'owner' && !returned) ListTile(leading: const Icon(Icons.edit_note, color: gold), title: const Text('تصحيح فاتورة البيع'), onTap: () { Navigator.pop(c); correctSaleDialog(context, id, data); }),
    if (canPrint) ListTile(leading: const Icon(Icons.print, color: gold), title: Text(data['printedAt'] == null ? 'طباعة الفاتورة' : 'إعادة طباعة الفاتورة'), onTap: () { Navigator.pop(c); selectInvoicePaper(context, type, id, data); }),
    if (type == 'sales' && '${data['customerPhone'] ?? ''}'.trim().isNotEmpty) ListTile(leading: const Icon(Icons.chat, color: Colors.greenAccent), title: const Text('إرسال للزبون على واتساب'), onTap: () { Navigator.pop(c); sendInvoiceWhatsApp(context, id, data); }),
    if (canReturn) ListTile(leading: Icon(Icons.undo, color: returned ? Colors.grey : Colors.redAccent), title: Text(returned ? 'تم إرجاع الفاتورة' : type == 'sales' ? 'إرجاع فاتورة المبيعات' : 'إرجاع فاتورة المشتريات'), enabled: !returned, onTap: returned ? null : () { Navigator.pop(c); confirmReturn(context, type, id, data); }),
  ])));
}

Future<void> correctSaleDialog(BuildContext context, String id, Map<String, dynamic> data) async {
  final quantity = TextEditingController(text: '${data['quantity'] ?? 1}');
  final price = TextEditingController(text: '${data['unitPrice'] ?? 0}');
  final reason = TextEditingController();
  await showDialog<void>(context: context, builder: (dialog) => AlertDialog(title: const Text('تصحيح فاتورة بيع'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Text('ستبقى الفاتورة الأصلية محفوظة كمرتجع، وتُنشأ فاتورة بديلة مع تعديل المخزون.'),
    TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية الجديدة')),
    TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر البيع الجديد')),
    TextField(controller: reason, decoration: const InputDecoration(labelText: 'سبب التصحيح (إلزامي)')),
  ])), actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إلغاء')), FilledButton(onPressed: () async {
    final qty = int.tryParse(quantity.text), unit = double.tryParse(price.text);
    if (qty == null || qty <= 0 || unit == null || !unit.isFinite || unit < 0 || reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(dialog).showSnackBar(const SnackBar(content: Text('أدخل كمية وسعرًا صحيحين وسبب التصحيح'))); return;
    }
    final replacement = db.collection('sales').doc();
    try {
      await db.runTransaction((tx) async {
        final oldRef = db.collection('sales').doc(id), old = await tx.get(oldRef);
        if (!old.exists || old.data()?['status'] != 'completed') throw Exception('الفاتورة غير متاحة للتصحيح');
        final original = old.data()!;
        final productId = '${original['productId']}', branch = '${original['branchId']}';
        final stockRef = db.collection('stock').doc('${branch}_$productId');
        final stock = await tx.get(stockRef);
        final product = await tx.get(db.collection('products').doc(productId));
        final oldQty = (original['quantity'] as num).toInt();
        final current = (stock.data()?['quantity'] as num?)?.toInt() ?? 0;
        final balance = current + oldQty - qty;
        if (balance < 0) throw Exception('الكمية الجديدة تتجاوز المخزون؛ صحح المخزون أو استخدم عملية بيع بموافقة المدير');
        final cost = (product.data()?['purchasePrice'] as num?)?.toDouble();
        if (cost != null && unit < cost) throw Exception('السعر الجديد أقل من تكلفة الشراء');
        tx.update(oldRef, {'status': 'returned', 'returnedAt': FieldValue.serverTimestamp(), 'returnId': replacement.id});
        tx.set(replacement, {'branchId': branch, 'employeeId': FirebaseAuth.instance.currentUser!.uid, 'customerPhone': original['customerPhone'] ?? '', 'productId': productId, 'productName': original['productName'], 'quantity': qty, 'unitPrice': unit, 'total': qty * unit, 'status': 'completed', 'createdAt': FieldValue.serverTimestamp(), 'correctsInvoiceId': id, 'correctionReason': reason.text.trim()});
        tx.set(stockRef, {'branchId': branch, 'productId': productId, 'quantity': balance, 'lastSaleId': replacement.id}, SetOptions(merge: true));
        for (final move in [('correction_return', oldQty, current + oldQty, id), ('correction_sale', -qty, balance, replacement.id)]) {
          tx.set(db.collection('stockMovements').doc(), {'productId': productId, 'productName': original['productName'], 'branchId': branch, 'kind': move.$1, 'quantity': move.$2, 'balanceAfter': move.$3, 'referenceId': move.$4, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'reason': reason.text.trim(), 'createdAt': FieldValue.serverTimestamp()});
        }
      });
      if (dialog.mounted) Navigator.pop(dialog);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم التصحيح، رقم الفاتورة الجديدة: ${replacement.id}')));
    } catch (e) { if (dialog.mounted) ScaffoldMessenger.of(dialog).showSnackBar(SnackBar(content: Text('تعذر التصحيح: $e'))); }
  }, child: const Text('حفظ التصحيح'))]));
}

Future<void> sendInvoiceWhatsApp(BuildContext context, String id, Map<String, dynamic> data) async {
  var phone = '${data['customerPhone'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
  if (phone.startsWith('0')) phone = '20${phone.substring(1)}';
  if (phone.startsWith('00')) phone = phone.substring(2);
  final message = 'فاتورة مبيعات VIB رقم $id\nالصنف: ${data['productName']}\nالكمية: ${data['quantity']}\nالإجمالي: ${data['total']} ج.م\nشكراً لتعاملكم معنا';
  final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح واتساب')));
}

Future<void> selectInvoicePaper(BuildContext context, String type, String id, Map<String, dynamic> data) async {
  final selected = await showModalBottomSheet<String>(context: context, builder: (sheet) => SafeArea(child: Wrap(children: [
    const ListTile(title: Text('مقاس ورق الفاتورة')),
    for (final choice in [('a4', 'ورق A4'), ('58', 'إيصال 58 مم'), ('80', 'إيصال 80 مم')]) ListTile(title: Text(choice.$2), onTap: () => Navigator.pop(sheet, choice.$1)),
  ])));
  if (selected != null && context.mounted) await printInvoice(context, type, id, data, paperChoice: selected);
}

Future<Uint8List> createInvoicePdf(String type, String id, Map<String, dynamic> data, {String? paperChoice}) async {
    Map<String, dynamic> settings = {};
    try {
      settings = (await db.collection('settings').doc('main').get()).data() ?? {};
    } catch (_) {
      // The employee may print an authorized sale even if company settings are owner-only.
    }
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final logo = pw.MemoryImage((await rootBundle.load('assets/icons/manager/mipmap-xxxhdpi/ic_launcher.png')).buffer.asUint8List());
    final pdf = pw.Document();
    final isSale = type == 'sales';
    final unit = data[isSale ? 'unitPrice' : 'unitCost'] ?? 0;
    final paper = paperChoice ?? (['a4', '58', '80'].contains(settings['paperSize']) ? '${settings['paperSize']}' : 'a4');
    final thermal = paper != 'a4';
    pdf.addPage(pw.Page(pageFormat: invoicePageFormat(paper), theme: pw.ThemeData.withFont(base: font, bold: font), build: (_) => pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Padding(padding: pw.EdgeInsets.all(thermal ? 2 : 28), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Center(child: pw.Image(logo, width: thermal ? 34 : 76, height: thermal ? 34 : 76)),
      pw.SizedBox(height: 8),
      pw.Center(child: pw.Text('${settings['companyName'] ?? 'VIB للتجارة والتوزيع'}', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: thermal ? 11 : 24, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 6), pw.Center(child: pw.Text('${settings['address'] ?? ''}  ${settings['phone'] ?? ''}')),
      pw.Divider(), pw.Text(isSale ? 'فاتورة مبيعات' : 'فاتورة مشتريات', style: pw.TextStyle(fontSize: thermal ? 12 : 20, fontWeight: pw.FontWeight.bold)),
      pw.Text('رقم الفاتورة: ${data['invoiceNumber']?.toString().isNotEmpty == true ? data['invoiceNumber'] : id}', style: pw.TextStyle(fontSize: thermal ? 8 : 12)), pw.Text('التاريخ: ${formatDate(data['createdAt'])}', style: pw.TextStyle(fontSize: thermal ? 9 : 12)),
      if (!isSale) pw.Text('المورد: ${data['supplierName'] ?? ''}'), pw.SizedBox(height: 18),
      if (thermal) pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [pw.Text('الصنف: ${data['productName'] ?? ''}', style: const pw.TextStyle(fontSize: 9)), pw.Text('الكمية: ${data['quantity'] ?? 0} × $unit ج.م', style: const pw.TextStyle(fontSize: 9)), pw.Divider()]) else pw.Table(border: pw.TableBorder.all(), children: [
        pw.TableRow(children: ['الإجمالي', 'سعر الوحدة', 'الكمية', 'الصنف'].map((v) => pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(v, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)))).toList()),
        pw.TableRow(children: ['${data['total'] ?? 0}', '$unit', '${data['quantity'] ?? 0}', '${data['productName'] ?? ''}'].map((v) => pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(v, textAlign: pw.TextAlign.center))).toList()),
      ]), pw.SizedBox(height: thermal ? 6 : 16), pw.Text('الإجمالي: ${data['total'] ?? 0} ج.م', style: pw.TextStyle(fontSize: thermal ? 11 : 18, fontWeight: pw.FontWeight.bold)),
      if (!isSale) pw.Text('المدفوع: ${data['paid'] ?? 0} ج.م     المتبقي: ${data['due'] ?? 0} ج.م'),
      if (data['status'] == 'returned') pw.Text('فاتورة مرتجعة', style: const pw.TextStyle(color: PdfColors.red, fontSize: 18)),
    ])))));
    return pdf.save();
}

Future<void> exportInvoicePdf(BuildContext context, String type, String id, Map<String, dynamic> data) async {
  try {
    final bytes = await createInvoicePdf(type, id, data, paperChoice: 'a4');
    await Printing.sharePdf(bytes: bytes, filename: '${type == 'sales' ? 'VIB-SALE' : 'VIB-PURCHASE'}-$id.pdf');
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء PDF: $e')));
  }
}

Future<void> printInvoice(BuildContext context, String type, String id, Map<String, dynamic> data, {String? paperChoice}) async {
  try {
    final bytes = await createInvoicePdf(type, id, data, paperChoice: paperChoice);
    await Printing.layoutPdf(name: '${type == 'sales' ? 'VIB-SALE' : 'VIB-PURCHASE'}-$id.pdf', onLayout: (_) async => bytes);
    await db.collection(type).doc(id).set({'printedAt': FieldValue.serverTimestamp(), 'printedBy': FirebaseAuth.instance.currentUser!.uid}, SetOptions(merge: true));
  } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الطباعة: $e'))); }
}

Future<void> confirmReturn(BuildContext context, String type, String id, Map<String, dynamic> data) async {
  final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('تأكيد المرتجع'), content: const Text('سيتم عكس حركة المخزون والحساب، وستظل الفاتورة الأصلية محفوظة.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد المرتجع'))])) ?? false;
  if (!yes || !context.mounted) return;
  try {
    await returnInvoice(type, id);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل المرتجع وحفظ الفاتورة الأصلية')));
  } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر المرتجع: $e'))); }
}

Future<void> returnInvoice(String type, String id) async {
  await db.runTransaction((tx) async {
    final invoiceRef = db.collection(type).doc(id), invoiceSnap = await tx.get(invoiceRef), d = invoiceSnap.data();
    if (d == null) throw Exception('الفاتورة غير موجودة');
    if (d['status'] == 'returned') throw Exception('الفاتورة مرتجعة بالفعل');
    final qty = (d['quantity'] as num).toInt(), productId = '${d['productId']}', now = FieldValue.serverTimestamp();
    if (type == 'sales') {
      final stockRef = db.collection('stock').doc('${d['branchId']}_$productId'), stock = await tx.get(stockRef), before = (stock.data()?['quantity'] as num?)?.toInt() ?? 0;
      final ret = db.collection('salesReturns').doc();
      tx.set(stockRef, {'branchId': d['branchId'], 'productId': productId, 'quantity': before + qty}, SetOptions(merge: true));
      tx.set(ret, {...d, 'sourceInvoiceId': id, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': now});
      tx.set(db.collection('stockMovements').doc(), {'productId': productId, 'productName': d['productName'], 'branchId': d['branchId'], 'kind': 'sales_return', 'quantity': qty, 'balanceAfter': before + qty, 'referenceId': ret.id, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': now});
      tx.update(invoiceRef, {'status': 'returned', 'returnedAt': now, 'returnId': ret.id});
    } else {
      final stockRef = db.collection('stock').doc('main_$productId'), stock = await tx.get(stockRef), before = (stock.data()?['quantity'] as num?)?.toInt() ?? 0;
      if (before < qty) throw Exception('المخزون الرئيسي لا يكفي لإرجاع الفاتورة');
      final supplierRef = db.collection('suppliers').doc('${d['supplierId']}'), supplier = await tx.get(supplierRef), oldBalance = (supplier.data()?['balance'] as num?)?.toDouble() ?? 0, due = (d['due'] as num?)?.toDouble() ?? 0;
      final ret = db.collection('purchaseReturns').doc();
      tx.set(stockRef, {'branchId': 'main', 'productId': productId, 'quantity': before - qty}, SetOptions(merge: true));
      tx.update(supplierRef, {'balance': oldBalance - due, 'updatedAt': now});
      tx.set(ret, {...d, 'sourceInvoiceId': id, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': now});
      tx.set(db.collection('accountMovements').doc(), {'accountType': 'suppliers', 'accountId': d['supplierId'], 'accountName': d['supplierName'], 'kind': 'purchase_return', 'amount': due, 'balanceBefore': oldBalance, 'balanceAfter': oldBalance - due, 'referenceId': ret.id, 'createdAt': now, 'actorId': FirebaseAuth.instance.currentUser!.uid});
      tx.set(db.collection('stockMovements').doc(), {'productId': productId, 'productName': d['productName'], 'branchId': 'main', 'kind': 'purchase_return', 'quantity': -qty, 'balanceAfter': before - qty, 'referenceId': ret.id, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': now});
      tx.update(invoiceRef, {'status': 'returned', 'returnedAt': now, 'returnId': ret.id});
    }
  });
}

class ItemMovementReport extends StatefulWidget {
  const ItemMovementReport({super.key});
  @override State<ItemMovementReport> createState() => _ItemMovementReportState();
}
class _ItemMovementReportState extends State<ItemMovementReport> {
  String? productId, branchId;
  DateTimeRange? range;
  @override Widget build(BuildContext context) => Column(children: [
    FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(future: Future.wait([db.collection('products').get(), db.collection('branches').get()]), builder: (context, snap) {
      if (!snap.hasData) return const LinearProgressIndicator();
      final products = snap.data![0].docs, branches = snap.data![1].docs;
      return Padding(padding: const EdgeInsets.all(10), child: Column(children: [
        DropdownButtonFormField<String>(initialValue: productId, decoration: const InputDecoration(labelText: 'الصنف'), items: products.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}'))).toList(), onChanged: (v) => setState(() => productId = v)),
        DropdownButtonFormField<String>(initialValue: branchId, decoration: const InputDecoration(labelText: 'الفرع (الكل)'), items: [const DropdownMenuItem<String>(value: null, child: Text('كل الفروع')), const DropdownMenuItem(value: 'main', child: Text('المخزون الرئيسي')), ...branches.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}')))], onChanged: (v) => setState(() => branchId = v)),
        TextButton.icon(onPressed: () async { final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1))); if (r != null) setState(() => range = r); }, icon: const Icon(Icons.date_range), label: Text(range == null ? 'كل الفترات' : '${DateFormat('dd/MM/yyyy').format(range!.start)} - ${DateFormat('dd/MM/yyyy').format(range!.end)}')),
      ]));
    }),
    Expanded(child: productId == null ? const Center(child: Text('اختر الصنف لعرض حركته')) : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('stockMovements').where('productId', isEqualTo: productId).snapshots(), builder: (context, snap) {
      if (snap.hasError) return const Center(child: Text('تعذر تحميل حركة الصنف'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snap.data!.docs.where((d) { final x = d.data(), date = (x['createdAt'] as Timestamp?)?.toDate(); return (branchId == null || x['branchId'] == branchId) && (range == null || (date != null && !date.isBefore(range!.start) && date.isBefore(range!.end.add(const Duration(days: 1))))); }).toList()..sort((a,b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
      final incoming = rows.fold<num>(0, (s,d) => s + ((d.data()['quantity'] as num?) ?? 0).clamp(0, 999999999)), outgoing = rows.fold<num>(0, (s,d) => s + (-((d.data()['quantity'] as num?) ?? 0)).clamp(0, 999999999));
      return Column(children: [Padding(padding: const EdgeInsets.all(8), child: Text('داخل: $incoming   •   خارج: $outgoing   •   عدد الحركات: ${rows.length}', style: const TextStyle(color: gold, fontWeight: FontWeight.bold))), Expanded(child: ListView(children: rows.map((d) { final x=d.data(), q=(x['quantity'] as num?) ?? 0; return ListTile(leading: Icon(q >= 0 ? Icons.south : Icons.north, color: q >= 0 ? Colors.greenAccent : Colors.redAccent), title: Text('${movementName('${x['kind']}')} • ${x['branchId']}'), subtitle: Text(formatDate(x['createdAt'])), trailing: Text('${q >= 0 ? '+' : ''}$q\nرصيد ${x['balanceAfter'] ?? '-'}', textAlign: TextAlign.center)); }).toList()))]);
    })),
  ]);
}
