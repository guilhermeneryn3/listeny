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
