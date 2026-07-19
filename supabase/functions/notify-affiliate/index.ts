// Listeny — Edge Function `notify-affiliate`
// Envia e-mail transacional ao afiliado (via Resend) e registra em affiliate_notifications.
// Chamada SERVER-TO-SERVER (painel N3 e listeny-web). Autenticação = segredo em
// `x-notify-secret` (a anon key é pública, então a proteção efetiva é o segredo).
// Secrets: RESEND_API_KEY, NOTIFY_SECRET, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, x-notify-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const FROM = 'Listeny Afiliados <noreply@listeny.app>';
const PORTAL = 'https://afiliados.listeny.app';

const brl = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

type Payload = {
  affiliate_id?: string;
  event?: string;
  ref?: string;
  data?: Record<string, unknown>;
};

function reasonBlock(data: Record<string, unknown> | undefined): string {
  const reason = String(data?.reason ?? '').trim();
  return reason ? `<p><strong>Motivo:</strong> ${reason}</p>` : '';
}

function footer(path = ''): string {
  return `<p>Acesse o portal: <a href="${PORTAL}${path}">${PORTAL.replace('https://', '')}${path}</a>.</p><p>— Equipe Listeny</p>`;
}

function renderTemplate(
  event: string,
  firstName: string,
  data: Record<string, unknown> | undefined,
): { subject: string; html: string } | null {
  switch (event) {
    case 'payout_paid': {
      const amount = Number(data?.amount ?? 0);
      return {
        subject: 'Seu pagamento foi realizado — Listeny Afiliados',
        html: `<p>Olá, ${firstName}!</p>
          <p>Confirmamos o pagamento da sua comissão no valor de <strong>${brl(amount)}</strong>.</p>
          ${footer('/financeiro')}`,
      };
    }
    case 'affiliate_approved':
      return {
        subject: 'Seu cadastro foi aprovado — Listeny Afiliados',
        html: `<p>Olá, ${firstName}!</p>
          <p>Seu cadastro no Programa de Afiliados Listeny foi <strong>aprovado</strong>.</p>
          <p>Próximo passo: conclua a <strong>verificação de identidade (KYC)</strong> em
             "Meu cadastro" para liberar o seu cupom.</p>
          ${footer('/perfil')}`,
      };
    case 'kyc_verified':
      return {
        subject: 'Identidade verificada — seu cupom está ativo! — Listeny Afiliados',
        html: `<p>Olá, ${firstName}!</p>
          <p>Sua identidade foi verificada e o seu <strong>cupom está ativo</strong>.</p>
          ${footer('')}`,
      };
    case 'affiliate_revision':
      return {
        subject: 'Precisamos de um ajuste no seu cadastro — Listeny Afiliados',
        html: `<p>Olá, ${firstName}!</p>
          <p>Revisamos seu cadastro e precisamos de um ajuste antes de aprovar.</p>
          ${reasonBlock(data)}
          <p>Entre no portal, corrija o que foi apontado e reenvie.</p>
          ${footer('')}`,
      };
    case 'kyc_rejected':
      return {
        subject: 'Sobre sua verificação de identidade — Listeny Afiliados',
        html: `<p>Olá, ${firstName}!</p>
          <p>Seus documentos de verificação de identidade não foram aprovados.</p>
          ${reasonBlock(data)}
          <p>Reenvie os documentos em "Meu cadastro".</p>
          ${footer('/perfil')}`,
      };
    case 'invoice_rejected':
      return {
        subject: 'Sobre sua nota fiscal — Listeny Afiliados',
        html: `<p>Olá, ${firstName}!</p>
          <p>A nota fiscal que você enviou foi recusada.</p>
          ${reasonBlock(data)}
          <p>Envie uma nova nota em "Financeiro".</p>
          ${footer('/financeiro')}`,
      };
    case 'affiliate_rejected':
      return {
        subject: 'Sobre seu cadastro no Programa de Afiliados — Listeny',
        html: `<p>Olá, ${firstName}!</p>
          <p>Infelizmente seu cadastro no Programa de Afiliados não foi aprovado no momento.</p>
          ${reasonBlock(data)}
          <p>Se tiver dúvidas, fale com o suporte pelo portal.</p>
          ${footer('')}`,
      };
    default:
      return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const secret = Deno.env.get('NOTIFY_SECRET');
  if (!secret || req.headers.get('x-notify-secret') !== secret) {
    return json({ error: 'unauthorized' }, 401);
  }

  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!resendKey) return json({ error: 'RESEND_API_KEY não configurada' }, 500);

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return json({ error: 'invalid json' }, 400);
  }
  const { affiliate_id, event, ref, data } = payload;
  if (!affiliate_id || !event) {
    return json({ error: 'affiliate_id e event são obrigatórios' }, 400);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  // Idempotência: mesmo evento+ref já enviado → não reenvia.
  if (ref) {
    const { data: existing } = await supabase
      .from('affiliate_notifications')
      .select('id')
      .eq('event', event)
      .eq('ref', ref)
      .eq('status', 'sent')
      .maybeSingle();
    if (existing) return json({ ok: true, skipped: 'already_sent' });
  }

  const { data: aff } = await supabase
    .from('affiliates')
    .select('email, resp_nome')
    .eq('id', affiliate_id)
    .maybeSingle();
  if (!aff?.email) return json({ error: 'afiliado sem e-mail' }, 404);

  const firstName = String(aff.resp_nome ?? '').trim().split(/\s+/)[0] || 'afiliado';
  const tpl = renderTemplate(event, firstName, data);
  if (!tpl) return json({ error: `evento desconhecido: ${event}` }, 400);

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from: FROM, to: aff.email, subject: tpl.subject, html: tpl.html }),
  });
  const ok = res.ok;
  const errText = ok ? null : await res.text();

  await supabase.from('affiliate_notifications').insert({
    affiliate_id,
    event,
    recipient: aff.email,
    ref: ref ?? null,
    status: ok ? 'sent' : 'failed',
    error: errText,
  });

  if (!ok) return json({ error: 'falha ao enviar', detail: errText }, 502);
  return json({ ok: true });
});
