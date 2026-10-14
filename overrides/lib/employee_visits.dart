part of 'main.dart';

class EmployeeVisitsPage extends StatefulWidget {
  final String uid;
  final String employeeName;
  final String branchId;
  const EmployeeVisitsPage({super.key, required this.uid, required this.employeeName, required this.branchId});
  @override State<EmployeeVisitsPage> createState() => _EmployeeVisitsPageState();
}

class _EmployeeVisitsPageState extends State<EmployeeVisitsPage> {
  String? selectedCustomerId;
  bool saving = false;

  Future<void> _recordVisit(String customerId, String customerName) async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تسجيل الزيارة'),
        content: const Text('هيتسجل اسم العميل ووقت الزيارة وموقعك الحالي، وهيظهروا للمدير. الموقع مش بيتسجل إلا لما توافق وتضغط تسجيل.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('موافق وتسجيل')),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    setState(() => saving = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('فعّل خدمة الموقع على الموبايل ثم حاول مرة تانية.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError('لازم تسمح للتطبيق باستخدام الموقع أثناء الاستخدام لتسجيل الزيارة.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      await db.collection('employeeVisits').add({
        'employeeId': widget.uid,
        'employeeName': widget.employeeName,
        'branchId': widget.branchId,
        'customerId': customerId,
        'customerName': customerName,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracyMeters': position.accuracy,
        'consented': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الزيارة وموقعك الحالي')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db.collection('customers').snapshots(),
    builder: (context, customersSnapshot) {
      final customers = customersSnapshot.data?.docs
        .where((row) => row.data()['active'] != false)
        .toList() ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      customers.sort((a, b) => ('${a.data()['name'] ?? ''}').compareTo('${b.data()['name'] ?? ''}'));
      QueryDocumentSnapshot<Map<String, dynamic>>? selected;
      for (final row in customers) {
        if (row.id == selectedCustomerId) { selected = row; break; }
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('تسجيل زيارة عميل', style: TextStyle(color: gold, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('اختار العميل، وبعدها سجّل موقعك الحالي. الموقع لا يعمل في الخلفية ولا يتحدث تلقائيًا.'),
                const SizedBox(height: 14),
                if (customersSnapshot.hasError)
                  const Text('تعذر تحميل العملاء', style: TextStyle(color: Colors.redAccent))
                else if (!customersSnapshot.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (customers.isEmpty)
                  const Text('لا يوجد عملاء نشطون لتسجيل زيارة لهم.')
                else
                  DropdownButtonFormField<String>(
                    value: selected?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'العميل'),
                    hint: const Text('اختار العميل'),
                    items: customers.map((row) => DropdownMenuItem<String>(
                      value: row.id,
                      child: Text('${row.data()['name'] ?? 'عميل'}', overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: saving ? null : (value) => setState(() => selectedCustomerId = value),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: saving || selected == null ? null : () => _recordVisit(selected!.id, '${selected!.data()['name'] ?? 'عميل'}'),
                  icon: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location),
                  label: Text(saving ? 'جاري تحديد الموقع...' : 'تسجيل الزيارة وموقعي الحالي'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          const Text('زياراتي السابقة', style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('employeeVisits').where('employeeId', isEqualTo: widget.uid).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Padding(padding: EdgeInsets.all(16), child: Text('تعذر تحميل الزيارات'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snapshot.data!.docs.toList()
                ..sort((a, b) => _visitTimestamp(b.data()).compareTo(_visitTimestamp(a.data())));
              if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('لسه مفيش زيارات مسجلة.'));
              return Column(children: rows.map((row) => _visitTile(context, row.data(), showEmployee: false)).toList());
            },
          ),
        ],
      );
    },
  );
}

class EmployeeVisitReport extends StatelessWidget {
  const EmployeeVisitReport({super.key});
  @override Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db.collection('employeeVisits').orderBy('createdAt', descending: true).limit(500).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('تعذر تحميل زيارات الموظفين'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      if (snapshot.data!.docs.isEmpty) return const Center(child: Text('لا توجد زيارات مسجلة حتى الآن'));
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: snapshot.data!.docs.length,
        itemBuilder: (context, index) => _visitTile(context, snapshot.data!.docs[index].data(), showEmployee: true),
      );
    },
  );
}

DateTime _visitTimestamp(Map<String, dynamic> data) {
  final value = data['createdAt'];
  return value is Timestamp ? value.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
}

Widget _visitTile(BuildContext context, Map<String, dynamic> data, {required bool showEmployee}) {
  final latitude = (data['latitude'] as num?)?.toDouble();
  final longitude = (data['longitude'] as num?)?.toDouble();
  final accuracy = (data['accuracyMeters'] as num?)?.toDouble();
  final date = _visitTimestamp(data);
  final dateText = date.millisecondsSinceEpoch == 0 ? 'جارٍ حفظ الوقت' : DateFormat('dd/MM/yyyy  HH:mm').format(date.toLocal());
  return Card(
    child: ListTile(
      leading: const Icon(Icons.location_on, color: vibBlue),
      title: Text('${data['customerName'] ?? 'عميل'}', style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text([
        if (showEmployee) 'الموظف: ${data['employeeName'] ?? ''}',
        'الوقت: $dateText',
        if (accuracy != null) 'دقة الموقع التقريبية: ${accuracy.round()} متر',
      ].join('\n')),
      isThreeLine: showEmployee,
      trailing: latitude == null || longitude == null ? null : IconButton(
        tooltip: 'فتح الموقع على الخريطة',
        icon: const Icon(Icons.map_outlined, color: gold),
        onPressed: () async {
          final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الخريطة')));
          }
        },
      ),
    ),
  );
}
