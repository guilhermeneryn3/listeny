-- Listeny — 0009 — seam de faturamento: prevê OS DOIS modelos no schema desde já.
--
-- (A) ATIVO — assinatura SaaS-branca: o professor/org assina o Listeny. `orders` registra a
--     cobrança da assinatura do org (espelha vamai-web orders); a entitlement/tier do org é
--     concedida por revenuecat-sync (service-role). Afiliado ganha sobre ISTO (0006).
--
-- (B) INERTE — marketplace (venda-ao-aluno): quando ligado numa fase futura, o org VENDE ao
--     aluno e o Listeny RETÉM `platform_fee`. As tabelas existem como CONTRATO, com RLS
--     travada e sem fluxo — nada as escreve ainda. Ligar o marketplace = próxima fase
--     (split de pagamento, payout e fiscal por tenant, KYC do criador).

-- (A) Assinatura do org (SaaS) ────────────────────────────────────────────────
create table if not exists public.orders (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid references public.orgs (id) on delete set null,
  buyer_id      uuid references auth.users (id),
  kind          text not null default 'subscription' check (kind in ('subscription')),
  plan          text,                               -- ex.: 'pro_monthly'
  coupon_code   text,
  affiliate_id  uuid references public.affiliates (id),
  gross         numeric(10,2) not null default 0,
  discount      numeric(10,2) not null default 0,
  currency      text not null default 'BRL',        -- i18n-ready: moeda parametrizável
  status        text not null default 'pending'
                  check (status in ('pending','paid','failed','refunded')),
  external_id   text unique,
  paid_at       timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists orders_org_idx on public.orders (org_id);

alter table public.orders enable row level security;
-- o comprador/owner lê o próprio pedido; escrita só pelo rail (service-role).
drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders
  for select using (buyer_id = auth.uid() or public.is_org_owner(org_id));

-- (B) Marketplace — CONTRATO INERTE (sem policy → só service-role; nada liga isto ainda) ──
create table if not exists public.tenant_sales (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references public.orgs (id) on delete restrict,
  student_id    uuid references auth.users (id),
  item_ref      text,                               -- curso/mensalidade (definido na fase marketplace)
  gross         numeric(10,2) not null,
  platform_fee  numeric(10,2) not null default 0,   -- taxa retida pelo Listeny
  net_to_tenant numeric(10,2) not null default 0,
  currency      text not null default 'BRL',
  status        text not null default 'pending'
                  check (status in ('pending','paid','refunded')),
  external_id   text unique,
  created_at    timestamptz not null default now()
);
create index if not exists tenant_sales_org_idx on public.tenant_sales (org_id);
alter table public.tenant_sales enable row level security;
-- sem policy: inerte até a fase do marketplace.
