-- Educaty — 0007 — campanhas, códigos promocionais e trilha de atribuição (marketing).
-- Motor único: cupom de trial (marketing próprio) + cupom de afiliado alimentam a atribuição
-- first-touch (colunas já em profiles, 0001). Gerência pelo painel N3; resgate pela edge
-- function `redeem-code` (service-role). App/portal não tocam direto. Trancado a service-role.

create table if not exists public.campaigns (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  channel    text not null default 'marketing',
  active     boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.promo_codes (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,               -- sempre MAIÚSCULO
  campaign_id uuid references public.campaigns (id) on delete set null,
  kind        text not null default 'trial' check (kind in ('trial')),
  trial_days  integer not null default 14,
  max_uses    integer,
  uses        integer not null default 0,
  valid_until timestamptz,
  active      boolean not null default true,
  created_by  uuid,
  created_at  timestamptz not null default now()
);
create index if not exists promo_codes_campaign_idx on public.promo_codes (campaign_id);

-- Resgates de trial: atribuição + anti-abuso (1 por usuário, índice por aparelho).
create table if not exists public.trial_redemptions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null,
  device_id    text,
  source_kind  text not null check (source_kind in ('promo','affiliate')),
  code         text,
  campaign_id  uuid references public.campaigns (id) on delete set null,
  affiliate_id uuid,
  granted_days integer not null,
  redeemed_at  timestamptz not null default now(),
  unique (user_id)
);
create index if not exists trial_redemptions_device_idx on public.trial_redemptions (device_id);

-- Trancadas: só service-role (painel N3 e edge function) acessa (sem policy = negado).
alter table public.campaigns         enable row level security;
alter table public.promo_codes       enable row level security;
alter table public.trial_redemptions enable row level security;
