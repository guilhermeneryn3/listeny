-- Listeny — 0021 — módulo Eventos: calendário institucional (excursão, reunião de pais, evento,
-- feriado, aviso). SEPARADO da agenda de sessões (privada). Visibilidade por evento:
-- public → pais/alunos/site (leitura por qualquer um, inclusive anon); internal → só equipe.
-- Datas em date/time (sem tz) — o calendário agrupa por event_date.

create table if not exists public.events (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.orgs (id) on delete cascade,
  title       text not null,
  type        text not null default 'evento'
                check (type in ('excursao','reuniao','evento','feriado','aviso')),
  event_date  date not null,
  start_time  time,
  end_date    date,
  location    text,
  description text,
  visibility  text not null default 'public' check (visibility in ('public','internal')),
  created_by  uuid references auth.users (id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists events_org_idx  on public.events (org_id);
create index if not exists events_date_idx on public.events (org_id, event_date);

drop trigger if exists events_set_updated_at on public.events;
create trigger events_set_updated_at
  before update on public.events
  for each row execute function public.set_updated_at();

alter table public.events enable row level security;

-- público: qualquer um lê eventos public (site público, pais, alunos)
drop policy if exists events_public_read on public.events;
create policy events_public_read on public.events
  for select using (visibility = 'public');

-- equipe gerencia (e lê os internos)
drop policy if exists events_manage on public.events;
create policy events_manage on public.events
  for all using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));
