-- Listeny — 0006 — comissão de afiliado: config, atribuição, eventos, NF, pagamento, avisos.
-- Taxas = DADO editável no painel (affiliate_settings global + affiliates.*_override por
-- afiliado). Taxa efetiva = coalesce(override, global), resolvida pelo rail e CONGELADA no
-- evento. Eventos criados por service-role; o afiliado só LÊ. Modelo inicial (VamAI): entrada
-- por trial + 10% sobre pagamentos do indicado por 6 meses; holdback 21 dias.

create table if not exists public.affiliate_settings (
  id                boolean primary key default true check (id),
  signup_rate       numeric(5,4) not null default 0,      -- 1ª cobrança (0 = sem comissão de entrada)
  recurrence_rate   numeric(5,4) not null default 0.10,   -- recorrência
  recurrence_months integer not null default 6,           -- janela da recorrência
  holdback_days     integer not null default 21,
  updated_at        timestamptz not null default now()
);
insert into public.affiliate_settings (id) values (true) on conflict (id) do nothing;

drop trigger if exists affiliate_settings_set_updated_at on public.affiliate_settings;
create trigger affiliate_settings_set_updated_at
  before update on public.affiliate_settings
  for each row execute function public.set_updated_at();

-- Atribuição assinatura↔afiliado (via cupom). first_paid_at ancora a janela de recorrência.
create table if not exists public.referrals (
  id              uuid primary key default gen_random_uuid(),
  affiliate_id    uuid not null references public.affiliates (id) on delete restrict,
  coupon_code     text not null,
  subscriber_id   uuid references auth.users (id),
  external_sub_id text,
  first_paid_at   timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists referrals_affiliate_idx on public.referrals (affiliate_id);

-- Evento de comissão: 1 por cobrança paga. idempotente por external_event_id.
create table if not exists public.commission_events (
  id                uuid primary key default gen_random_uuid(),
  affiliate_id      uuid not null references public.affiliates (id) on delete restrict,
  referral_id       uuid references public.referrals (id) on delete set null,
  type              text not null check (type in ('signup','recurrence','clawback')),
  external_event_id text unique,
  external_txn_id   text,
  gross             numeric(10,2) not null,
  fees              numeric(10,2) not null default 0,
  net_base          numeric(10,2) not null,
  rate              numeric(5,4)  not null,
  amount            numeric(10,2) not null,
  status            text not null default 'pending'
                      check (status in ('pending','eligible','paid','reversed')),
  eligible_at       timestamptz,
  payout_id         uuid,
  created_at        timestamptz not null default now()
);
create index if not exists commission_events_affiliate_idx on public.commission_events (affiliate_id);
create index if not exists commission_events_status_idx    on public.commission_events (status);

create table if not exists public.invoices (
  id               uuid primary key default gen_random_uuid(),
  affiliate_id     uuid not null references public.affiliates (id) on delete restrict,
  period           text not null,
  amount           numeric(10,2) not null,
  file_path        text not null,
  nf_key           text,
  status           text not null default 'submitted'
                     check (status in ('submitted','valid','rejected')),
  rejection_reason text,
  created_at       timestamptz not null default now()
);
create index if not exists invoices_affiliate_idx on public.invoices (affiliate_id);

create table if not exists public.payouts (
  id           uuid primary key default gen_random_uuid(),
  affiliate_id uuid not null references public.affiliates (id) on delete restrict,
  bank_id      uuid references public.affiliate_banks (id),
  invoice_id   uuid references public.invoices (id),
  amount       numeric(10,2) not null,
  status       text not null default 'open'
                 check (status in ('open','awaiting_nf','approved','paid')),
  external_transfer_id text,
  paid_at      timestamptz,
  created_at   timestamptz not null default now()
);
create index if not exists payouts_affiliate_idx on public.payouts (affiliate_id);

-- Avisos transacionais ao afiliado (logados pela edge function notify-affiliate).
-- Formato alinhado à função: event + destinatário + ref (idempotência) + status/erro.
create table if not exists public.affiliate_notifications (
  id           uuid primary key default gen_random_uuid(),
  affiliate_id uuid not null references public.affiliates (id) on delete cascade,
  event        text not null,
  recipient    text,
  ref          text,                               -- chave de idempotência (não reenvia mesmo event+ref)
  status       text not null default 'sent' check (status in ('sent','failed')),
  error        text,
  created_at   timestamptz not null default now()
);
create index if not exists affiliate_notifications_ref_idx
  on public.affiliate_notifications (event, ref);
create index if not exists affiliate_notifications_affiliate_idx on public.affiliate_notifications (affiliate_id);

-- ── RLS: afiliado só LÊ o que é dele; settings só service-role ────────────────
alter table public.affiliate_settings      enable row level security;
alter table public.referrals               enable row level security;
alter table public.commission_events       enable row level security;
alter table public.invoices                enable row level security;
alter table public.payouts                 enable row level security;
alter table public.affiliate_notifications enable row level security;

drop policy if exists referrals_select on public.referrals;
create policy referrals_select on public.referrals
  for select using (exists (select 1 from public.affiliates a
                            where a.id = affiliate_id and a.user_id = auth.uid()));

drop policy if exists commission_events_select on public.commission_events;
create policy commission_events_select on public.commission_events
  for select using (exists (select 1 from public.affiliates a
                            where a.id = affiliate_id and a.user_id = auth.uid()));

drop policy if exists payouts_select on public.payouts;
create policy payouts_select on public.payouts
  for select using (exists (select 1 from public.affiliates a
                            where a.id = affiliate_id and a.user_id = auth.uid()));

drop policy if exists affiliate_notifications_select on public.affiliate_notifications;
create policy affiliate_notifications_select on public.affiliate_notifications
  for select using (exists (select 1 from public.affiliates a
                            where a.id = affiliate_id and a.user_id = auth.uid()));

drop policy if exists invoices_select on public.invoices;
create policy invoices_select on public.invoices
  for select using (exists (select 1 from public.affiliates a
                            where a.id = affiliate_id and a.user_id = auth.uid()));
drop policy if exists invoices_insert on public.invoices;
create policy invoices_insert on public.invoices
  for insert with check (
    status = 'submitted'
    and exists (select 1 from public.affiliates a
                where a.id = affiliate_id and a.user_id = auth.uid())
  );
