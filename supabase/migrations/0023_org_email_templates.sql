-- Listeny — 0023 — e-mails automáticos configuráveis pelo professor (ao aluno).
-- Catálogo de tipos mora no código (lib/emails.ts); aqui ficam os OVERRIDES por org:
-- ligar/desligar + assunto/texto. Disparo real é follow-up (infra de e-mail/Resend).
-- Pagamento (meios de pagamento) reusa `connectors`/`connector_credentials` (0008) — sem tabela nova.

create table if not exists public.org_email_templates (
  org_id     uuid not null references public.orgs (id) on delete cascade,
  key        text not null,               -- ex.: 'welcome','charge_due','new_lesson','session_reminder'
  enabled    boolean not null default false,
  subject    text,
  body       text,
  updated_at timestamptz not null default now(),
  primary key (org_id, key)
);

drop trigger if exists org_email_templates_set_updated_at on public.org_email_templates;
create trigger org_email_templates_set_updated_at
  before update on public.org_email_templates
  for each row execute function public.set_updated_at();

alter table public.org_email_templates enable row level security;
drop policy if exists org_email_templates_manage on public.org_email_templates;
create policy org_email_templates_manage on public.org_email_templates
  for all using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));
