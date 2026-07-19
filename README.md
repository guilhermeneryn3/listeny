# Listeny

**Plataforma multi-tenant white-label de portais de aprendizado.** Cada professor/criador
ganha o próprio **portal** (logo, cores, template de aparência, domínio próprio) para
organizar aulas (incl. ao vivo), acompanhar alunos e fazer gestão financeira. O **portal web
é o produto**; este **app mobile é a ferramenta companheira** que se re-veste com a marca do
tenant após o login.

Produto da holding **N3 Labz** — nasce federado no painel N3 e segue a arquitetura "tomada"
(API-first, conectores plugáveis, identidade multi-tenant, afiliados desde a base).

## Repositórios irmãos
- **`Listeny/`** (este) — o **cérebro** (`supabase/`) + o app mobile companheiro (Expo).
- **`listeny-web/`** — o **portal web** multi-tenant (Next.js) + landing + admin do criador.
- **`N3 Labz/`** — o painel da holding que federa/gerencia o Listeny.

Web, app e painel N3 apontam para o **mesmo** projeto Supabase (o cérebro mora aqui).

## Cérebro (`supabase/`)
- **Identidade** (`0001`): `profiles` cross-tenant, `locale` pt-BR (i18n-ready), premium
  travado ao servidor.
- **Tenancy** (`0002`): `orgs` (tenants) + `memberships` (teacher/student/staff), RLS sem
  recursão via helpers `is_org_member`/`is_org_owner`.
- **Branding** (`0003`): `theme_templates` (catálogo) + `org_branding` — a "cara" é DADO;
  contrato de tokens único p/ portal (CSS vars) e app (theme tokens).
- **Domínios** (`0004`): `org_domains` — subdomínio `<slug>.listeny.app` + domínio próprio.
- **Afiliados** (`0005`-`0007`): programa da plataforma (modelo VamAI) — indica o professor
  pagante; comissão/atribuição first-touch; campanhas/cupons/trial.
- **Conectores** (`0008`): encaixe universal (live_video/payment/storage/calendar) por tenant.
- **Billing seam** (`0009`): assinatura SaaS-branca (ativa) + venda-ao-aluno marketplace
  (contrato inerte, faseado).
- **RPC admin** (`0010`): `force_delete_affiliate` (chamada pelo painel N3).
- **Edge functions**: `revenuecat-sync`, `redeem-code`, `notify-affiliate`,
  `admin-delete-account` (padrão VamAI: JWT revalidado, service-role, segredo compartilhado).

Deploy: ver comentário em `supabase/config.toml`.

## App mobile
Expo SDK 54 + TypeScript + expo-router. Ver `.env.example`. (Scaffold — telas de ensino na
Fase 1.)
