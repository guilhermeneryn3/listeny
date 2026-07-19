-- Educaty — 0002 — multi-tenant: orgs (tenants) + memberships.
-- Um `org` é a MARCA do professor/criador (workspace white-label): tem slug (subdomínio
-- <slug>.educaty.app), tier de assinatura e membros. Um auth.users pode ser owner de um org
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
