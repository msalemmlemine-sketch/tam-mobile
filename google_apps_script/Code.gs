/**
 * TAM Mobile - Google Drive JSON Sync API
 *
 * Web App: Execute as the script owner, access: Anyone.
 * The script stores the complete application state in one JSON file
 * inside the owner's Google Drive.
 *
 * Configure the API key once by running setApiKey('YOUR_SECRET') from
 * the Apps Script editor. The key is kept in Script Properties, not in
 * the Drive JSON file.
 */

const FILE_NAME = 'TAM_Mobile_shared_state.json';
const PROP_KEY = 'TAM_API_KEY';
const PROP_FILE_ID = 'TAM_STATE_FILE_ID';

function setApiKey(secret) {
  if (!secret || String(secret).length < 16) {
    throw new Error('API key must contain at least 16 characters.');
  }
  PropertiesService.getScriptProperties().setProperty(PROP_KEY, String(secret));
}

function doGet(e) {
  try {
    requireKey_(e && e.parameter ? e.parameter.key : '');
    const action = (e && e.parameter && e.parameter.action) || 'pull';
    if (action === 'pull') return json_(readState_());
    if (action === 'listArchives') return json_({ ok: true, files: listArchives_() });
    if (action === 'pullArchive') return json_(pullArchive_(e.parameter.fileName));
    return json_({ ok: false, error: 'Unsupported GET action.' });
  } catch (err) {
    return json_({ ok: false, error: String(err.message || err) });
  }
}

function doPost(e) {
  try {
    const body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    if (body.action === 'sendWhatsApp') return json_({ok:true, result:sendWhatsApp_(body)});
    requireKey_(body.apiKey);
    if (body.action === 'pull') return json_(readState_());
    if (body.action === 'pushArchive') return json_(pushArchive_(body));
    if (body.action === 'push' || !body.action) return json_(pushState_(body));
    return json_({ ok: false, error: 'Unsupported action.' });
  } catch (err) {
    return json_({ ok: false, error: String(err.message || err) });
  }
}

// ==================== أرشيف التقارير (PDF/Excel) ====================
// مجلد منفصل تمامًا عن ملف الحالة الحية (FILE_NAME) — رفع/تنزيل ملف
// أرشيف لا يمس أبدًا readState_/pushState_، فلا يمكن له إطلاقًا أن
// يُصادم أو يمحو بيانات حية مهما حدث.
const ARCHIVE_FOLDER_NAME = 'TAM_Mobile_report_archives';

function getOrCreateArchiveFolder_() {
  const props = PropertiesService.getScriptProperties();
  const savedId = props.getProperty('TAM_ARCHIVE_FOLDER_ID');
  if (savedId) {
    try { return DriveApp.getFolderById(savedId); } catch (_) {}
  }
  const folder = DriveApp.createFolder(ARCHIVE_FOLDER_NAME);
  props.setProperty('TAM_ARCHIVE_FOLDER_ID', folder.getId());
  return folder;
}

function pushArchive_(body) {
  const fileName = String(body.fileName || '').trim();
  const contentBase64 = String(body.contentBase64 || '');
  if (!fileName || !contentBase64) return { ok: false, error: 'fileName and contentBase64 are required.' };
  const folder = getOrCreateArchiveFolder_();
  const bytes = Utilities.base64Decode(contentBase64);
  const blob = Utilities.newBlob(bytes, 'application/octet-stream', fileName);
  // نسخ سابقة بنفس الاسم تُحذف أولًا حتى لا يتراكم أرشيف مكرر بلا حدود.
  const existing = folder.getFilesByName(fileName);
  while (existing.hasNext()) existing.next().setTrashed(true);
  folder.createFile(blob);
  return { ok: true };
}

function listArchives_() {
  const folder = getOrCreateArchiveFolder_();
  const it = folder.getFiles();
  const out = [];
  while (it.hasNext()) {
    const f = it.next();
    out.push({ fileName: f.getName(), updatedAt: f.getLastUpdated().toISOString(), sizeBytes: f.getSize() });
  }
  return out;
}

function pullArchive_(fileName) {
  const folder = getOrCreateArchiveFolder_();
  const files = folder.getFilesByName(String(fileName || ''));
  if (!files.hasNext()) return { ok: false, error: 'File not found.' };
  const file = files.next();
  const bytes = file.getBlob().getBytes();
  return { ok: true, contentBase64: Utilities.base64Encode(bytes) };
}

function pushState_(body) {
  if (!body.state || typeof body.state !== 'object') {
    return { ok: false, error: 'state is required.' };
  }

  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const current = readState_();
    const currentRevision = Number(current.revision || 0);
    const baseRevision = Number(body.baseRevision || 0);

    // Optimistic concurrency: never overwrite a newer copy.
    if (baseRevision !== currentRevision) {
      return {
        ok: false,
        errorCode: 'REVISION_CONFLICT',
        error: 'A newer revision already exists on Google Drive. Pull it before pushing again.',
        revision: currentRevision,
      };
    }

    const nextRevision = currentRevision + 1;
    const state = body.state;
    state.schema = Number(state.schema || 1);
    state.updatedAt = new Date().toISOString();
    state.updatedByDevice = String(body.deviceId || 'unknown');

    const payload = {
      ok: true,
      revision: nextRevision,
      state: state,
      updatedAt: state.updatedAt,
      updatedByDevice: state.updatedByDevice,
    };

    const file = getOrCreateFile_();
    file.setContent(JSON.stringify(payload));
    return { ok: true, revision: nextRevision, updatedAt: state.updatedAt };
  } finally {
    lock.releaseLock();
  }
}

function readState_() {
  const file = getOrCreateFile_();
  const text = file.getBlob().getDataAsString('UTF-8').trim();
  if (!text) return { ok: true, revision: 0, state: emptyState_() };
  const parsed = JSON.parse(text);
  if (!parsed || typeof parsed !== 'object') throw new Error('Invalid state file.');
  return parsed;
}

function emptyState_() {
  return {
    schema: 1,
    generatedAt: new Date().toISOString(),
    settings: [],
    districts: [],
    institutions: [],
    members: [],
    subscription_settings: [],
    subscription_payments: [],
    subscription_dues: [],
    payment_allocations: [],
    subscription_rates: [],
    membership_card_payments: [],
    subscription_name_aliases: [],
    subscription_import_batches: [],
    regional_expenses: [],
    fund_opening_overrides: [],
    whatsapp_messages: [],
  };
}

function getOrCreateFile_() {
  const props = PropertiesService.getScriptProperties();
  const savedId = props.getProperty(PROP_FILE_ID);
  if (savedId) {
    try { return DriveApp.getFileById(savedId); } catch (_) {}
  }
  const file = DriveApp.createFile(
    FILE_NAME,
    JSON.stringify({ ok: true, revision: 0, state: emptyState_() }),
    MimeType.PLAIN_TEXT
  );
  props.setProperty(PROP_FILE_ID, file.getId());
  return file;
}

function requireKey_(provided) {
  const expected = PropertiesService.getScriptProperties().getProperty(PROP_KEY);
  if (!expected) throw new Error('API key is not configured. Run setApiKey() first.');
  if (!provided || String(provided) !== String(expected)) throw new Error('Unauthorized.');
}

function json_(value) {
  return ContentService.createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}


function configureWhatsApp(accessToken, phoneNumberId, clientSecret) {
  PropertiesService.getScriptProperties().setProperties({WA_ACCESS_TOKEN:String(accessToken),WA_PHONE_NUMBER_ID:String(phoneNumberId),WA_CLIENT_SECRET:String(clientSecret)});
}
function sendWhatsApp_(body) {
  const props=PropertiesService.getScriptProperties();
  const token=props.getProperty('WA_ACCESS_TOKEN'), phoneId=props.getProperty('WA_PHONE_NUMBER_ID'), secret=props.getProperty('WA_CLIENT_SECRET');
  if(!token||!phoneId||!secret) throw new Error('WhatsApp is not configured.');
  if(String(body.clientSecret||'')!==String(secret)) throw new Error('Unauthorized WhatsApp client.');
  const phone=String(body.phone||'').replace(/[^0-9]/g,'');
  if(phone.length<8) throw new Error('Invalid phone number. Use international format.');
  const params=Array.isArray(body.parameters)?body.parameters.map(String):[];
  const template={name:String(body.templateName||'tam_overdue_reminder'),language:{code:String(body.languageCode||'ar')}};
  if(params.length) template.components=[{type:'body',parameters:params.map(function(v){return {type:'text',text:v};})}];
  const payload={messaging_product:'whatsapp',to:phone,type:'template',template:template};
  const r=UrlFetchApp.fetch('https://graph.facebook.com/v23.0/'+encodeURIComponent(phoneId)+'/messages',{method:'post',contentType:'application/json',muteHttpExceptions:true,headers:{Authorization:'Bearer '+token},payload:JSON.stringify(payload)});
  const code=r.getResponseCode(), data=JSON.parse(r.getContentText()||'{}');
  if(code<200||code>=300) throw new Error(data.error?JSON.stringify(data.error):'WhatsApp API error '+code);
  return data;
}
function installWhatsAppReminderTrigger(){
  ScriptApp.getProjectTriggers().filter(function(t){return t.getHandlerFunction()==='runWhatsAppReminders';}).forEach(function(t){ScriptApp.deleteTrigger(t);});
  ScriptApp.newTrigger('runWhatsAppReminders').timeBased().everyDays(1).atHour(9).create();
}
// ⚠️ إصلاح حظر واتساب (2026-09): كانت هذه الحلقة تستدعي
// UrlFetchApp.fetch لكل منتسب متأخر فورًا وبتتابع مباشر بلا أي فاصل
// زمني — نمط سلوك يُشبه بوتات الإرسال الجماعي في نظر رصد Meta
// الآلي، وقد يؤدي لحظر رقم واتساب النقابة كليًا. الإصلاح: فاصل
// عشوائي (Jitter) بين 4 و9 ثوانٍ قبل كل رسالة (ما عدا الأولى)، وحد
// أقصى لعدد الرسائل في نفس اليوم عبر Script Properties، فوق آلية
// deduplication (WA_SENT_...) الموجودة أصلًا التي تمنع إعادة إرسال
// نفس المنتسب في نفس اليوم عند تكرار تشغيل الدالة.
const WA_DAILY_LIMIT = 200;

function runWhatsAppReminders(){
  const day=new Date().getDate(); if(day!==24&&day!==26)return;
  const state=readState_().state||{}, members=state.members||[], payments=state.subscription_payments||[], dues=state.subscription_dues||[], allocations=state.payment_allocations||[];
  const settings={}; (state.subscription_settings||[]).forEach(function(r){settings[r.setting_key]=Number(r.setting_value||0);});
  const monthly=settings.monthly_amount||100, year=new Date().getFullYear(), month=new Date().getMonth()+1, props=PropertiesService.getScriptProperties();
  const dueMap={}; dues.forEach(function(d){ if(Number(d.due_year)===year) dueMap[String(d.id)] = d; });
  const allocated={}; allocations.forEach(function(a){ const d=dueMap[String(a.due_id)]; if(d) allocated[String(d.member_id)+'_'+String(d.due_month)] = (allocated[String(d.member_id)+'_'+String(d.due_month)]||0)+Number(a.allocated_amount||0); });

  const dailyCountKey = 'WA_DAILY_COUNT_' + new Date().toISOString().slice(0, 10);
  let sentToday = Number(props.getProperty(dailyCountKey) || 0);
  let isFirst = true;

  members.forEach(function(m){
    if (sentToday >= WA_DAILY_LIMIT) return; // تجاوزنا الحد اليومي — تجاهل الباقي بأمان (لا كسر للحلقة).
    if(String(m.membership_status||'active')!=='active'||Number(m.is_archived||0)===1||!m.phone)return;
    let paid=0;
    for(let mm=1;mm<=month;mm++){ paid += Math.min(monthly, allocated[String(m.id)+'_'+String(mm)]||0); }
    if(!allocations.length){ payments.forEach(function(p){if(Number(p.member_id)===Number(m.id)&&Number(p.payment_year)===year)paid+=Number(p.subscription_amount||0);}); }
    const remaining=Math.max(0,month*monthly-paid); if(remaining<=0)return;
    const key='WA_SENT_'+year+'_'+day+'_'+m.id; if(props.getProperty(key))return;

    if (!isFirst) {
      Utilities.sleep(4000 + Math.floor(Math.random() * 5000)); // 4–9 ثوانٍ
    }
    isFirst = false;

    try{
      sendWhatsApp_({clientSecret:props.getProperty('WA_CLIENT_SECRET'),phone:m.phone,templateName:'tam_overdue_reminder',languageCode:'ar',parameters:[String(m.name||''),String(remaining.toFixed(0)),String(year)]});
      props.setProperty(key,new Date().toISOString());
      sentToday += 1;
      props.setProperty(dailyCountKey, String(sentToday));
    }catch(err){
      console.log(err); // فشل رسالة واحدة لا يوقف بقية المنتسبين.
    }
  });
}
