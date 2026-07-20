-- Listeny — 0018 — Financeiro: cobranças/mensalidades por aluno (gestão).
-- Camada de gestão (criar cobrança, valor, vencimento, pago/pendente). A "tomada de pagamento"
-- (conectar gateway do profissional + cobrança real) é bloco seguinte e adiciona colunas
-- (provider/external_id/payment_url) de forma aditiva. RLS por org; aluno lê as próprias.

create table if not exists public.charges (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.orgs (id) on delete cascade,
  student_id  uuid not null references public.students (id) on delete cascade,
  title       text not null,
  amount      numeric(10,2) not null,
  currency    text not null default 'BRL',
  due_date    date,
  status      text not null default 'pending' check (status in ('pending','paid','canceled')),
  paid_at     timestamptz,
  created_by  uuid references auth.users (id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists charges_org_idx     on public.charges (org_id);
create index if not exists charges_student_idx on public.charges (student_id);

drop trigger if exists charges_set_updated_at on public.charges;
create trigger charges_set_updated_at
  before update on public.charges
  for each row execute function public.set_updated_at();

alter table public.charges enable row level security;

drop policy if exists charges_manage on public.charges;
create policy charges_manage on public.charges
  for all using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));

drop policy if exists charges_self_read on public.charges;
create policy charges_self_read on public.charges
  for select using (exists (select 1 from public.students s
                            where s.id = student_id and s.user_id = auth.uid()));
