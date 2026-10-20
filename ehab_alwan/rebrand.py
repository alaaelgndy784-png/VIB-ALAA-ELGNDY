#!/usr/bin/env python3
"""Create an isolated Flutter code copy for معرض إيهاب علوان.

Work ONLY on a freshly extracted copy, never the VIB working tree.
Removes Firebase configuration tied to VIB and sets distinct package names.
"""
from __future__ import annotations
from pathlib import Path
import argparse
import re
import shutil

BRAND = "معرض إيهاب علوان"
NEW_PKG = "ehab_alwan_sales"
OLD_BACKEND_MARKERS = (
    "vib-sales.firebasestorage.app", "200962643703",
    "AIzaSyBDjNjPOhmTt0SbYUfCTQM8IteDCBxGfWk",
    "com.alaa.vibsales.managerscan", "com.alaa.vibsales.staffscan",
)
FIREBASE_VARS = {
    "_vibApiKey": "EHAB_FIREBASE_API_KEY",
    "_vibProjectId": "EHAB_FIREBASE_PROJECT_ID",
    "_vibSenderId": "EHAB_FIREBASE_SENDER_ID",
    "_vibStorageBucket": "EHAB_FIREBASE_STORAGE_BUCKET",
    "_managerFirebaseAppId": "EHAB_FIREBASE_MANAGER_APP_ID",
    "_staffFirebaseAppId": "EHAB_FIREBASE_STAFF_APP_ID",
}

def rebrand(root: Path):
    if not (root/"lib"/"main.dart").is_file():
        raise SystemExit("Invalid Flutter source folder")
    for path in root.rglob("*.dart"):
        s = path.read_text(encoding="utf-8")
        for a, b in [
            ("VIB ALAA ELGNDY", BRAND),
            ("VIB Manager", BRAND),
            ("VIB Staff", BRAND+" - موظف"),
            ("ALAA ELGNDY", "EHAB ALWAN"),
            ("ALAAELGNDY", "EHAB ALWAN"),
            ("علاء الجندي", "إيهاب علوان"),
            ("com.alaa.vibsales.managerscan", "com.ehabalwan.sales.manager"),
            ("com.alaa.vibsales.staffscan", "com.ehabalwan.sales.staff"),
            ("package:vib_sales/", "package:ehab_alwan_sales/"),
            ("'vib_", "'ehab_alwan_"),
            ('"vib_', '"ehab_alwan_"),
        ]:
            s = s.replace(a,b)
        s = re.sub(r"(?<![\w])VIB(?![\w])", BRAND, s)
        for symbol, var in FIREBASE_VARS.items():
            s, n = re.subn(r"(const\s+"+re.escape(symbol)+r"\s*=\s*)'[^']*'\s*;",
                           r"\g<1>const String.fromEnvironment('"+var+r"');", s)
            if path.name == "main.dart" and n != 1:
                raise ValueError("Firebase option not safely patched: "+symbol)
        for x in OLD_BACKEND_MARKERS:
            if x in s:
                raise RuntimeError("Unsafe old Firebase configuration in "+str(path))
        path.write_text(s, encoding="utf-8")
    pubspec=root/"pubspec.yaml"
    s=pubspec.read_text(encoding="utf-8")
    s,n=re.subn(r"(?m)^name:\s*[\w-]+\s*$","name: ehab_alwan_sales",s,count=1)
    if n != 1: raise RuntimeError("pubspec name not updated")
    pubspec.write_text(s,encoding="utf-8")
    for f in root.rglob("google-services.json"):
        f.unlink()  # Never publish a Google-services file from VIB.
    assets=root/"assets"
    assets.mkdir(parents=True, exist_ok=True)
    logo=Path(__file__).with_name("Ehab_Alwan_Logo.png")
    icon=Path(__file__).with_name("Ehab_Alwan_App_Icon.png")
    if logo.exists():
        shutil.copyfile(logo,assets/"vip-logo.png")
    else:
        # Brand-safe fallback image. Replace with the approved logo before release.
        from PIL import Image,ImageDraw,ImageFont
        im=Image.new("RGB",(1024,1024),"#071c32")
        d=ImageDraw.Draw(im)
        d.rounded_rectangle((55,55,969,969),radius=125,outline="#d7a83f",width=24)
        font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",275)
        small=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",61)
        d.text((512,415),"EA",font=font,anchor="mm",fill="#d7a83f")
        d.text((512,700),"EHAB ALWAN",font=small,anchor="mm",fill="#fff7e6")
        im.save(assets/"vip-logo.png")
    if not icon.exists(): icon=assets/"vip-logo.png"
    for app in ("manager","staff"):
        for density in ("mdpi","hdpi","xhdpi","xxhdpi","xxxhdpi"):
            dest=assets/"icons"/app/("mipmap-"+density)
            dest.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(icon,dest/"ic_launcher.png")
    (root/"EHAB_PACKAGE_IDS.txt").write_text(
        "manager=com.ehabalwan.sales.manager\n"
        "staff=com.ehabalwan.sales.staff\n",encoding="utf-8")
    (root/"EHAB_FIREBASE_SETUP.txt").write_text(
        "معرض إيهاب علوان: يجب إنشاء Firebase مستقل عن VIB وتسجيل تطبيق مدير وموظف.\n"
        "هذه نسخة شفرة مصدرية وليست APK مهيأة للعمل.\n"
        "لا تنشر البيانات أو الحسابات أو مفتاح توقيع VIB ضمن المشروع الجديد.\n",
        encoding="utf-8")
    for p in root.rglob("*"):
        if p.is_file() and p.suffix in (".dart",".json",".yml",".yaml",".js"):
            try: s=p.read_text(encoding="utf-8")
            except UnicodeError: continue
            if any(marker in s for marker in OLD_BACKEND_MARKERS):
                raise RuntimeError("Old VIB connection found: "+str(p))
    print("Prepared branded source for Ehab Alwan, isolated from VIB cloud.")

if __name__=="__main__":
    a=argparse.ArgumentParser()
    a.add_argument("root",type=Path)
    args=a.parse_args()
    rebrand(args.root)
