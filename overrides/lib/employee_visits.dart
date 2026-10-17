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
  bool saving = false, recording = false, recordingBusy = false;
  int recordingSeconds = 0, shortageAudioSeconds = 0;
  String? shortageAudioBase64;
  DateTime? nextVisitAt;
  final TextEditingController shortageController = TextEditingController();
  AudioRecorder? recorder;
  Timer? recordingTimer;

  @override void dispose() {
    recordingTimer?.cancel();
    recorder?.dispose();
    shortageController.dispose();
    super.dispose();
  }

  Future<void> _toggleShortageRecording() async {
    if (recordingBusy || saving) return;
    setState(() => recordingBusy = true);
    try {
      if (recording) {
        recordingTimer?.cancel();
        final path = await recorder!.stop();
        final duration = recordingSeconds.clamp(1, 60).toInt();
        if (path == null) throw StateError('لم يتم تسجيل الصوت');
        final file = File(path);
        final bytes = await file.readAsBytes();
        await file.delete();
        if (bytes.isEmpty || bytes.length > 600000) throw StateError('حجم التسجيل غير مناسب؛ سجل مرة أخرى');
        if (mounted) setState(() {
          recording = false;
          shortageAudioBase64 = base64Encode(bytes);
          shortageAudioSeconds = duration;
        });
      } else {
        recorder ??= AudioRecorder();
        if (!await recorder!.hasPermission()) throw StateError('اسمح للتطبيق باستخدام الميكروفون من إعدادات الهاتف');
        final dir = await getTemporaryDirectory();
        await recorder!.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 16000, numChannels: 1),
          path: '${dir.path}/vib-visit-${DateTime.now().microsecondsSinceEpoch}.m4a',
        );
        if (!mounted) { await recorder!.cancel(); return; }
        setState(() { recording = true; recordingSeconds = 0; });
        recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => recordingSeconds++);
          if (recordingSeconds >= 60) _toggleShortageRecording();
        });
      }
    } catch (error) {
      recordingTimer?.cancel();
      await recorder?.cancel();
      if (mounted) {
        setState(() => recording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تسجيل الصوت: ${error.toString().replaceFirst('Bad state: ', '')}')),
        );
      }
    } finally {
      if (mounted) setState(() => recordingBusy = false);
    }
  }

  Future<void> _chooseNextVisit() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final chosenDate = await showDatePicker(
      context: context,
      initialDate: nextVisitAt ?? now.add(const Duration(days: 1)),
      firstDate: first,
      lastDate: DateTime(now.year + 5),
      helpText: 'اختار يوم الرجوع للعميل',
    );
    if (chosenDate == null || !mounted) return;
    final initialTime = nextVisitAt != null && nextVisitAt!.year == chosenDate.year &&
        nextVisitAt!.month == chosenDate.month && nextVisitAt!.day == chosenDate.day
        ? TimeOfDay.fromDateTime(nextVisitAt!) : const TimeOfDay(hour: 9, minute: 0);
    final chosenTime = await showTimePicker(context: context, initialTime: initialTime, helpText: 'اختار ميعاد الرجوع');
    if (chosenTime == null || !mounted) return;
    setState(() => nextVisitAt = DateTime(
      chosenDate.year, chosenDate.month, chosenDate.day, chosenTime.hour, chosenTime.minute,
    ));
  }

  Future<void> _recordVisit(String customerId, String customerName) async {
    final shortageText = shortageController.text.trim();
    final audio = shortageAudioBase64;
    final hasShortage = shortageText.isNotEmpty || audio != null;
    if (shortageText.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('طلب النواقص بحد أقصى 1000 حرف')));
      return;
    }
    if (hasShortage && nextVisitAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدد يوم وميعاد الرجوع للعميل عشان يظهر تذكير للمدير')));
      return;
    }
    if (hasShortage && nextVisitAt!.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختار ميعاد رجوع قادم')));
      return;
    }
    final consent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تسجيل الزيارة'),
        content: const Text('هيتسجل اسم العميل ووقت الزيارة وموقعك الحالي وطلب النواقص إن وجد، وهيظهروا للمدير. الموقع مش بيتسجل إلا لما توافق وتضغط تسجيل.'),
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)),
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
        'shortageText': shortageText,
        if (audio != null) 'shortageAudioBase64': audio,
        'shortageAudioSeconds': audio == null ? 0 : shortageAudioSeconds,
        if (nextVisitAt != null) 'nextVisitAt': Timestamp.fromDate(nextVisitAt!),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      shortageController.clear();
      setState(() {
        shortageAudioBase64 = null;
        shortageAudioSeconds = 0;
        nextVisitAt = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hasShortage ? 'تم تسجيل الزيارة وطلب النواقص وميعاد الرجوع؛ هيظهروا للمدير' : 'تم تسجيل الزيارة وموقعك الحالي')),
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
      final customers = customersSnapshot.data?.docs.where((row) => row.data()['active'] != false).toList()
        ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      customers.sort((a, b) => ('${a.data()['name'] ?? ''}').compareTo('${b.data()['name'] ?? ''}'));
      QueryDocumentSnapshot<Map<String, dynamic>>? selected;
      for (final row in customers) {
        if (row.id == selectedCustomerId) { selected = row; break; }
      }
      final hasShortage = shortageController.text.trim().isNotEmpty || shortageAudioBase64 != null;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('تسجيل زيارة عميل', style: TextStyle(color: gold, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('اختار العميل، سجّل موقعك الحالي، واكتب أو سجّل صوتيًا أي نواقص مطلوبة وحدد ميعاد الرجوع.'),
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
                      value: row.id, child: Text('${row.data()['name'] ?? 'عميل'}', overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: saving || recording ? null : (value) => setState(() => selectedCustomerId = value),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: shortageController,
                  enabled: !saving && !recording,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'طلب النواقص أو المطلوب للزيارة القادمة',
                    hintText: 'مثال: خلاط مطبخ موديل ... / قطعة ناقصة ...',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                Row(children: [
                  IconButton(
                    tooltip: recording ? 'إيقاف التسجيل' : 'تسجيل طلب صوتي',
                    onPressed: recordingBusy || saving || shortageAudioBase64 != null ? null : _toggleShortageRecording,
                    icon: Icon(recording ? Icons.stop_circle : Icons.mic, color: recording ? Colors.red : vibBlue, size: 30),
                  ),
                  Expanded(child: Text(recording
                    ? 'جارٍ التسجيل: $recordingSeconds / 60 ثانية'
                    : shortageAudioBase64 != null ? 'تم إرفاق تسجيل صوتي (${shortageAudioSeconds} ثانية)'
                    : 'سجّل صوت العميل أو اكتب الطلب')),
                  if (shortageAudioBase64 != null)
                    IconButton(
                      tooltip: 'حذف التسجيل',
                      onPressed: saving ? null : () => setState(() { shortageAudioBase64 = null; shortageAudioSeconds = 0; }),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ]),
                if (shortageAudioBase64 != null)
                  ChatVoicePlayer(encoded: shortageAudioBase64!, seconds: shortageAudioSeconds),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: saving || recording ? null : _chooseNextVisit,
                  icon: const Icon(Icons.event_available),
                  label: Text(nextVisitAt == null
                    ? 'تحديد ميعاد الرجوع للعميل'
                    : 'الرجوع: ${DateFormat('dd/MM/yyyy  HH:mm').format(nextVisitAt!)}'),
                ),
                if (hasShortage)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('الموعد وطلب النواقص هيظهروا في تجميعة المدير، ويتحدد الطلب المستحق يوم الرجوع.', style: TextStyle(color: vibBlue)),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: saving || recording || recordingBusy || selected == null
                    ? null : () => _recordVisit(selected!.id, '${selected!.data()['name'] ?? 'عميل'}'),
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
              return Column(children: rows.map((row) => _visitTile(context, row.id, row.data(), showEmployee: false, allowDelete: true)).toList());
            },
          ),
        ],
      );
    },
  );
}

class EmployeeVisitReport extends StatelessWidget {
  const EmployeeVisitReport({super.key});
  @override Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(children: [
        const Expanded(child: Text('زيارات الموظفين', style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 17))),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmployeeVisitShortagesPage())),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('تجميع النواقص'),
        ),
      ]),
    ),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('employeeVisits').orderBy('createdAt', descending: true).limit(500).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('تعذر تحميل زيارات الموظفين'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text('لا توجد زيارات مسجلة حتى الآن'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final row = snapshot.data!.docs[index];
            return _visitTile(context, row.id, row.data(), showEmployee: true, allowDelete: true);
          },
        );
      },
    )),
  ]);
}

class EmployeeVisitShortagesPage extends StatelessWidget {
  const EmployeeVisitShortagesPage({super.key});

  @override Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('تجميع نواقص الزيارات')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('employeeVisits').orderBy('createdAt', descending: true).limit(500).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('تعذر تحميل طلبات النواقص'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!.docs.where((row) => _visitHasShortage(row.data())).toList()
            ..sort((a, b) => _visitReturnTime(a.data()).compareTo(_visitReturnTime(b.data())));
          if (rows.isEmpty) return const Center(child: Text('لا توجد طلبات نواقص مسجلة'));
          final today = DateTime.now();
          final dueToday = rows.where((row) {
            final date = _visitReturnTime(row.data());
            return date.year == today.year && date.month == today.month && date.day == today.day;
          }).length;
          final groups = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final row in rows) {
            final key = '${row.data()['customerId'] ?? row.data()['customerName'] ?? 'عميل'}';
            groups.putIfAbsent(key, () => []).add(row);
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.notifications_active_outlined, color: vibBlue),
                  title: Text('${rows.length} طلب نواقص'),
                  subtitle: Text('منها $dueToday مطلوب الرجوع فيها النهارده'),
                ),
              ),
              ...groups.entries.map((entry) => Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.person_outline, color: gold),
                  title: Text('${entry.value.first.data()['customerName'] ?? 'عميل'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${entry.value.length} طلب للعميل'),
                  children: entry.value.map((row) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: _visitTile(context, row.id, row.data(), showEmployee: true, allowDelete: true),
                  )).toList(),
                ),
              )),
            ],
          );
        },
      ),
    ),
  );
}

DateTime _visitTimestamp(Map<String, dynamic> data) {
  final value = data['createdAt'];
  return value is Timestamp ? value.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime _visitReturnTime(Map<String, dynamic> data) {
  final value = data['nextVisitAt'];
  return value is Timestamp ? value.toDate().toLocal() : DateTime(9999);
}

bool _visitHasShortage(Map<String, dynamic> data) =>
  '${data['shortageText'] ?? ''}'.trim().isNotEmpty || data['shortageAudioBase64'] is String;

String _visitReturnLabel(Map<String, dynamic> data) {
  final date = data['nextVisitAt'];
  if (date is! Timestamp) return 'موعد الرجوع غير محدد';
  final local = date.toDate().toLocal();
  final today = DateTime.now();
  final dueToday = local.year == today.year && local.month == today.month && local.day == today.day;
  return '${dueToday ? 'مطلوب الرجوع اليوم • ' : ''}${DateFormat('dd/MM/yyyy  HH:mm').format(local)}';
}

Future<void> _deleteVisit(BuildContext context, String id) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('مسح الزيارة؟'),
      content: const Text('هيتم حذف الزيارة وطلب النواقص والتسجيل الصوتي المرتبط بها.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('مسح الزيارة')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await db.collection('employeeVisits').doc(id).delete();
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم مسح الزيارة')));
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر مسح الزيارة: ${error.toString()}')),
    );
  }
}

Widget _visitTile(BuildContext context, String id, Map<String, dynamic> data, {
  required bool showEmployee,
  required bool allowDelete,
}) {
  final latitude = (data['latitude'] as num?)?.toDouble();
  final longitude = (data['longitude'] as num?)?.toDouble();
  final accuracy = (data['accuracyMeters'] as num?)?.toDouble();
  final date = _visitTimestamp(data);
  final dateText = date.millisecondsSinceEpoch == 0 ? 'جارٍ حفظ الوقت' : DateFormat('dd/MM/yyyy  HH:mm').format(date.toLocal());
  final shortageText = '${data['shortageText'] ?? ''}'.trim();
  final audio = data['shortageAudioBase64'];
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
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
        if (_visitHasShortage(data)) ...[
          const Divider(),
          const Text('طلب النواقص للزيارة القادمة', style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
          if (shortageText.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: SelectableText(shortageText)),
          if (audio is String) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ChatVoicePlayer(encoded: audio, seconds: (data['shortageAudioSeconds'] as num?)?.toInt() ?? 0),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_visitReturnLabel(data), style: const TextStyle(color: vibBlue, fontWeight: FontWeight.bold)),
          ),
        ],
        if (allowDelete)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => _deleteVisit(context, id),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              label: const Text('مسح الزيارة', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
      ]),
    ),
  );
}
