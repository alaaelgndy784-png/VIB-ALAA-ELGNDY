package com.ayaqurania.calls;

import android.app.*;
import android.os.*;
import android.content.*;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.security.SecureRandom;

public class MainActivity extends Activity {
    private final int GREEN=Color.rgb(9,66,53), GOLD=Color.rgb(205,166,83), TEXT=Color.rgb(30,53,45), BG=Color.rgb(245,248,245);
    private SharedPreferences prefs;
    private JSONArray people,groups,callerCandidates;
    private LinearLayout content;
    private final SecureRandom rng=new SecureRandom();

    @Override public void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().setStatusBarColor(GREEN);
        getWindow().setNavigationBarColor(BG);
        prefs=getSharedPreferences("aya_qurania_local",MODE_PRIVATE);
        people=readArray("people"); groups=readArray("groups"); callerCandidates=readArray("caller_candidates"); render();
    }
    private JSONArray readArray(String key) {try{return new JSONArray(prefs.getString(key,"[]"));}catch(Exception e){return new JSONArray();}}
    private void save(){prefs.edit().putString("people",people.toString()).putString("groups",groups.toString()).putString("caller_candidates",callerCandidates.toString()).apply();}
    private int dp(float n){return Math.round(n*getResources().getDisplayMetrics().density);}
    private GradientDrawable bg(int color,int radius) {GradientDrawable g=new GradientDrawable(); g.setColor(color);g.setCornerRadius(dp(radius));return g;}
    private TextView txt(String value,int size,int color,boolean bold) {
        TextView v=new TextView(this);v.setText(value);v.setTextSize(size);v.setTextColor(color);
        v.setGravity(Gravity.RIGHT|Gravity.CENTER_VERTICAL);if(bold)v.setTypeface(null,1);return v;
    }
    private Button button(String value,int color,int textColor) {
        Button b=new Button(this);b.setText(value);b.setAllCaps(false);b.setTextSize(14);b.setTextColor(textColor);
        b.setBackground(bg(color,13)); b.setPadding(dp(8),0,dp(8),0); b.setMinimumHeight(dp(48));return b;
    }
    private void pad(View v,int p){v.setPadding(dp(p),dp(p),dp(p),dp(p));}
    private LinearLayout linear(int orientation){LinearLayout l=new LinearLayout(this);l.setOrientation(orientation);l.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);return l;}
    private LinearLayout.LayoutParams lp(){return new LinearLayout.LayoutParams(-1,-2);}
    private void space(LinearLayout box,int n){View v=new View(this);box.addView(v,new LinearLayout.LayoutParams(1,dp(n)));}
    private void addBtn(LinearLayout row,String name,int color,int textColor,Runnable action) {
        Button b=button(name,color,textColor);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,dp(51),1);
        p.setMargins(dp(3),dp(3),dp(3),dp(3));row.addView(b,p);b.setOnClickListener(v->action.run());
    }
    private String room(){
        byte[] b=new byte[18];rng.nextBytes(b);StringBuilder s=new StringBuilder("AyaQurania");
        for(byte x:b)s.append(String.format(java.util.Locale.US,"%02x",x&255));
        return s.toString();
    }
    private String url(String id,boolean audio){return "https://meet.jit.si/"+id+(audio?"#config.startWithVideoMuted=true":"");}
    private void share(String url){
        Intent intent=new Intent(Intent.ACTION_SEND);intent.setType("text/plain");
        intent.putExtra(Intent.EXTRA_TEXT,"دعوة لمكالمة من تطبيق آية قرآنية:\n"+url);
        startActivity(Intent.createChooser(intent,"إرسال رابط المكالمة"));
    }
    private void open(String url){
        try{Intent i=new Intent(Intent.ACTION_VIEW,Uri.parse(url));startActivity(i);}
        catch(Exception e){Toast.makeText(this,"مش لاقي متصفح يفتح المكالمة",Toast.LENGTH_LONG).show();}
    }
    private void copy(String url){
        android.content.ClipboardManager cm=(android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE);
        cm.setPrimaryClip(ClipData.newPlainText("دعوة آية قرآنية",url));
        Toast.makeText(this,"تم نسخ الرابط",Toast.LENGTH_SHORT).show();
    }
    private void call(String heading,String id,boolean audio){
        String link=url(id,audio);
        new AlertDialog.Builder(this).setTitle(heading).setMessage(
            "المكالمة بتفتح عن طريق الإنترنت في Jitsi.\n\n"+
            "اضغط «ابدأ» وبعد كده ابعت رابط الدعوة للشخص اللي هتكلمه.\n\n"+link)
            .setPositiveButton("ابدأ المكالمة",(d,w)->open(link))
            .setNeutralButton("إرسال الدعوة",(d,w)->share(link))
            .setNegativeButton("نسخ الرابط",(d,w)->copy(link)).show();
    }
    private void chooseCall(String target,String id){
        String r=(id==null)?room():id;
        new AlertDialog.Builder(this).setTitle("اتصال: "+target)
            .setItems(new String[]{"☎ مكالمة صوت","▣ مكالمة فيديو"},
                (d,which)->call("مكالمة مع "+target,r,which==0)).show();
    }
    private void render(){
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);scroll.setBackgroundColor(BG);
        LinearLayout page=linear(1);page.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        scroll.addView(page);setContentView(scroll);
        LinearLayout head=linear(1);head.setBackgroundColor(GREEN);pad(head,22);
        TextView title=txt("۞  آية قرآنية",28,Color.WHITE,true);head.addView(title,lp());
        TextView subt=txt("تواصل مع أحبابك بالصوت والصورة",14,0xffeed9a6,false);head.addView(subt,lp());
        space(head,22);
        TextView name=txt("الاسم: "+prefs.getString("name","ضيف"),14,Color.WHITE,false);
        head.addView(name,lp());space(head,10);
        Button edit=button("تعديل اسمي",GOLD,GREEN);head.addView(edit,lp());edit.setOnClickListener(v->editName());
        page.addView(head,lp());
        content=linear(1);pad(content,14);page.addView(content,lp());
        space(content,8);
        TextView h=txt("بدء مكالمة",21,GREEN,true);content.addView(h,lp());space(content,8);
        LinearLayout start=linear(0);
        addBtn(start,"☎ اتصال صوت",GREEN,Color.WHITE,()->call("مكالمة صوتية",room(),true));
        addBtn(start,"▣ فيديو",GOLD,GREEN,()->call("مكالمة فيديو",room(),false));
        content.addView(start,lp());space(content,8);
        Button pstn=button("☎  الاتصال بأرقام الموبايل العادية (الإنترنت)",0xffe4eadf,GREEN);
        content.addView(pstn,lp());pstn.setOnClickListener(v->internetDialer());space(content,7);
        Button linesButton=button("⚙  إدارة أرقامي المملوكة للتوثيق",0xfff6ebcd,GREEN);
        content.addView(linesButton,lp());linesButton.setOnClickListener(v->manageCallerIds());space(content,8);
        TextView carrierNote=txt("تنبيه: الاتصال بالأرقام العادية غير مفعل بعد. يلزم توثيق الأرقام وربط شركة اتصالات مرخص لها أولاً.",12,0xff866b32,false);
        content.addView(carrierNote,lp());space(content,8);
        Button join=button("🔗 الانضمام من رابط",0xffe1eee7,GREEN);
        content.addView(join,lp());join.setOnClickListener(v->join());
        space(content,24);
        LinearLayout peopleHeader=linear(0);
        TextView peopleLabel=txt("الأشخاص  ("+people.length()+")",19,GREEN,true);
        peopleHeader.addView(peopleLabel,new LinearLayout.LayoutParams(0,dp(55),1));
        Button add=button("+ إضافة شخص",GREEN,Color.WHITE); peopleHeader.addView(add,new LinearLayout.LayoutParams(dp(120),dp(48)));
        add.setOnClickListener(v->addPerson());content.addView(peopleHeader,lp());
        if(people.length()==0){content.addView(txt("لسه ما أضفتش أشخاص. ابدأ بإضافة اسم.",13,0xff6b7b72,false),lp());}
        for(int i=0;i<people.length();i++){JSONObject p=people.optJSONObject(i);if(p==null)continue;
            String id=p.optString("id"), person=p.optString("name"), phone=p.optString("phone");
            LinearLayout card=linear(1);pad(card,11);card.setBackground(bg(Color.WHITE,14));
            card.addView(txt("👤  "+person,17,TEXT,true),lp());
            if(!phone.isEmpty())card.addView(txt("     "+phone,12,0xff77857b,false),lp());
            space(card,8);
            LinearLayout actions=linear(0);
            addBtn(actions,"☎ صوت",0xffe5f2eb,GREEN,()->call("مكالمة صوتية مع "+person,room(),true));
            addBtn(actions,"▣ فيديو",0xfffff3d4,GREEN,()->call("مكالمة فيديو مع "+person,room(),false));
            addBtn(actions,"حذف",0xfffee9e8,0xff994343,()->removePerson(id,person));
            card.addView(actions,lp());LinearLayout.LayoutParams cp=lp();cp.setMargins(0,dp(6),0,dp(6));content.addView(card,cp);
        }
        space(content,25);
        LinearLayout groupHeader=linear(0);
        groupHeader.addView(txt("المجموعات  ("+groups.length()+")",19,GREEN,true),new LinearLayout.LayoutParams(0,dp(55),1));
        Button groupAdd=button("+ مجموعة",GREEN,Color.WHITE);groupHeader.addView(groupAdd,new LinearLayout.LayoutParams(dp(120),dp(48)));
        groupAdd.setOnClickListener(v->addGroup());content.addView(groupHeader,lp());
        if(groups.length()==0)content.addView(txt("اعمل مجموعة علشان تكلم أكثر من شخص في نفس الغرفة.",13,0xff6b7b72,false),lp());
        for(int i=0;i<groups.length();i++){JSONObject g=groups.optJSONObject(i);if(g==null)continue;
            String id=g.optString("id"), label=g.optString("name"), roomid=g.optString("room");
            LinearLayout card=linear(1);pad(card,11);card.setBackground(bg(Color.WHITE,14));
            card.addView(txt("♧  "+label,17,TEXT,true),lp());space(card,9);
            LinearLayout actions=linear(0);
            addBtn(actions,"ابدأ",GREEN,Color.WHITE,()->chooseCall(label,roomid));
            addBtn(actions,"ادعو الناس",0xfffff3d4,GREEN,()->share(url(roomid,false)));
            addBtn(actions,"حذف",0xfffee9e8,0xff994343,()->removeGroup(id,label));
            card.addView(actions,lp());LinearLayout.LayoutParams cp=lp();cp.setMargins(0,dp(6),0,dp(6));content.addView(card,cp);
        }
        space(content,20);TextView note=txt(
        "نسخة تجريبية: إضافة الأشخاص على الموبايل فقط. المكالمات تفتح في Jitsi وتحتاج إنترنت وإرسال دعوة. لا توجد مكالمات واردة برنة أو حسابات مستخدمين حتى الآن.",12,0xff60776a,false);
        note.setPadding(dp(10),dp(12),dp(10),dp(20));content.addView(note,lp());
    }
    private void editName(){
        EditText n=new EditText(this);n.setSingleLine(true);n.setText(prefs.getString("name",""));n.setHint("اسمك");
        new AlertDialog.Builder(this).setTitle("الاسم الظاهر").setView(n)
            .setPositiveButton("حفظ",(d,w)->{String s=n.getText().toString().trim();if(!s.isEmpty())prefs.edit().putString("name",s).apply();render();})
            .setNegativeButton("إلغاء",null).show();
    }
    private void addPerson(){
        LinearLayout layout=linear(1);pad(layout,18);
        EditText n=new EditText(this);n.setHint("اسم الشخص");n.setSingleLine(true);layout.addView(n,lp());
        EditText p=new EditText(this);p.setHint("رقم الموبايل (اختياري)");p.setInputType(3);p.setSingleLine(true);layout.addView(p,lp());
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle("إضافة شخص").setView(layout)
            .setPositiveButton("حفظ",null).setNegativeButton("إلغاء",null).create();
        dialog.setOnShowListener(v->dialog.getButton(-1).setOnClickListener(c->{
            String name=n.getText().toString().trim();if(name.isEmpty()){n.setError("اكتب الاسم");return;}
            JSONObject obj=new JSONObject();
            try{obj.put("id",room());obj.put("name",name);obj.put("phone",p.getText().toString().trim());people.put(obj);save();render();dialog.dismiss();}
            catch(Exception e){Toast.makeText(this,"تعذر حفظ الاسم",0).show();}
        }));dialog.show();
    }
    private void addGroup(){
        EditText n=new EditText(this);n.setHint("اسم المجموعة");n.setSingleLine(true);
        AlertDialog d=new AlertDialog.Builder(this).setTitle("مجموعة جديدة").setView(n)
            .setPositiveButton("إنشاء",null).setNegativeButton("إلغاء",null).create();
        d.setOnShowListener(v->d.getButton(-1).setOnClickListener(c->{
            String name=n.getText().toString().trim();if(name.isEmpty()){n.setError("اكتب اسم المجموعة");return;}
            try{JSONObject obj=new JSONObject();obj.put("id",room());obj.put("room",room());obj.put("name",name);
                groups.put(obj);save();render();d.dismiss();
            }catch(Exception e){Toast.makeText(this,"تعذر إنشاء المجموعة",0).show();}
        }));d.show();
    }
    private void removePerson(String id,String label){
        new AlertDialog.Builder(this).setTitle("حذف "+label+"؟").setNegativeButton("إلغاء",null)
            .setPositiveButton("حذف",(d,w)->{
                JSONArray next=new JSONArray();for(int i=0;i<people.length();i++){JSONObject o=people.optJSONObject(i);if(o!=null&&!id.equals(o.optString("id")))next.put(o);}
                people=next;save();render();
            }).show();
    }
    private void removeGroup(String id,String label){
        new AlertDialog.Builder(this).setTitle("حذف المجموعة "+label+"؟").setNegativeButton("إلغاء",null)
            .setPositiveButton("حذف",(d,w)->{
                JSONArray next=new JSONArray();for(int i=0;i<groups.length();i++){JSONObject o=groups.optJSONObject(i);if(o!=null&&!id.equals(o.optString("id")))next.put(o);}
                groups=next;save();render();
            }).show();
    }
    // Local records are unverified candidates only. Never accept a caller ID
    // as authorized without confirmation from the trusted provider backend.
    private String formatEgyptCallerId(String canonical){
        // Keep the actual E.164 number for eventual provider verification.
        // Display it without the plus sign so the local 01... becomes 201...
        if(canonical != null && canonical.startsWith("+20") && canonical.length()==13) return canonical.substring(1);
        return canonical;
    }
    private String egyptMobile(String raw){
        String s=raw.trim().replace(" ","").replace("-","").replace("(","").replace(")","");
        if(s.matches("01[0125][0-9]{8}"))return "+20"+s.substring(1);
        if(s.matches("201[0125][0-9]{8}"))return "+"+s;
        if(s.matches("\\+201[0125][0-9]{8}"))return s;
        return null;
    }
    private void internetDialer(){
        LinearLayout form=linear(1);pad(form,18);
        form.addView(txt("اتصال إنترنت لرقم موبايل عادي - بدون استخدام شريحتك",15,GREEN,true),lp());
        space(form,9);
        EditText dest=new EditText(this);
        dest.setHint("رقم العميل 01xxxxxxxxx");
        dest.setSingleLine(true);dest.setInputType(android.text.InputType.TYPE_CLASS_PHONE);
        dest.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        form.addView(dest,lp());space(form,14);
        form.addView(txt("اختار الرقم اللي هتطلب توثيقه علشان يظهر للعميل:",14,GREEN,true),lp());
        space(form,7);
        android.widget.RadioGroup lines=new android.widget.RadioGroup(this);
        lines.setOrientation(android.widget.RadioGroup.VERTICAL);
        lines.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        final String[] picked={prefs.getString("preferred_caller_id","")};
        if(callerCandidates.length()==0){
            form.addView(txt("مفيش أرقام مضافة. اضغط إدارة الأرقام وأضف خطوطك الثلاثة.",13,0xff956c30,false),lp());
        }
        for(int i=0;i<callerCandidates.length();i++){
            JSONObject obj=callerCandidates.optJSONObject(i);
            if(obj==null)continue;
            String phone=obj.optString("number"),label=obj.optString("name");
            RadioButton item=new RadioButton(this);
            item.setId(View.generateViewId());
            item.setText(label+"  •  "+formatEgyptCallerId(phone)+"  [بانتظار موافقة المزود]");
            item.setTextColor(GREEN);item.setTextSize(14);
            item.setPadding(dp(6),dp(8),dp(6),dp(8));
            item.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
            if(phone.equals(picked[0]))item.setChecked(true);
            item.setOnClickListener(v->{
                picked[0]=phone;
                prefs.edit().putString("preferred_caller_id",phone).apply();
                Toast.makeText(this,"تم حفظ الرقم المفضل؛ لم يتم تفعيل الاتصال",Toast.LENGTH_SHORT).show();
            });
            lines.addView(item,new LinearLayout.LayoutParams(-1,-2));
        }
        form.addView(lines,lp());
        space(form,10);
        Button manage=button("إضافة أو مراجعة أرقامك",0xffe4eee8,GREEN);
        form.addView(manage,lp());manage.setOnClickListener(v->manageCallerIds());
        space(form,12);
        TextView warning=txt("الخطوط الموجودة هنا مش موثقة عند شركة الاتصال لسه. ميزة المكالمة الحقيقية مش هتشتغل غير بعد موافقة المزود وربط السيرفر والتحقق من ملكية كل خط. اختيار الرقم في الموبايل لا يغيّر Caller ID وحده.",12,0xff8b6450,false);
        form.addView(warning,lp());
        ScrollView scroller=new ScrollView(this);scroller.addView(form);
        new AlertDialog.Builder(this)
            .setTitle("الاتصال بأرقام العملاء")
            .setView(scroller)
            .setPositiveButton("متطلبات التفعيل",(d,w)->requirements())
            .setNegativeButton("إغلاق",null).show();
    }
    private void requirements(){
        new AlertDialog.Builder(this).setTitle("متطلبات الاتصال الحقيقي")
            .setMessage("1) اختيار مزود VoIP يدعم وجهة الاتصال وإظهار أرقامك المصرية بشكل قانوني.\n\n"+
                "2) توثيق ملكية كل رقم برمز من المزود، وليس بمجرد كتابته هنا.\n\n"+
                "3) ربط خدمة اتصالات آمنة على سيرفر وعدم وضع مفاتيح الدفع في التطبيق.\n\n"+
                "4) اختبار ظهور Caller ID على شبكات مصر قبل التفعيل.\n\n"+
                "الرد على أرقامك الموجودة يظل عبر شركة الشريحة الحالية ما لم يُفعّل تحويل أو ربط مستقل.")
            .setPositiveButton("تمام",null).show();
    }
    private void manageCallerIds(){
        LinearLayout layout=linear(1);pad(layout,16);
        TextView header=txt("أرقامك المُضافة للتوثيق (غير مفعلة للاتصال)",15,GREEN,true);
        layout.addView(header,lp());space(layout,10);
        if(callerCandidates.length()==0){
            layout.addView(txt("لم تُضف أي رقم بعد.",13,0xff7a877e,false),lp());space(layout,10);
        }
        for(int i=0;i<callerCandidates.length();i++){
            JSONObject o=callerCandidates.optJSONObject(i);if(o==null)continue;
            String id=o.optString("id"),name=o.optString("name"),num=o.optString("number");
            LinearLayout row=linear(1);
            row.setBackground(bg(0xfff3f6f1,12));pad(row,9);
            row.addView(txt(name+"  "+formatEgyptCallerId(num),15,GREEN,true),lp());
            row.addView(txt("الحالة: غير موثق — ليس جاهزًا للاتصال",12,0xff8d6d30,false),lp());
            Button rm=button("حذف الرقم",0xfffcebe8,0xff9b3333);
            row.addView(rm,lp());rm.setOnClickListener(v->{
                JSONArray next=new JSONArray();
                for(int j=0;j<callerCandidates.length();j++){
                    JSONObject c=callerCandidates.optJSONObject(j);
                    if(c!=null&&!id.equals(c.optString("id")))next.put(c);
                }
                callerCandidates=next;save();manageCallerIds();
            });
            layout.addView(row,lp());space(layout,8);
        }
        Button add=button("+ إضافة رقم أملكه",GREEN,Color.WHITE);
        layout.addView(add,lp());add.setOnClickListener(v->addCallerCandidate());space(layout,9);
        TextView note=txt("إضافة الرقم هنا لا تثبت الملكية. لا يمكن اختيار أي رقم للاتصال إلا بعد التحقق من الشركة وربط الخادم.",12,0xff7d755e,false);
        layout.addView(note,lp());
        ScrollView scroll=new ScrollView(this);scroll.addView(layout);
        new AlertDialog.Builder(this).setTitle("إدارة أرقام المتصل").setView(scroll)
           .setNegativeButton("إغلاق",null).show();
    }
    private void addCallerCandidate(){
        LinearLayout form=linear(1);pad(form,18);
        EditText name=new EditText(this);name.setSingleLine(true);name.setHint("اسم الخط: شغل، معرض، شخصي...");form.addView(name,lp());
        TextView formatNote=txt("مثال: 01012345678 هيظهر 201012345678 (بإضافة 2 أول الرقم)",13,GREEN,false);
        form.addView(formatNote,lp());space(form,6);
        if(callerCandidates.length()>=3){new AlertDialog.Builder(this).setMessage("مسموح بتسجيل 3 أرقام في النسخة دي. احذف رقم قديم لو عايز تغيّره.").setPositiveButton("تمام",null).show();return;}
        EditText number=new EditText(this);number.setSingleLine(true);
        number.setInputType(android.text.InputType.TYPE_CLASS_PHONE);
        number.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);number.setHint("01xxxxxxxxx");
        form.addView(number,lp());
        AlertDialog d=new AlertDialog.Builder(this).setTitle("إضافة رقم تملكه للتوثيق")
            .setView(form).setPositiveButton("حفظ للمتابعة",null)
            .setNegativeButton("إلغاء",null).create();
        d.setOnShowListener(v->d.getButton(-1).setOnClickListener(v2->{
            String label=name.getText().toString().trim(),num=egyptMobile(number.getText().toString());
            if(label.isEmpty()){name.setError("اكتب اسم الخط");return;}
            if(num==null){number.setError("اكتب رقم موبايل مصري صحيح");return;}
            for(int i=0;i<callerCandidates.length();i++){
                JSONObject p=callerCandidates.optJSONObject(i);
                if(p!=null&&num.equals(p.optString("number"))){number.setError("الرقم موجود بالفعل");return;}
            }
            try{JSONObject obj=new JSONObject();obj.put("id",room());obj.put("name",label);obj.put("number",num);
                obj.put("status","pending");callerCandidates.put(obj);save();d.dismiss();
                Toast.makeText(this,"اتحفظ كرقم غير موثق",Toast.LENGTH_LONG).show();manageCallerIds();
            }catch(Exception e){Toast.makeText(this,"تعذر حفظ الرقم",Toast.LENGTH_SHORT).show();}
        }));
        d.show();
    }
    private void join(){
        EditText input=new EditText(this);input.setHint("رابط المكالمة");input.setSingleLine(true);input.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        new AlertDialog.Builder(this).setTitle("الانضمام إلى مكالمة").setView(input)
            .setPositiveButton("انضم",(d,w)->{
                String raw=input.getText().toString().trim();try{
                    Uri u=Uri.parse(raw);
                    String segment=u.getLastPathSegment();
                    if(!"https".equals(u.getScheme())||!"meet.jit.si".equals(u.getHost())||segment==null||!segment.matches("AyaQurania[a-f0-9]{36}"))
                        throw new Exception();
                    open(url(segment,false));
                }catch(Exception e){Toast.makeText(this,"رابط آية قرآنية غير صحيح",Toast.LENGTH_LONG).show();}
            }).setNegativeButton("إلغاء",null).show();
    }
}