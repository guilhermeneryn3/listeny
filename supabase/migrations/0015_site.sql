-- Listeny — 0015 — site público editável do tenant.
-- Cada profissional/unidade tem seu SITE (a cara pública da marca). Conteúdo é DADO, editado
-- no admin e renderizado no portal público, tematizado pelo motor de branding (0003).
-- Leitura PÚBLICA (o site é aberto); escrita só quem gerencia o org (can_manage_org, 0011).

-- Uma linha por org: seções comuns de um site profissional.
create table if not exists public.org_site (
  org_id          uuid primary key references public.orgs (id) on delete cascade,
  published       boolean not null default false,
  hero_title      text,
  hero_subtitle   text,
  hero_cta_label  text,
  hero_cta_url    text,
  hero_image_url  text,
  about_title     text,
  about_body      text,
  contact_email   text,
  contact_phone   text,
  contact_whatsapp text,
  address         text,
  instagram       text,
  youtube         text,
  tiktok          text,
  facebook        text,
  updated_at      timestamptz not null default now()
);

drop trigger if exists org_site_set_updated_at on public.org_site;
create trigger org_site_set_updated_at
  before update on public.org_site
  for each row execute function public.set_updated_at();

-- Ofertas/serviços (vitrine): aula avulsa, pacote, mensalidade, mentoria… Sem checkout ainda.
create table if not exists public.site_offerings (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.orgs (id) on delete cascade,
  title        text not null,
  description  text,
  price        numeric(10,2),
  currency     text not null default 'BRL',
  duration_min integer,
  cta_label    text,
  cta_url      text,
  position     integer not null default 0,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists site_offerings_org_idx on public.site_offerings (org_id);

drop trigger if exists site_offerings_set_updated_at on public.site_offerings;
create trigger site_offerings_set_updated_at
  before update on public.site_offerings
  for each row execute function public.set_updated_at();

-- ── RLS: leitura pública, escrita só gestor ──────────────────────────────────
alter table public.org_site       enable row level security;
alter table public.site_offerings enable row level security;

drop policy if exists org_site_public_read on public.org_site;
create policy org_site_public_read on public.org_site
  for select using (true);
drop policy if exists org_site_manage on public.org_site;
create policy org_site_manage on public.org_site
  for all using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));

drop policy if exists site_offerings_public_read on public.site_offerings;
create policy site_offerings_public_read on public.site_offerings
  for select using (true);
drop policy if exists site_offerings_manage on public.site_offerings;
create policy site_offerings_manage on public.site_offerings
  for all using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));
