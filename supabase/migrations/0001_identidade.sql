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
