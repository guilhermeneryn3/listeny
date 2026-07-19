// Listeny — Edge Function `redeem-code`
// Resgata um cupom (promocional OU de afiliado) e CONCEDE um trial de premium via RevenueCat,
// sem cartão. Anti-abuso: 1 trial por CONTA e 1 por APARELHO. Grava a atribuição (de onde veio).
// Segredos: REVENUECAT_SECRET_KEY + SUPABASE_URL/SERVICE_ROLE_KEY/ANON_KEY.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const DAY_MS = 24 * 60 * 60 * 1000;
const AFFILIATE_TRIAL_DAYS = 10; // isca do afiliado (10 dias vs 7 padrão da loja)

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/** Concede/estende o entitlement `premium` por `days` dias (promotional; não cobra). */
async function grantPremium(userId: string, days: number, secret: string): Promise<void> {
  const enc = encodeURIComponent(userId);
  const RC = 'https://api.revenuecat.com/v1';
  const h = { Authorization: `Bearer ${secret}`, 'Content-Type': 'application/json' };
  const sub = await fetch(`${RC}/subscribers/${enc}`, { headers: h });
  const data = (await sub.json().catch(() => null)) as
    | { subscriber?: { entitlements?: Record<string, { expires_date?: string | null }> } }
    | null;
  const current = data?.subscriber?.entitlements?.premium?.expires_date;
  const base = Math.max(Date.now(), current ? new Date(current).getTime() : 0);
  const res = await fetch(`${RC}/subscribers/${enc}/entitlements/premium/promotional`, {
    method: 'POST',
    headers: h,
    body: JSON.stringify({ end_time_ms: base + days * DAY_MS }),
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`RevenueCat ${res.status}: ${detail.slice(0, 120)}`);
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const rcSecret = Deno.env.get('REVENUECAT_SECRET_KEY');
    if (!rcSecret) return json({ error: 'RevenueCat não configurado no servidor.' }, 500);
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Sem autorização.' }, 401);

    const body = (await req.json().catch(() => null)) as { code?: string; deviceId?: string } | null;
    const code = String(body?.code ?? '').trim().toUpperCase();
    const deviceId = body?.deviceId ? String(body.deviceId) : null;
    if (!code) return json({ error: 'Informe um cupom.' }, 400);

    const url = Deno.env.get('SUPABASE_URL') ?? '';
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
    const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY') ?? '', {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData } = await userClient.auth.getUser();
    const user = userData?.user;
    if (!user) return json({ error: 'Usuário inválido.' }, 401);

    // ── Anti-abuso ──────────────────────────────────────────────────────────
    const { data: byUser } = await admin
      .from('trial_redemptions')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
    if (byUser) return json({ error: 'Você já usou um período de teste.' }, 409);

    if (deviceId) {
      const { data: byDevice } = await admin
        .from('trial_redemptions')
        .select('id')
        .eq('device_id', deviceId)
        .limit(1);
      if (byDevice && byDevice.length > 0) {
        return json({ error: 'Este aparelho já usou um período de teste.' }, 409);
      }
    }

    // ── Resolve o cupom: código promocional OU cupom de afiliado ─────────────
    let sourceKind: 'promo' | 'affiliate';
    let trialDays: number;
    let campaignId: string | null = null;
    let affiliateId: string | null = null;
    let channel = 'marketing';
    let promoRow: { id: string; uses: number } | null = null;

    const { data: promo } = await admin
      .from('promo_codes')
      .select('id, campaign_id, trial_days, max_uses, uses, valid_until, active')
      .eq('code', code)
      .maybeSingle();
    const p = promo as {
      id: string;
      campaign_id: string | null;
      trial_days: number;
      max_uses: number | null;
      uses: number;
      valid_until: string | null;
      active: boolean;
    } | null;

    const promoValid =
      !!p && p.active && (!p.valid_until || new Date(p.valid_until) > new Date()) &&
      (p.max_uses == null || p.uses < p.max_uses);

    if (promoValid && p) {
      sourceKind = 'promo';
      trialDays = p.trial_days;
      campaignId = p.campaign_id;
      promoRow = { id: p.id, uses: p.uses };
      if (campaignId) {
        const { data: camp } = await admin.from('campaigns').select('channel').eq('id', campaignId).maybeSingle();
        channel = (camp as { channel: string } | null)?.channel ?? 'marketing';
      }
    } else {
      const { data: aff } = await admin
        .from('affiliates')
        .select('id, status')
        .eq('coupon_code', code)
        .maybeSingle();
      const a = aff as { id: string; status: string } | null;
      if (a && a.status === 'approved') {
        sourceKind = 'affiliate';
        affiliateId = a.id;
        channel = 'afiliados';
        trialDays = AFFILIATE_TRIAL_DAYS;
      } else {
        return json({ error: 'Cupom inválido ou expirado.' }, 404);
      }
    }

    // ── Concede o trial no RevenueCat ────────────────────────────────────────
    try {
      await grantPremium(user.id, trialDays, rcSecret);
    } catch (e) {
      return json({ error: `Não consegui liberar o teste: ${(e as Error).message}` }, 502);
    }

    // ── Registra resgate + atribuição first-touch + consome uso ──────────────
    await admin.from('trial_redemptions').insert({
      user_id: user.id,
      device_id: deviceId,
      source_kind: sourceKind,
      code,
      campaign_id: campaignId,
      affiliate_id: affiliateId,
      granted_days: trialDays,
    });

    await admin
      .from('profiles')
      .update({
        acquisition_channel: channel,
        acquisition_source: code,
        acquisition_affiliate_id: affiliateId,
        acquisition_at: new Date().toISOString(),
      })
      .eq('user_id', user.id)
      .is('acquisition_at', null);

    if (sourceKind === 'affiliate' && affiliateId) {
      const { data: existingRef } = await admin
        .from('referrals')
        .select('id')
        .eq('subscriber_id', user.id)
        .maybeSingle();
      if (!existingRef) {
        await admin.from('referrals').insert({
          affiliate_id: affiliateId,
          coupon_code: code,
          subscriber_id: user.id,
        });
      }
    }

    if (promoRow) {
      await admin.from('promo_codes').update({ uses: promoRow.uses + 1 }).eq('id', promoRow.id);
    }

    return json({ ok: true, granted_days: trialDays, tier: 'premium' });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
