// Listeny — revenuecat-sync — grava o plano (tier) do usuário no profiles.
// Fonte da verdade: a API do RevenueCat (o client não é confiável). Chamada por:
//   1) Webhook do RevenueCat (Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>).
//   2) App/portal logado (Authorization: Bearer <JWT do Supabase>), após login/compra.
// Deploy com "Verify JWT" DESLIGADO (o webhook não manda JWT do Supabase).
//
// Nota: a propagação para o tier do ORG (assinatura SaaS-branca) entra na fase de billing —
// aqui só sincronizamos a pessoa (profiles), como no VamAI.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const RC_SECRET = Deno.env.get('REVENUECAT_SECRET_KEY') ?? '';
const WEBHOOK_SECRET = Deno.env.get('REVENUECAT_WEBHOOK_SECRET') ?? '';

const admin = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

type Tier = 'free' | 'premium';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/** Consulta o RevenueCat e deriva o tier a partir dos entitlements ativos. */
async function fetchTier(appUserId: string): Promise<Tier> {
  const r = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`,
    { headers: { Authorization: `Bearer ${RC_SECRET}` } },
  );
  if (!r.ok) return 'free'; // 404 = sem assinante
  const data = await r.json();
  const ents = data?.subscriber?.entitlements ?? {};
  const now = Date.now();
  const active = (id: string): boolean => {
    const e = ents[id];
    if (!e) return false;
    if (!e.expires_date) return true; // vitalício
    return new Date(e.expires_date).getTime() > now;
  };
  return active('premium') ? 'premium' : 'free';
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ error: 'missing_authorization' }, 401);

  let appUserId: string | null = null;

  if (WEBHOOK_SECRET && token === WEBHOOK_SECRET) {
    const body = await req.json().catch(() => null);
    appUserId = body?.event?.app_user_id ?? null;
  } else {
    const { data, error } = await admin.auth.getUser(token);
    if (error || !data.user) return json({ error: 'unauthorized' }, 401);
    appUserId = data.user.id;
  }

  if (!appUserId) return json({ error: 'no_app_user_id' }, 400);
  if (appUserId.startsWith('$RCAnonymousID:')) return json({ ok: true, skipped: 'anonymous' });

  let tier = await fetchTier(appUserId);
  // Blindagem da concessão de admin: se o RC vier 'free' mas houver concessão do painel
  // (premium_since preenchido), NÃO rebaixa. A revogação limpa premium_since e volta a rebaixar.
  if (tier === 'free') {
    const { data: prof } = await admin
      .from('profiles')
      .select('premium_since')
      .eq('user_id', appUserId)
      .maybeSingle();
    if ((prof as { premium_since?: string | null } | null)?.premium_since) tier = 'premium';
  }
  const { error } = await admin
    .from('profiles')
    .update({ tier, is_premium: tier !== 'free' })
    .eq('user_id', appUserId);
  if (error) return json({ error: error.message }, 500);

  return json({ ok: true, tier });
});
