// Listeny — Edge Function `admin-delete-account`
// Apaga a conta de um usuário A PEDIDO DO PAINEL N3 (servidor-a-servidor). O N3 chama com o
// segredo compartilhado em `x-admin-secret` e passa o `user_id`. A lógica de apagamento é a
// mesma da `delete-account` (dono via JWT): `_shared/erase-user.ts`.
//
// Guardas: recusa se o usuário for afiliado (reason:'affiliate') ou dono de org
// (reason:'owns_org') — o painel resolve isso antes, porque há registro fiscal/tenant em jogo.
//
// Segredos: ADMIN_DELETE_SECRET (o mesmo valor no N3) + SUPABASE_URL/SERVICE_ROLE_KEY.

import { eraseUser, isAffiliate, makeAdmin, ownsOrg } from '../_shared/erase-user.ts';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/** Comparação em tempo constante — não vaza o comprimento do prefixo correto do segredo. */
function timingSafeEqual(a: string, b: string): boolean {
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const expected = Deno.env.get('ADMIN_DELETE_SECRET') ?? '';
  const got = req.headers.get('x-admin-secret') ?? '';
  if (!expected || got.length !== expected.length || !timingSafeEqual(got, expected)) {
    return json({ error: 'unauthorized' }, 401);
  }

  try {
    const body = (await req.json().catch(() => null)) as { user_id?: string } | null;
    const uid = body?.user_id?.trim();
    if (!uid) return json({ error: 'user_id obrigatório' }, 400);

    const admin = makeAdmin();

    if (await isAffiliate(admin, uid)) return json({ ok: false, reason: 'affiliate' }, 409);
    if (await ownsOrg(admin, uid)) return json({ ok: false, reason: 'owns_org' }, 409);

    const res = await eraseUser(admin, uid, 'admin-delete-account');
    if (!res.ok) return json({ error: res.error }, 500);
    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
