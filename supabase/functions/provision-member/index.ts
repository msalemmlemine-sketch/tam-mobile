import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  try {
    const auth = req.headers.get('Authorization');
    if (!auth) return json({ error: 'Unauthorized' }, 401);
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const caller = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const admin = createClient(url, service);
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: 'Unauthorized' }, 401);
    const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).maybeSingle();
    if (!profile || !['organization_secretary','administrator'].includes(profile.role)) return json({ error: 'Forbidden' }, 403);

    const body = await req.json();
    const memberId = Number(body.member_id);
    const memberSyncUuid = String(body.member_sync_uuid || '');
    const displayName = String(body.display_name || '').trim();
    const username = String(body.username || '').trim().toLowerCase();
    const password = String(body.password || '').trim();
    if (!memberId || !memberSyncUuid || !displayName || !username || !password) return json({ error: 'Missing member account data' }, 400);

    const email = username.includes('@') ? username : `${username}@tam.local`;
    let target: any = null;
    const listed = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (listed.error) throw listed.error;
    target = listed.data.users.find((u: any) => (u.email || '').toLowerCase() === email.toLowerCase()) || null;

    if (!target) {
      const created = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { display_name: displayName, role: 'member' } });
      if (created.error) throw created.error;
      target = created.data.user;
    } else {
      const updated = await admin.auth.admin.updateUserById(target.id, { password, user_metadata: { display_name: displayName, role: 'member' } });
      if (updated.error) throw updated.error;
    }

    const { error: pError } = await admin.from('profiles').upsert({ id: target.id, username, display_name: displayName, role: 'member', member_id: memberId, member_sync_uuid: memberSyncUuid, is_active: true, must_change_password: true }, { onConflict: 'id' });
    if (pError) throw pError;
    return json({ ok: true, user_id: target.id, username, temporary_password: password });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
