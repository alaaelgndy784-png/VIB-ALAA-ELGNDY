# معرض إيهاب علوان — مشروع المبيعات والمخزون المستقل

هذه نقطة تطوير منفصلة مشتقة من نفس كود إدارة المبيعات والمخزون المستخدم في VIB. لم يتم تغيير الفرع الرئيسي main، ولا نقل فواتير أو أرصدة أو مخزون أو بيانات عملاء.

## ما تم إعداده

- هوية جديدة: معرض إيهاب علوان
- Android Manager application ID: com.ehabalwan.sales.manager
- Android Staff application ID: com.ehabalwan.sales.staff
- سكربت تهيئة يزيل اتصال Firebase القديم ويستخدم متغيرات تهيئة مستقلة، ويغير اسم تطبيق Flutter ويستبدل شعار VIB
- فصل كود الواجهة والتقارير والمحاسبة والمشتريات والطباعة ومخزون الموظفين، مع استنساخ قوالب قواعد Firestore وCloud Functions دون نشرها

## استخراج الشفرة المصدرية كاملة

من تبويب Actions على GitHub شغّل Package Ehab Alwan Sales Source على فرع ehab-alwan-sales (أو استخدم التشغيل التلقائي عند دفع ملفات الفرع).

حَمِّل ملف artifact المسمى EHAB-ALWAN-SALES-FULL-SOURCE.

## شرط التشغيل

لا تثبّت هذا كنسخة أعمال حقيقية بعد. يلزم إنشاء Firebase جديد منفصل كليًّا عن vib-sales، تسجيل تطبيقَي المدير والموظف، وإنشاء مستخدم مدير مستقل، وتطبيق القواعد والاختبارات قبل إخراج APK ونشره. هذا الفرع لا يشغّل أي workflow نشر Firebase ولا ينسخ بيانات العملاء.

متغيرات بناء Firebase الجديدة المطلوبة:
- EHAB_FIREBASE_API_KEY
- EHAB_FIREBASE_PROJECT_ID
- EHAB_FIREBASE_SENDER_ID
- EHAB_FIREBASE_STORAGE_BUCKET
- EHAB_FIREBASE_MANAGER_APP_ID
- EHAB_FIREBASE_STAFF_APP_ID

مفتاح توقيع Android يجب إنشاؤه وحفظه خصوصًا للمشروع الجديد؛ مفاتيح VIB لا تنقل هنا.

## اللوجو

سيتولد شعار EA مؤقت بألوان كحلي/ذهبي إذا لم تُرفع الصور المعتمدة. اللوجو والأيقونة الرسميان موجودان في حزمة التأسيس المرفقة في محادثة ChatGPT؛ ضعهما في ehab_alwan/Ehab_Alwan_Logo.png و ehab_alwan/Ehab_Alwan_App_Icon.png قبل إخراج النسخة الرسمية.

منقول هنا الشفرة البرمجية فقط، ولا ننسخ أو نعدل قاعدة بيانات VIB. أي وظيفة حسابات أو تقارير أو مزامنة تحتاج اختبارًا على قاعدة بيانات إيهاب الجديدة. هذا ليس إعلان اكتمال نسخة إنتاجية.
