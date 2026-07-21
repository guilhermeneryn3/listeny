-- Listeny — 0020 — módulos opcionais por org.
-- O plano gateia os módulos DISPONÍVEIS; aqui o org liga/desliga os que quer exibir (um
-- autônomo pode não querer Site/Eventos). Guarda só overrides; ausente = habilitado (se no plano).
-- Efetivo = módulos do plano ∩ (não desligados). Só admin (dono/diretor) altera.

create table if not exists public.org_modules (
  org_id     uuid not null references public.orgs (id) on delete cascade,
  module_key text not null,
  enabled    boolean not null default true,
  primary key (org_id, module_key)
);

alter table public.org_modules enable row level security;

-- gestor lê (pra calcular os módulos efetivos); só admin escreve.
drop policy if exists org_modules_read on public.org_modules;
create policy org_modules_read on public.org_modules
  for select using (public.can_manage_org(org_id));
drop policy if exists org_modules_manage on public.org_modules;
create policy org_modules_manage on public.org_modules
  for all using (public.is_org_admin(org_id)) with check (public.is_org_admin(org_id));
