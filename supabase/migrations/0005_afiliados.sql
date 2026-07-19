-- Educaty — 0005 — programa de afiliados DA PLATAFORMA (afiliado indica o professor pagante).
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
