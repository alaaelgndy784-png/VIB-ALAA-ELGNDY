package com.example.data

import com.example.R
import com.example.model.Product
import com.example.model.SanitaryCategory

object InitialProducts {
  val defaultCatalog = listOf(
    // النحاسات (Brass Fittings)
    Product(
      id = "brass_01",
      name = "محبس زاوية نحاس أصلي ثقيل 1/2 بوصة VIB",
      price = 145.0,
      category = SanitaryCategory.BRASS,
      description = "محبس زاوية نحاس أصفر عالي الجودة بنواة سيراميك ألمانية، يتحمل الضغط العالي ومقاوم للأملاح والصدأ مع ضمان 5 سنوات.",
      drawableRes = R.drawable.brass_fitting,
      inStock = true
    ),
    Product(
      id = "brass_02",
      name = "نبل نحاس مضلع سن خارجي ثقيل 1/2 × 1/2",
      price = 45.0,
      category = SanitaryCategory.BRASS,
      description = "نبل توصيل نحاس إيطالي أصلي مصبوب بجودة متناهية، مناسب لكافة توصيلات التغذية والسباكة الحديثة.",
      drawableRes = R.drawable.brass_fitting,
      inStock = true
    ),
    Product(
      id = "brass_03",
      name = "صمام عدم رجوع نحاسي (شيك بلف) 1 بوصة",
      price = 220.0,
      category = SanitaryCategory.BRASS,
      description = "شيك بلف نحاس كامل مع ياي استانلس ستيل لمنع ارتداد المياه للمضخات والخزانات بكفاءة قصوى.",
      drawableRes = R.drawable.brass_fitting,
      inStock = true
    ),
    Product(
      id = "brass_04",
      name = "كوع نحاس سن داخلي/خارجي 1/2 بوصة",
      price = 65.0,
      category = SanitaryCategory.BRASS,
      description = "كوع توصيل نحاس نقي سميك ومطلي بطبقة حماية ضد التآكل والترسبات الكلسية.",
      drawableRes = R.drawable.brass_fitting,
      inStock = true
    ),

    // الحنفيات (Faucets & Mixers)
    Product(
      id = "faucet_01",
      name = "خلاط حوض شلال ذهبي فاخر VIB Royal Gold",
      price = 1650.0,
      category = SanitaryCategory.FAUCETS,
      description = "خلاط مغسلة شلال بتصميم ملكي انسيابي باللون الذهبي البراق، قلب سيراميك هيدروليكي فائق النعومة وموفر لاستهلاك المياه.",
      drawableRes = R.drawable.faucet_gold,
      inStock = true
    ),
    Product(
      id = "faucet_02",
      name = "خلاط مطبخ شداد متحرك دوران 360 درجة ذهبي",
      price = 1850.0,
      category = SanitaryCategory.FAUCETS,
      description = "خلاط مجلى مطبخ مع خرطوم مرن قابل للسحب ورشاش مياه بنظامين (دفع مركز ورذاذ دش)، لمسة عصرية تدوم طويلاً.",
      drawableRes = R.drawable.faucet_gold,
      inStock = true
    ),
    Product(
      id = "faucet_03",
      name = "خلاط بانيو ودش دفن نحاسي ذهبي مع طاسة سقفية",
      price = 2950.0,
      category = SanitaryCategory.FAUCETS,
      description = "نظام دش دفن كامل يشمل وجه الخلاط النحاسي الذهبي، طاسة دش مطري مقاس 30 سم، وسماعة يد مع خرطوم مقاوم للالتواء.",
      drawableRes = R.drawable.faucet_gold,
      inStock = true
    ),
    Product(
      id = "faucet_04",
      name = "حنفية مفرد فاخرة نحاس جولد للمغاسل المعلقة",
      price = 580.0,
      category = SanitaryCategory.FAUCETS,
      description = "صنبور مياه مفرد مدمج مع فلتر ترشيح وتنقية وتوزيع منتظم لرذاذ المياه.",
      drawableRes = R.drawable.faucet_gold,
      inStock = true
    ),

    // الإكسسوارات (Accessories)
    Product(
      id = "acc_01",
      name = "طقم إكسسوار حمام ذهبي ملكي 6 قطع VIB",
      price = 1250.0,
      category = SanitaryCategory.ACCESSORIES,
      description = "طقم حمام متكامل يشمل: رف فوط مزدوج، حامل مناديل بغطاء، حامل صابون كريستال، علاقة ملابس، كوب فرش ومعجون، وحامل إسفنج.",
      drawableRes = R.drawable.accessories_set,
      inStock = true
    ),
    Product(
      id = "acc_02",
      name = "صفاية أرضية استانلس ستيل ذهبي مانعة للحشرات 15×15",
      price = 380.0,
      category = SanitaryCategory.ACCESSORIES,
      description = "بيبة أرضية شاور سميكة بقلب نحاسي يفتح تلقائياً مع تدفق المياه ويغلق بإحكام لمنع الروائح والحشرات.",
      drawableRes = R.drawable.accessories_set,
      inStock = true
    ),
    Product(
      id = "acc_03",
      name = "شطاف حمام نحاس ذهبي مع هوز مرن وحامل جداري",
      price = 420.0,
      category = SanitaryCategory.ACCESSORIES,
      description = "شطاف يدوي برأس نحاسي ضغط عالي، خرطوم معدني مدعم 1.2 متر ضد الانفجار والصدأ.",
      drawableRes = R.drawable.accessories_set,
      inStock = true
    ),
    Product(
      id = "acc_04",
      name = "حامل مناشف فندقي طبقتين استانلس مذهب عريض",
      price = 690.0,
      category = SanitaryCategory.ACCESSORIES,
      description = "رف مناشف فندقي فاخر قابل للطي مع مساكات سفلية متعددة وسعة حمل عالية.",
      drawableRes = R.drawable.accessories_set,
      inStock = true
    ),

    // الألوان (Colors & Designer Finishes)
    Product(
      id = "color_01",
      name = "طقم خلاطات حمام أسود مط مطفي Matte Black (3 قطع)",
      price = 3400.0,
      category = SanitaryCategory.COLORS,
      description = "طقم خلاطات أسود كربوني فحم مطفي يشمل: خلاط مغسلة عالي، خلاط بانيو، ومسطرة دش كاملة بطلاء كهروسكوني مضاد للبصمات والخدوش.",
      drawableRes = R.drawable.colors_sanitary,
      inStock = true
    ),
    Product(
      id = "color_02",
      name = "خلاط حوض روز جولد ملكي Rose Gold Brushed",
      price = 1950.0,
      category = SanitaryCategory.COLORS,
      description = "تصميم حصري بلون الذهب الوردي المصقول بنعومة مخملية، يتناسب مع أرقى الديكورات المودرن والرخام الطبيعي.",
      drawableRes = R.drawable.colors_sanitary,
      inStock = true
    ),
    Product(
      id = "color_03",
      name = "خلاط مغسلة رمادي داكن فانتوم Gunmetal Gray",
      price = 1750.0,
      category = SanitaryCategory.COLORS,
      description = "لون الجرافيت الرمادي التيتانيوم العصري، خامة نحاس ثقيلة وطلاء PVD فائق الصلابة ومقاوم للتكلس.",
      drawableRes = R.drawable.colors_sanitary,
      inStock = true
    ),
    Product(
      id = "color_04",
      name = "مسطرة دش ألوان فاخرة ذهبي مطفي Brushed Gold",
      price = 2800.0,
      category = SanitaryCategory.COLORS,
      description = "مسطرة شاور كاملة بطلاء الذهب المطفى الكلاسيكي، مزودة بسماعة دش عريضة ثلاثية الوظائف ورشاش مساج.",
      drawableRes = R.drawable.colors_sanitary,
      inStock = true
    )
  )
}
