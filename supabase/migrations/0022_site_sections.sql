-- Listeny — 0022 — visibilidade das seções do site (funcionalidades do módulo Site).
-- O profissional liga/desliga cada bloco do site público no console. Defaults preservam o
-- comportamento atual (about/offerings/contact aparecem; events/booking são novos → off).

alter table public.org_site
  add column if not exists show_about     boolean not null default true,
  add column if not exists show_offerings boolean not null default true,
  add column if not exists show_events    boolean not null default false,
  add column if not exists show_booking   boolean not null default false,
  add column if not exists show_contact   boolean not null default true,
  add column if not exists booking_cta_label text;
