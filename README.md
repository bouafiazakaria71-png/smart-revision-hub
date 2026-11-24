# راجع بذكاء

منصة تعليمية عربية لتلاميذ التعليم الثانوي في الجزائر.

## تشغيل الموقع

الموقع واجهة ثابتة مناسبة لـ GitHub Pages. ملف الدخول هو `index.html`.

1. افتح إعدادات المستودع في GitHub ثم **Pages** واختر النشر من الفرع `main` والمجلد `/ (root)`.
2. رابط الموقع: https://bouafiazakaria71-png.github.io/smart-revision-hub/

## ربط Supabase (تم إعداد ملفات الموقع)

تم إنشاء مشروع Supabase وربط إعداداته العامة في `config.js` بالفعل:

- Project URL: `https://fxrfxilxbxrkxadgfkxw.supabase.co`
- المفتاح المستخدم في المتصفح هو **Publishable key** فقط.
- تم تنفيذ `supabase-schema.sql` والتحقق من ظهور الجدولين `profiles` و`study_resources`.

لا تستبدل الإعدادات الحالية في `config.js` إلا عند تغيير مشروع Supabase. لا تضف مطلقًا مفتاح `Secret` أو `service_role` إلى ملفات GitHub.

## تفعيل تسجيل الدخول بالبريد وGoogle

### إعداد عناوين العودة في Supabase

1. افتح **Authentication → URL Configuration**.
2. ضع عنوان الموقع التالي في **Site URL**:
   `https://bouafiazakaria71-png.github.io/smart-revision-hub/`
3. أضف العنوان نفسه إلى **Redirect URLs** واحفظ.

### إعداد Google OAuth

يلزم إنشاء بيانات OAuth في حساب Google ثم حفظها في لوحة Supabase؛ لا يحتاج الموقع إلى Client Secret في ملفاته.

1. افتح [Google Cloud Console](https://console.cloud.google.com/) وأنشئ OAuth Client من نوع **Web application**.
2. في **Authorized JavaScript origins** أضف:
   `https://bouafiazakaria71-png.github.io`
3. في **Authorized redirect URIs** أضف عنوان Callback الذي يعرضه Supabase في **Authentication → Sign In / Providers → Google**. لمشروعك يكون عادةً:
   `https://fxrfxilxbxrkxadgfkxw.supabase.co/auth/v1/callback`
   استخدم القيمة التي يعرضها Supabase إذا اختلفت.
4. أنشئ OAuth Client وانسخ **Client ID** و**Client Secret**.
5. ارجع إلى Supabase وافتح **Authentication → Sign In / Providers → Google**، فعّل Google، ثم أدخل Client ID وClient Secret واحفظ.
6. إذا كان تطبيق Google في وضع الاختبار، أضف حسابات الاختبار المسموح لها بتجربة الدخول في إعدادات Google OAuth.

بعد حفظ الإعدادات، افتح الموقع واضغط «المتابعة باستخدام Google» لاختبار تسجيل الدخول. لا ترسل Client Secret أو كلمات المرور أو مفاتيح Secret إلى أي شخص.

## حساب المسؤول

بعد إنشاء حسابك وتأكيد البريد الإلكتروني، عيّن حسابك مسؤولًا من **SQL Editor** باستخدام الاستعلام الموجود في نهاية `supabase-schema.sql` بعد استبدال `YOUR_ADMIN_EMAIL` ببريد حسابك. نفّذ هذا الاستعلام بنفسك من لوحة Supabase، ولا تمنح دور المسؤول لأي حساب آخر دون حاجة.

## مكوّنات الأمان

- Supabase Auth يتولى التحقق من كلمات المرور وإدارة الجلسات والرموز وتجديدها.
- الواجهة تستخدم المفتاح العام فقط. المفتاح العام ليس سرًا، لكن يجب حماية البيانات بسياسات RLS.
- لا تضع أبدًا `service_role` أو مفاتيح مزوّد الذكاء الاصطناعي في `index.html` أو `config.js`.
- صلاحية المسؤول تُقرأ من جدول profiles، وعمليات إضافة الموارد محمية بسياسات RLS في قاعدة البيانات.
- تغيير دور المستخدم محظور من واجهة المستخدم بواسطة trigger. غيّر الدور إداريًا من SQL Editor فقط.
- استخدم HTTPS، فعّل تأكيد البريد، واضبط قيود كلمات المرور والحماية من إساءة الاستخدام في إعدادات Supabase.
- لا توجد خدمة ذكاء اصطناعي حقيقية مفعّلة بعد؛ المساعد الحالي واجهة إرشادية فقط. ربط الذكاء الاصطناعي يتطلب خادمًا/Edge Function يحفظ المفتاح السري بعيدًا عن المتصفح.

## الملفات

- `index.html`: الواجهة المتجاوبة وسلوك الأزرار والنماذج.
- `config.js`: إعدادات Supabase العامة (المفتاح العام فقط).
- `supabase-schema.sql`: الجداول وسياسات الوصول والتريغرات.

## ملاحظات

- لا تضع بيانات حقيقية أو أسرارًا في المستودع العام.
- قبل إطلاق المنصة للجمهور، اختبر التسجيل وتأكيد البريد واستعادة كلمة المرور وتسجيل الخروج وصلاحيات المسؤول.