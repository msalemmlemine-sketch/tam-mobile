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
    const targetUserId = String(body.user_id || '');
    const password = String(body.new_password || '').trim();
    if (!targetUserId || password.length < 6) return json({ error: 'A user_id and password of at least 6 characters are required' }, 400);
    const updated = await admin.auth.admin.updateUserById(targetUserId, { password });
    if (updated.error) throw updated.error;
    const { error } = await admin.from('profiles').update({ must_change_password: true }).eq('id', targetUserId);
    if (error) throw error;
    return json({ ok: true });
  } catch (e) { return json({ error: String(e) }, 500); }
});
