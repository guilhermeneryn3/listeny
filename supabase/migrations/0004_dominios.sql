-- Educaty — 0004 — domínios do tenant.
-- Todo org tem o subdomínio <slug>.educaty.app (resolvido por orgs.slug, já público).
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
