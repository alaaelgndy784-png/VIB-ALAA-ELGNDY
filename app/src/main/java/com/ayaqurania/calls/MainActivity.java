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
    private JSONArray people,groups;
    private LinearLayout content;
    private final SecureRandom rng=new SecureRandom();

    @Override public void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().setStatusBarColor(GREEN);
        getWindow().setNavigationBarColor(BG);
        prefs=getSharedPreferences("aya_qurania_local",MODE_PRIVATE);
        people=readArray("people"); groups=readArray("groups"); render();
    }
    private JSONArray readArray(String key) {try{return new JSONArray(prefs.getString(key,"[]"));}catch(Exception e){return new JSONArray();}}
    private void save(){prefs.edit().putString("people",people.toString()).putString("groups",groups.toString()).apply();}
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