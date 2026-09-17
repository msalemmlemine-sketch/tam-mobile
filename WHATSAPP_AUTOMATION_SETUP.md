# WhatsApp Automation

تم تجهيز TAM Mobile للإرسال التلقائي الرسمي عبر WhatsApp Cloud API بواسطة Google Apps Script.

1. أنشئ قالبًا معتمدًا باسم `tam_overdue_reminder` في Meta.
2. في Apps Script شغّل `configureWhatsApp(accessToken, phoneNumberId, clientSecret)` مرة واحدة.
3. شغّل `installWhatsAppReminderTrigger()` مرة واحدة.
4. استخدم أرقام المنتسبين بالصيغة الدولية.

يعمل التذكير في يومي 24 و26، ويرسل فقط لمن لديه متبقٍ. يتم منع التكرار لكل منتسب ولكل يوم.

ملاحظة: WhatsApp Cloud API الرسمي ليس مضمونًا أن يكون مجانيًا دائمًا؛ الأسعار والسياسات تحددها Meta.
