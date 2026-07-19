// Educaty — apagamento de conta (compartilhado entre `delete-account` e `admin-delete-account`).
//
// Uma fonte só pra não divergirem. A lógica de LGPD (o QUE apagar) mora aqui; QUEM pode pedir
// (o próprio dono via JWT vs. um admin via segredo) e a guarda de afiliado ficam em cada função.
//
// Segredos: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// deno-lint-ignore no-explicit-any
type Admin = any;

/** Client service-role do projeto do Educaty (apaga qualquer usuário). */
export function makeAdmin(): Admin {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );
}

/** Existe afiliado ligado a este usuário? (guarda fiscal — os chamadores decidem o que fazer.) */
export async function isAffiliate(admin: Admin, uid: string): Promise<boolean> {
  const { data } = await admin.from('affiliates').select('id').eq('user_id', uid).maybeSingle();
  return !!data;
}

/** É dono (owner) de algum org com dados? Bloqueia o delete (o tenant precisa ser resolvido antes). */
export async function ownsOrg(admin: Admin, uid: string): Promise<boolean> {
  const { data } = await admin.from('orgs').select('id').eq('owner_id', uid).limit(1);
  return !!(data && data.length > 0);
}

/** Apaga recursivamente todos os arquivos de uma pasta (prefixo) de um bucket. Best-effort. */
async function removeFolder(admin: Admin, bucket: string, prefix: string): Promise<number> {
  const toRemove: string[] = [];
  const walk = async (path: string): Promise<void> => {
    const { data, error } = await admin.storage.from(bucket).list(path, { limit: 1000 });
    if (error || !data) return;
    for (const entry of data as { name: string; id: string | null }[]) {
      const full = path ? `${path}/${entry.name}` : entry.name;
      if (entry.id === null) await walk(full); // subpasta
      else toRemove.push(full);
    }
  };
  await walk(prefix);
  for (let i = 0; i < toRemove.length; i += 100) {
    await admin.storage.from(bucket).remove(toRemove.slice(i, i + 100));
  }
  return toRemove.length;
}

/**
 * Apaga a conta `uid` e TODOS os dados vinculados (LGPD + exigência das lojas).
 * NÃO checa afiliado nem posse de org — quem chama decide isso antes. Passos:
 *  1) arquivos do Storage do usuário (não cascateiam com o Auth);
 *  2) desvincula a atribuição de afiliado (referrals.subscriber_id → null; FK sem cascade);
 *  3) apaga trial_redemptions (o anti-abuso por APARELHO continua valendo);
 *  4) apaga o usuário do Auth → CASCADE apaga profiles/memberships/etc.
 */
export async function eraseUser(
  admin: Admin,
  uid: string,
  logTag: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
  for (const bucket of ['avatars', 'logos']) {
    try {
      await removeFolder(admin, bucket, uid);
    } catch {
      // best-effort: um bucket não bloqueia a exclusão
    }
  }

  await admin.from('referrals').update({ subscriber_id: null }).eq('subscriber_id', uid);
  await admin.from('trial_redemptions').delete().eq('user_id', uid);

  const { error: delErr } = await admin.auth.admin.deleteUser(uid);
  if (delErr) {
    console.error(`[${logTag}] deleteUser falhou:`, delErr.message, 'uid:', uid);
    return { ok: false, error: delErr.message };
  }
  return { ok: true };
}
