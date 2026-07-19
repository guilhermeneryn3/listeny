-- Listeny — bootstrap: TODAS as migrations 0001..0010 em ordem.
-- Rode UMA VEZ no SQL Editor do projeto Supabase (cole tudo e Run).


-- ============================================================
-- 0001_identidade.sql
-- ============================================================
-- Listeny — 0001 — identidade do usuário (perfil global, cross-tenant).
-- Um auth.users pode pertencer a vários orgs (tenants) com papéis diferentes (ver 0002).
-- Este profile é a identidade da PESSOA, não do vínculo com um tenant.
-- RLS por user_id = auth.uid(). i18n desde a base: locale default 'pt-BR'.
-- tier/is_premium só o servidor escreve (guard em 0001 — espelha o padrão VamAI 0060).

create table if not exists public.profiles (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  first_name    text not null default '',
  last_name     text not null default '',
  email         text,
  phone         text,
  locale        text not null default 'pt-BR',
  onboarded     boolean not null default false,
  is_premium    boolean not null default false,
  tier          text not null default 'free',
  premium_since timestamptz,
  -- atribuição first-touch (marketing/afiliado) — preenchida uma única vez (ver 0007)
  acquisition_channel      text,
  acquisition_source       text,
  acquisition_affiliate_id uuid,
  acquisition_at           timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select using (auth.uid() = user_id);

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert with check (auth.uid() = user_id);

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- updated_at automático em cada UPDATE (função compartilhada por todo o schema)
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Cria a linha de profile automaticamente quando um usuário nasce no auth.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id, email)
  values (new.id, new.email)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Tranca os campos de premium: só service-role (concessão do painel N3, revenuecat-sync)
-- escreve tier/is_premium/premium_since. Usuário final segue editando nome/telefone/locale.
create or replace function public.guard_profile_premium()
returns trigger language plpgsql as $$
begin
  -- Bloqueia SÓ usuário final (authenticated/anon). service-role/migrations passam livres.
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.tier := 'free';
    new.is_premium := false;
    new.premium_since := null;
    return new;
  end if;

  if new.tier is distinct from old.tier
     or new.is_premium is distinct from old.is_premium
     or new.premium_since is distinct from old.premium_since then
    raise exception 'premium é definido apenas pelo servidor';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_guard_premium on public.profiles;
create trigger profiles_guard_premium
  before insert or update on public.profiles
  for each row execute function public.guard_profile_premium();

-- ============================================================
-- 0002_tenancy.sql
-- ============================================================
-- Listeny — 0002 — multi-tenant: orgs (tenants) + memberships.
-- Um `org` é a MARCA do professor/criador (workspace white-label): tem slug (subdomínio
-- <slug>.listeny.app), tier de assinatura e membros. Um auth.users pode ser owner de um org
-- e student de outro. O tier do org é a assinatura SaaS-branca (só o servidor escreve).
--
-- RLS sem recursão: as políticas usam helpers SECURITY DEFINER (is_org_member/is_org_owner)
-- que ignoram RLS, evitando o laço clássico orgs<->memberships.

create table if not exists public.orgs (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references auth.users (id) on delete restrict,
  name       text not null,
  slug       text not null unique,           -- subdomínio do tenant; minúsculo (ver 0004 p/ domínio custom)
  tier       text not null default 'free',   -- assinatura SaaS do tenant (server-only)
  status     text not null default 'active'
               check (status in ('active','suspended','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists orgs_owner_idx on public.orgs (owner_id);

do $$ begin
  create type public.membership_role as enum ('teacher','student','staff');
exception when duplicate_object then null; end $$;

create table if not exists public.memberships (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.orgs (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  role       public.membership_role not null default 'student',
  created_at timestamptz not null default now(),
  unique (org_id, user_id)
);
create index if not exists memberships_user_idx on public.memberships (user_id);
create index if not exists memberships_org_idx  on public.memberships (org_id);

-- ── Helpers (SECURITY DEFINER → ignoram RLS; quebram a recursão) ─────────────
create or replace function public.is_org_member(p_org uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.memberships m
    where m.org_id = p_org and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_org_owner(p_org uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.orgs o
    where o.id = p_org and o.owner_id = auth.uid()
  );
$$;

-- updated_at
drop trigger if exists orgs_set_updated_at on public.orgs;
create trigger orgs_set_updated_at
  before update on public.orgs
  for each row execute function public.set_updated_at();

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.orgs        enable row level security;
alter table public.memberships enable row level security;

-- orgs: membro (ou owner) lê; qualquer autenticado cria o próprio org (vira owner);
-- só o owner edita nome/slug. tier/status ficam pro servidor (guard abaixo).
drop policy if exists orgs_select on public.orgs;
create policy orgs_select on public.orgs
  for select using (owner_id = auth.uid() or public.is_org_member(id));

drop policy if exists orgs_insert on public.orgs;
create policy orgs_insert on public.orgs
  for insert with check (owner_id = auth.uid());

drop policy if exists orgs_update on public.orgs;
create policy orgs_update on public.orgs
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- memberships: o usuário vê o próprio vínculo; o owner do org vê/gerencia todos.
drop policy if exists memberships_select on public.memberships;
create policy memberships_select on public.memberships
  for select using (user_id = auth.uid() or public.is_org_owner(org_id));

drop policy if exists memberships_insert on public.memberships;
create policy memberships_insert on public.memberships
  for insert with check (public.is_org_owner(org_id));

drop policy if exists memberships_update on public.memberships;
create policy memberships_update on public.memberships
  for update using (public.is_org_owner(org_id)) with check (public.is_org_owner(org_id));

drop policy if exists memberships_delete on public.memberships;
create policy memberships_delete on public.memberships
  for delete using (public.is_org_owner(org_id));

-- ── Guarda: tier/status do org só o servidor (painel N3 / revenuecat-sync) muda ──
create or replace function public.guard_org_billing()
returns trigger language plpgsql as $$
begin
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.tier := 'free';
    new.status := 'active';
    return new;
  end if;
  if new.tier is distinct from old.tier or new.status is distinct from old.status then
    raise exception 'tier/status do org são definidos apenas pelo servidor';
  end if;
  return new;
end;
$$;

drop trigger if exists orgs_guard_billing on public.orgs;
create trigger orgs_guard_billing
  before insert or update on public.orgs
  for each row execute function public.guard_org_billing();

-- ============================================================
-- 0003_branding.sql
-- ============================================================
-- Listeny — 0003 — branding white-label: a "cara" do tenant é DADO, não código.
-- theme_templates = catálogo de aparências (tokens). org_branding = escolha do tenant
-- (template + logo + overrides de paleta + css opcional). Portal (CSS vars) e app (theme
-- tokens) consomem o MESMO contrato de tokens abaixo — nunca hardcode de cor na UI.
--
-- Contrato de tokens (jsonb) — chaves fixas, valores hex/px:
--   { primary, primaryDark, bg, surface, ink, sub, hint, edge, soft,
--     success, warn, danger, tint, radius, font }
-- palette (org_branding) = overrides parciais aplicados por cima do template escolhido.

create table if not exists public.theme_templates (
  id         uuid primary key default gen_random_uuid(),
  key        text not null unique,
  name       text not null,
  tokens     jsonb not null,
  is_public  boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.org_branding (
  org_id            uuid primary key references public.orgs (id) on delete cascade,
  theme_template_id uuid references public.theme_templates (id),
  logo_url          text,
  palette           jsonb not null default '{}'::jsonb,   -- overrides parciais
  custom_css        text,
  updated_at        timestamptz not null default now()
);

drop trigger if exists org_branding_set_updated_at on public.org_branding;
create trigger org_branding_set_updated_at
  before update on public.org_branding
  for each row execute function public.set_updated_at();

-- ── RLS ──────────────────────────────────────────────────────────────────────
-- Branding é PÚBLICO (o portal do tenant é aberto a visitantes/alunos → precisa ler a cara
-- sem sessão). Só o owner do org grava. Templates públicos, escrita só service-role.
alter table public.theme_templates enable row level security;
alter table public.org_branding    enable row level security;

drop policy if exists theme_templates_select on public.theme_templates;
create policy theme_templates_select on public.theme_templates
  for select using (is_public);

drop policy if exists org_branding_select on public.org_branding;
create policy org_branding_select on public.org_branding
  for select using (true);

drop policy if exists org_branding_insert on public.org_branding;
create policy org_branding_insert on public.org_branding
  for insert with check (public.is_org_owner(org_id));

drop policy if exists org_branding_update on public.org_branding;
create policy org_branding_update on public.org_branding
  for update using (public.is_org_owner(org_id)) with check (public.is_org_owner(org_id));

-- ── Template default: tema claro, primário teal/verde (do mockup) ────────────
insert into public.theme_templates (key, name, tokens, is_public)
values (
  'teal-clean',
  'Teal Clean (padrão)',
  jsonb_build_object(
    'primary',     '#14B8A6',
    'primaryDark', '#0D9488',
    'bg',          '#F7F8FA',
    'surface',     '#FFFFFF',
    'ink',         '#17181D',
    'sub',         '#5A6172',
    'hint',        '#9AA0AB',
    'edge',        '#ECECF2',
    'soft',        '#F1F3F7',
    'success',     '#16A34A',
    'warn',        '#B45309',
    'danger',      '#F0473C',
    'tint',        '#ECFDF9',
    'radius',      '16px',
    'font',        'Plus Jakarta Sans'
  ),
  true
)
on conflict (key) do nothing;

-- ============================================================
-- 0004_dominios.sql
-- ============================================================
-- Listeny — 0004 — domínios do tenant.
-- Todo org tem o subdomínio <slug>.listeny.app (resolvido por orgs.slug, já público).
-- Aqui ficam os domínios PRÓPRIOS (escola-do-joao.com). A resolução hostname→org roda no
-- portal (server). O attach/verificação/SSL real (Vercel API) é fase seguinte; aqui fica o
-- modelo. Mapeamento não é segredo → leitura pública; verificação só o servidor faz.

create table if not exists public.org_domains (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references public.orgs (id) on delete cascade,
  hostname           text not null unique,        -- minúsculo, sem protocolo
  is_primary         boolean not null default false,
  status             text not null default 'pending'
                       check (status in ('pending','active','failed')),
  verification_token text,
  ssl_status         text not null default 'none'
                       check (ssl_status in ('none','pending','active','failed')),
  created_at         timestamptz not null default now()
);
create index if not exists org_domains_org_idx on public.org_domains (org_id);

alter table public.org_domains enable row level security;

drop policy if exists org_domains_select on public.org_domains;
create policy org_domains_select on public.org_domains
  for select using (true);

-- o owner adiciona o próprio domínio; nasce 'pending', sem SSL, não-primário.
-- (verificação/ativação/SSL/primário são prerrogativa do servidor.)
drop policy if exists org_domains_insert on public.org_domains;
create policy org_domains_insert on public.org_domains
  for insert with check (
    public.is_org_owner(org_id)
    and status = 'pending'
    and is_primary = false
    and ssl_status = 'none'
  );

drop policy if exists org_domains_delete on public.org_domains;
create policy org_domains_delete on public.org_domains
  for delete using (public.is_org_owner(org_id));
-- sem policy de UPDATE → só service-role (portal/servidor) verifica e ativa.

-- ============================================================
-- 0005_afiliados.sql
-- ============================================================
-- Listeny — 0005 — programa de afiliados DA PLATAFORMA (afiliado indica o professor pagante).
-- Modelo VamAI: afiliado se cadastra logado com a conta, escolhe o próprio cupom (o "CPF"
-- dele: único, fixo, intransferível). RLS: o dono gerencia o que é seu; o painel N3
-- (service-role, auth.uid() nulo) aprova/verifica. Comissão fica na 0006.
-- (Afiliados DO TENANT, no futuro marketplace, são outra camada — não é isto.)

create table if not exists public.affiliates (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null unique references auth.users (id) on delete cascade,
  status             text not null default 'pending'
                       check (status in ('pending','approved','rejected','suspended','archived')),
  -- pessoa/PJ
  person_type        text not null default 'pj' check (person_type in ('pj','pf')),
  cnpj               text unique,
  razao_social       text,
  nome_fantasia      text,
  resp_nome          text not null,
  resp_cpf           text not null,
  resp_nascimento    date,
  -- contato / endereço
  email              text not null,
  telefone           text not null,
  endereco           jsonb not null default '{}'::jsonb,
  -- programa (só o N3 escreve)
  coupon_code        text unique,
  signup_rate_override     numeric(5,4),
  recurrence_rate_override numeric(5,4),
  rejection_reason   text,
  reviewed_by        uuid,
  reviewed_at        timestamptz,
  premium_granted_at timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table if not exists public.affiliate_socials (
  id           uuid primary key default gen_random_uuid(),
  affiliate_id uuid not null references public.affiliates (id) on delete cascade,
  platform     text not null
                 check (platform in ('instagram','youtube','tiktok','facebook','kwai','x','outros')),
  handle       text not null,
  followers    integer,
  created_at   timestamptz not null default now()
);
create index if not exists affiliate_socials_affiliate_idx on public.affiliate_socials (affiliate_id);

create table if not exists public.affiliate_terms (
  id           uuid primary key default gen_random_uuid(),
  affiliate_id uuid not null references public.affiliates (id) on delete cascade,
  version      text not null,
  accepted_at  timestamptz not null default now(),
  ip           text
);
create index if not exists affiliate_terms_affiliate_idx on public.affiliate_terms (affiliate_id);

create table if not exists public.affiliate_banks (
  id           uuid primary key default gen_random_uuid(),
  affiliate_id uuid not null references public.affiliates (id) on delete cascade,
  kind         text not null check (kind in ('pix','conta')),
  pix_key_type text check (pix_key_type in ('cnpj','cpf','email','telefone','aleatoria')),
  pix_key      text,
  banco        text,
  agencia      text,
  conta        text,
  verified     boolean not null default false,
  is_default   boolean not null default false,
  created_at   timestamptz not null default now()
);
create index if not exists affiliate_banks_affiliate_idx on public.affiliate_banks (affiliate_id);

drop trigger if exists affiliates_set_updated_at on public.affiliates;
create trigger affiliates_set_updated_at
  before update on public.affiliates
  for each row execute function public.set_updated_at();

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.affiliates       enable row level security;
alter table public.affiliate_socials enable row level security;
alter table public.affiliate_terms   enable row level security;
alter table public.affiliate_banks   enable row level security;

-- affiliates: o dono lê/cria/edita a própria linha. Na criação só nasce 'pending', pode
-- escolher o coupon_code, e sem campos de programa (isso é prerrogativa do N3).
drop policy if exists affiliates_select on public.affiliates;
create policy affiliates_select on public.affiliates
  for select using (auth.uid() = user_id);

drop policy if exists affiliates_insert on public.affiliates;
create policy affiliates_insert on public.affiliates
  for insert with check (
    auth.uid() = user_id
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and premium_granted_at is null
    and signup_rate_override is null
    and recurrence_rate_override is null
  );

drop policy if exists affiliates_update on public.affiliates;
create policy affiliates_update on public.affiliates
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists affiliate_socials_all on public.affiliate_socials;
create policy affiliate_socials_all on public.affiliate_socials
  for all using (exists (select 1 from public.affiliates a
                         where a.id = affiliate_id and a.user_id = auth.uid()))
  with check (exists (select 1 from public.affiliates a
                      where a.id = affiliate_id and a.user_id = auth.uid()));

drop policy if exists affiliate_terms_select on public.affiliate_terms;
create policy affiliate_terms_select on public.affiliate_terms
  for select using (exists (select 1 from public.affiliates a
                            where a.id = affiliate_id and a.user_id = auth.uid()));
drop policy if exists affiliate_terms_insert on public.affiliate_terms;
create policy affiliate_terms_insert on public.affiliate_terms
  for insert with check (exists (select 1 from public.affiliates a
                                 where a.id = affiliate_id and a.user_id = auth.uid()));

drop policy if exists affiliate_banks_all on public.affiliate_banks;
create policy affiliate_banks_all on public.affiliate_banks
  for all using (exists (select 1 from public.affiliates a
                         where a.id = affiliate_id and a.user_id = auth.uid()))
  with check (exists (select 1 from public.affiliates a
                      where a.id = affiliate_id and a.user_id = auth.uid()));

-- ── Guardas: o afiliado não altera aprovação/comissão; verificação de conta é do N3 ──
create or replace function public.affiliates_guard()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null and (
       new.status                   is distinct from old.status or
       new.coupon_code              is distinct from old.coupon_code or
       new.reviewed_by              is distinct from old.reviewed_by or
       new.reviewed_at              is distinct from old.reviewed_at or
       new.premium_granted_at       is distinct from old.premium_granted_at or
       new.signup_rate_override     is distinct from old.signup_rate_override or
       new.recurrence_rate_override is distinct from old.recurrence_rate_override
     ) then
    raise exception 'Campos de aprovação/comissão só podem ser alterados pelo painel.';
  end if;
  return new;
end;
$$;
drop trigger if exists affiliates_guard on public.affiliates;
create trigger affiliates_guard before update on public.affiliates
  for each row execute function public.affiliates_guard();

create or replace function public.affiliate_banks_guard()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null and new.verified then
    raise exception 'A verificação da conta é feita pelo painel.';
  end if;
  return new;
end;
$$;
drop trigger if exists affiliate_banks_guard on public.affiliate_banks;
create trigger affiliate_banks_guard before insert or update on public.affiliate_banks
  for each row execute function public.affiliate_banks_guard();

-- Disponibilidade do cupom sem expor dados de outros (SECURITY DEFINER → só booleano).
create or replace function public.affiliate_coupon_available(code text)
returns boolean language sql security definer set search_path = public as $$
  select not exists (select 1 from public.affiliates where coupon_code = upper(code));
$$;
revoke all on function public.affiliate_coupon_available(text) from public;
grant execute on function public.affiliate_coupon_available(text) to authenticated;

-- ============================================================
-- 0006_afiliados_comissao.sql
-- ============================================================
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

-- ============================================================
-- 0007_campanhas_codigos.sql
-- ============================================================
-- Listeny — 0007 — campanhas, códigos promocionais e trilha de atribuição (marketing).
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

-- ============================================================
-- 0008_conectores.sql
-- ============================================================
-- Listeny — 0008 — camada de conectores ("encaixe universal" / socket-and-plug).
-- Toda integração externa entra por AQUI, por tenant — nunca código de um provedor específico
-- espalhado no núcleo. É onde a AULA AO VIVO (live_video), o pagamento do MARKETPLACE futuro
-- (payment), storage/calendar plugam. `config` é público (não-segredo); credenciais ficam em
-- `connector_credentials`, opaco e SÓ service-role (as edge functions leem; nunca o client).
--
-- Espelha o adapter pattern de vamai-web/src/lib/payments/* (interface + swap por provedor),
-- mas dirigido por dado, por tenant. Fase 0: só o contrato — nenhum conector real ligado.

do $$ begin
  create type public.connector_kind as enum ('live_video','payment','storage','calendar','other');
exception when duplicate_object then null; end $$;

create table if not exists public.connectors (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.orgs (id) on delete cascade,
  key        text not null,                       -- ex.: 'livekit', 'daily', 'asaas'
  kind       public.connector_kind not null,
  enabled    boolean not null default false,
  config     jsonb not null default '{}'::jsonb,  -- não-segredo (ids públicos, opções)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, kind, key)
);
create index if not exists connectors_org_idx on public.connectors (org_id);

-- Credenciais do conector: opaco, escrito/lido só por service-role (edge functions).
create table if not exists public.connector_credentials (
  connector_id uuid primary key references public.connectors (id) on delete cascade,
  secret       jsonb not null default '{}'::jsonb,
  updated_at   timestamptz not null default now()
);

drop trigger if exists connectors_set_updated_at on public.connectors;
create trigger connectors_set_updated_at
  before update on public.connectors
  for each row execute function public.set_updated_at();

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.connectors            enable row level security;
alter table public.connector_credentials enable row level security;

-- connectors (metadados, sem segredo): o owner do org gerencia; membros leem.
drop policy if exists connectors_select on public.connectors;
create policy connectors_select on public.connectors
  for select using (public.is_org_member(org_id) or public.is_org_owner(org_id));

drop policy if exists connectors_write on public.connectors;
create policy connectors_write on public.connectors
  for all using (public.is_org_owner(org_id)) with check (public.is_org_owner(org_id));

-- connector_credentials: sem policy nenhuma → só service-role (edge functions) toca.

-- ============================================================
-- 0009_billing_seam.sql
-- ============================================================
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

-- ============================================================
-- 0010_rpc_admin.sql
-- ============================================================
-- Listeny — 0010 — RPCs administrativas que o painel N3 chama (service-role).
-- force_delete_affiliate: apaga afiliado À FORÇA (limpeza de teste). Só o OWNER dispara na UI
-- do N3. Respeita a ordem dos FKs `on delete restrict`. Afiliado real que já operou deve ser
-- ARQUIVADO (status='archived'), não apagado.

create or replace function public.force_delete_affiliate(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from commission_events where affiliate_id = p_id;
  delete from payouts          where affiliate_id = p_id;
  delete from invoices         where affiliate_id = p_id;
  delete from referrals        where affiliate_id = p_id;
  -- cascateiam sozinhos: affiliate_socials/terms/banks/notifications.
  delete from affiliates       where id = p_id;
end;
$$;

revoke all on function public.force_delete_affiliate(uuid) from public;
revoke all on function public.force_delete_affiliate(uuid) from anon;
revoke all on function public.force_delete_affiliate(uuid) from authenticated;
