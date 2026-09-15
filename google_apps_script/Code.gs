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
    if (action !== 'pull') return json_({ ok: false, error: 'Unsupported GET action.' });
    return json_(readState_());
  } catch (err) {
    return json_({ ok: false, error: String(err.message || err) });
  }
}

function doPost(e) {
  try {
    const body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    requireKey_(body.apiKey);
    if (body.action === 'pull') return json_(readState_());
    if (body.action === 'push' || !body.action) return json_(pushState_(body));
    return json_({ ok: false, error: 'Unsupported action.' });
  } catch (err) {
    return json_({ ok: false, error: String(err.message || err) });
  }
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
    membership_card_payments: [],
    subscription_name_aliases: [],
    subscription_import_batches: [],
    regional_expenses: [],
    fund_opening_overrides: [],
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
