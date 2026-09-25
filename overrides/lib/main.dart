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
          return ListTile(title: Text('${p['name'] ?? ''}'), subtitle: Text('السعر: ${p['price'] ?? 0} ج.م'), trailing: owner
            ? Wrap(children: [IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit), onPressed: () => productDialog(context, id: d.id, data: p)), IconButton(tooltip: 'المخزون الرئيسي', icon: const Icon(Icons.warehouse), onPressed: () => mainStockDialog(context, d.id, '${p['name']}'))])
            : IconButton(icon: const Icon(Icons.add_shopping_cart), onPressed: () => saleDialog(context, d.id, p, uid, branchId)));
        })),
      ]);
    },
  );
}

Future<void> productDialog(BuildContext context, {String? id, Map<String, dynamic>? data}) async {
  final name = TextEditingController(text: '${data?['name'] ?? ''}');
  final price = TextEditingController(text: '${data?['price'] ?? ''}');
  await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(title: Text(id == null ? 'منتج جديد' : 'تعديل المنتج'), content: Column(mainAxisSize: MainAxisSize.min, children: [
    TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المنتج')),
    TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر')),
  ]), actions: [
    TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
    FilledButton(onPressed: () async {
      final amount = double.tryParse(price.text);
      if (name.text.trim().isEmpty || amount == null || amount < 0) return;
      final ref = id == null ? db.collection('products').doc() : db.collection('products').doc(id);
      try { await ref.set({'name': name.text.trim(), 'price': amount, 'active': true, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        if (dialogContext.mounted) Navigator.pop(dialogContext);
      } catch (_) { if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('فشل حفظ المنتج'))); }
    }, child: const Text('حفظ')),
  ]));
}

Future<void> saleDialog(BuildContext context, String productId, Map<String, dynamic> product, String uid, String branchId) async {
  final quantity = TextEditingController(text: '1');
  final customerPhone = TextEditingController();
  await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(title: Text('بيع ${product['name']}'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية')), TextField(controller: customerPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم هاتف الزبون (اختياري للواتساب)'))]),
    actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')), FilledButton(onPressed: () async {
      final qty = int.tryParse(quantity.text);
      if (qty == null || qty <= 0) return;
      try {
        await db.runTransaction((tx) async {
          final stockRef = db.collection('stock').doc('${branchId}_$productId');
          final stock = await tx.get(stockRef);
          final current = (stock.data()?['quantity'] as num?)?.toInt() ?? 0;
          if (current < qty) throw Exception('الكمية غير متاحة في الفرع');
          final sale = db.collection('sales').doc();
          tx.update(stockRef, {'quantity': current - qty, 'lastSaleId': sale.id});
          tx.set(sale, {'branchId': branchId, 'employeeId': uid, 'customerPhone': customerPhone.text.trim(), 'productId': productId, 'productName': product['name'], 'quantity': qty, 'unitPrice': product['price'], 'total': qty * (product['price'] as num), 'status': 'completed', 'createdAt': FieldValue.serverTimestamp()});
          tx.set(db.collection('stockMovements').doc(), {'productId': productId, 'productName': product['name'], 'branchId': branchId, 'kind': 'sale', 'quantity': -qty, 'balanceAfter': current - qty, 'referenceId': sale.id, 'actorId': uid, 'createdAt': FieldValue.serverTimestamp()});
        });
        if (dialogContext.mounted) Navigator.pop(dialogContext);
      } catch (e) { if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('تعذر البيع: $e'))); }
    }, child: const Text('تأكيد البيع'))]));
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
    if (rows.isEmpty) return const Center(child: Text('لا توجد مبيعات بعد'));
    return ListView(children: rows.map((d) { final s = d.data(); return ListTile(
      title: Text('${s['productName']} × ${s['quantity']}'),
      subtitle: Text('فرع: ${s['branchId']} • ${formatDate(s['createdAt'])}${s['status'] == 'returned' ? ' • مرتجع' : ''}'),
      trailing: Text('${s['total']} ج.م'),
      onTap: () => invoiceActions(context, 'sales', d.id, s, canReturn: owner),
    ); }).toList());
  });
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
    Card(child: ListTile(leading: const Icon(Icons.store, color: gold), title: const Text('الفروع والمخزون'), subtitle: const Text('إضافة الفروع ونقل البضاعة إليها'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('الفروع')), body: const Branches()))))),
    Card(child: ListTile(leading: const Icon(Icons.people, color: gold), title: const Text('الموظفون والصلاحيات'), subtitle: const Text('تفعيل الموظف وتحديد فرعه'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('الموظفون')), body: const Staff()))))),
    Card(child: ListTile(leading: const Icon(Icons.history, color: gold), title: const Text('سجل حركات الحسابات'), subtitle: const Text('التحصيلات والمدفوعات محفوظة بالتاريخ'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('حركات الحسابات')), body: const AccountMovements()))))),
    Card(child: ListTile(leading: const Icon(Icons.swap_vert, color: gold), title: const Text('تقرير حركة صنف'), subtitle: const Text('مبيعات ومشتريات ومرتجعات ورصيد كل حركة'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('تقرير حركة صنف')), body: const ItemMovementReport()))))),
    Card(child: ListTile(leading: const Icon(Icons.settings, color: gold), title: const Text('الإعدادات والطباعة'), subtitle: const Text('بيانات الشركة وتجهيز الفواتير للطباعة'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('الإعدادات')), body: const AppSettings()))))),
  ]);
}

class Purchases extends StatelessWidget {
  const Purchases({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: () => purchaseDialog(context), icon: const Icon(Icons.add), label: const Text('فاتورة مشتريات جديدة'))),
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
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(onPressed: () async {
          if (name.text.trim().isEmpty) return;
          try {
            await db.collection('users').doc(uid).update({
              'name': name.text.trim(), 'role': 'employee', 'branchId': selected, 'active': enabled,
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
            final balance = (snapshot.data()?['balance'] as num?)?.toDouble();
            if (balance == null || paid > balance) throw Exception('المبلغ أكبر من الرصيد الحالي');
            tx.update(ref, {'balance': balance - paid, 'updatedAt': FieldValue.serverTimestamp()});
            tx.set(db.collection('accountMovements').doc(), {
              'accountType': collection, 'accountId': id, 'accountName': snapshot.data()?['name'],
              'kind': isSupplier ? 'payment' : 'collection', 'amount': paid,
              'balanceBefore': balance, 'balanceAfter': balance - paid,
              'createdAt': FieldValue.serverTimestamp(),
              'actorId': FirebaseAuth.instance.currentUser!.uid,
            });
          });
          if (dialogContext.mounted) Navigator.pop(dialogContext);
        } catch (e) {
          if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('تعذر تسجيل الحركة: $e')));
        }
      }, child: Text(isSupplier ? 'تسجيل السداد' : 'تسجيل التحصيل'))],
  ));
}

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});
  @override State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  final company = TextEditingController(text: 'VIB للتجارة والتوزيع');
  final phone = TextEditingController(), whatsapp = TextEditingController(), address = TextEditingController(), tax = TextEditingController();
  bool loading = true, saving = false;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    final d = (await db.collection('settings').doc('main').get()).data();
    if (d != null) {
      company.text = '${d['companyName'] ?? company.text}'; phone.text = '${d['phone'] ?? ''}';
      whatsapp.text = '${d['whatsapp'] ?? ''}'; address.text = '${d['address'] ?? ''}'; tax.text = '${d['taxNumber'] ?? ''}';
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> save() async {
    if (company.text.trim().isEmpty) return;
    setState(() => saving = true);
    try {
      await db.collection('settings').doc('main').set({'companyName': company.text.trim(), 'phone': phone.text.trim(), 'whatsapp': whatsapp.text.trim(), 'address': address.text.trim(), 'taxNumber': tax.text.trim(), 'updatedAt': FieldValue.serverTimestamp(), 'updatedBy': FirebaseAuth.instance.currentUser!.uid}, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'))); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override Widget build(BuildContext context) => loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
    TextField(controller: company, decoration: const InputDecoration(labelText: 'اسم الشركة على الفاتورة')),
    TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
    TextField(controller: whatsapp, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم واتساب')),
    TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
    TextField(controller: tax, decoration: const InputDecoration(labelText: 'الرقم الضريبي (اختياري)')),
    const SizedBox(height: 20), FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.save), label: const Text('حفظ الإعدادات')),
    const SizedBox(height: 14), const Card(child: ListTile(leading: Icon(Icons.cloud_done, color: gold), title: Text('حفظ البيانات طويل المدة'), subtitle: Text('الفواتير والحركات لا تُحذف وتظل محفوظة في قاعدة البيانات.'))),
  ]);
}

Future<void> invoiceActions(BuildContext context, String type, String id, Map<String, dynamic> data, {bool canReturn = true}) async {
  final returned = data['status'] == 'returned';
  await showModalBottomSheet<void>(context: context, builder: (c) => SafeArea(child: Wrap(children: [
    ListTile(leading: const Icon(Icons.print, color: gold), title: Text(data['printedAt'] == null ? 'طباعة الفاتورة' : 'إعادة طباعة الفاتورة'), onTap: () { Navigator.pop(c); printInvoice(context, type, id, data); }),
    if (type == 'sales' && '${data['customerPhone'] ?? ''}'.trim().isNotEmpty) ListTile(leading: const Icon(Icons.chat, color: Colors.greenAccent), title: const Text('إرسال للزبون على واتساب'), onTap: () { Navigator.pop(c); sendInvoiceWhatsApp(context, id, data); }),
    if (canReturn) ListTile(leading: Icon(Icons.undo, color: returned ? Colors.grey : Colors.redAccent), title: Text(returned ? 'تم إرجاع الفاتورة' : type == 'sales' ? 'إرجاع فاتورة المبيعات' : 'إرجاع فاتورة المشتريات'), enabled: !returned, onTap: returned ? null : () { Navigator.pop(c); confirmReturn(context, type, id, data); }),
  ])));
}

Future<void> sendInvoiceWhatsApp(BuildContext context, String id, Map<String, dynamic> data) async {
  var phone = '${data['customerPhone'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
  if (phone.startsWith('0')) phone = '20${phone.substring(1)}';
  if (phone.startsWith('00')) phone = phone.substring(2);
  final message = 'فاتورة مبيعات VIB رقم $id\nالصنف: ${data['productName']}\nالكمية: ${data['quantity']}\nالإجمالي: ${data['total']} ج.م\nشكراً لتعاملكم معنا';
  final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح واتساب')));
}

Future<void> printInvoice(BuildContext context, String type, String id, Map<String, dynamic> data) async {
  try {
    final settings = (await db.collection('settings').doc('main').get()).data() ?? <String, dynamic>{};
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final pdf = pw.Document();
    final isSale = type == 'sales';
    final unit = data[isSale ? 'unitPrice' : 'unitCost'] ?? 0;
    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, theme: pw.ThemeData.withFont(base: font, bold: font), build: (_) => pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Padding(padding: const pw.EdgeInsets.all(28), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Center(child: pw.Text('${settings['companyName'] ?? 'VIB للتجارة والتوزيع'}', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 6), pw.Center(child: pw.Text('${settings['address'] ?? ''}  ${settings['phone'] ?? ''}')),
      if ('${settings['taxNumber'] ?? ''}'.isNotEmpty) pw.Center(child: pw.Text('الرقم الضريبي: ${settings['taxNumber']}')),
      pw.Divider(), pw.Text(isSale ? 'فاتورة مبيعات' : 'فاتورة مشتريات', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.Text('رقم الفاتورة: ${data['invoiceNumber']?.toString().isNotEmpty == true ? data['invoiceNumber'] : id}'), pw.Text('التاريخ: ${formatDate(data['createdAt'])}'),
      if (!isSale) pw.Text('المورد: ${data['supplierName'] ?? ''}'), pw.SizedBox(height: 18),
      pw.Table(border: pw.TableBorder.all(), children: [
        pw.TableRow(children: ['الإجمالي', 'سعر الوحدة', 'الكمية', 'الصنف'].map((v) => pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(v, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)))).toList()),
        pw.TableRow(children: ['${data['total'] ?? 0}', '$unit', '${data['quantity'] ?? 0}', '${data['productName'] ?? ''}'].map((v) => pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(v, textAlign: pw.TextAlign.center))).toList()),
      ]), pw.SizedBox(height: 16), pw.Text('الإجمالي: ${data['total'] ?? 0} ج.م', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      if (!isSale) pw.Text('المدفوع: ${data['paid'] ?? 0} ج.م     المتبقي: ${data['due'] ?? 0} ج.م'),
      if (data['status'] == 'returned') pw.Text('فاتورة مرتجعة', style: const pw.TextStyle(color: PdfColors.red, fontSize: 18)),
    ])))));
    await Printing.layoutPdf(name: '${isSale ? 'VIB-SALE' : 'VIB-PURCHASE'}-$id.pdf', onLayout: (_) => pdf.save());
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
