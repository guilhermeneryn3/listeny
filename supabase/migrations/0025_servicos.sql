-- Listeny — 0025 — Serviços: catálogo operacional (preço + duração) que a AGENDA usa.
-- Base da vertical Beleza (e de qualquer negócio por atendimento): agenda, e mais à frente
-- comissão e comanda, penduram no serviço. Por org, RLS. Separado de `site_offerings` (que é
-- vitrine de marketing do módulo Site) — aqui é o catálogo OPERACIONAL do que se agenda/cobra.

create table if not exists public.services (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.orgs (id) on delete cascade,
  name         text not null,
  description  text,
  price        numeric(10,2),                 -- preço de tabela (opcional)
  duration_min integer not null default 30 check (duration_min > 0),
  category     text,                          -- agrupador livre (ex.: Cabelo, Unhas, Estética)
  active       boolean not null default true,
  sort         integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists services_org_idx on public.services (org_id);

drop trigger if exists services_set_updated_at on public.services;
create trigger services_set_updated_at
  before update on public.services
  for each row execute function public.set_updated_at();

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.services enable row level security;

-- gestor do org administra
drop policy if exists services_manage on public.services;
create policy services_manage on public.services
  for all using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));

-- membro/aluno com conta lê os serviços ATIVOS (base p/ escolher no agendamento)
drop policy if exists services_read_active on public.services;
create policy services_read_active on public.services
  for select using (active and (public.is_org_member(org_id) or public.is_org_owner(org_id)));

-- ── Agenda referencia o serviço (opcional) ───────────────────────────────────
-- pré-preenche título/duração ao marcar; base da comissão e da comanda futuras.
alter table public.sessions
  add column if not exists service_id uuid references public.services (id) on delete set null;
