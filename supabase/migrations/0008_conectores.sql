-- Educaty — 0008 — camada de conectores ("encaixe universal" / socket-and-plug).
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
