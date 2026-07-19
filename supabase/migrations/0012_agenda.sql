-- Listeny — 0012 — Agenda: sessões agendadas (presencial e/ou online).
-- Serve tanto ensino online quanto PRESENCIAL (personal, luta, dança). O MODO é POR SESSÃO,
-- não por professor: o mesmo professor mistura presencial e online livremente. `location`
-- (endereço) e `meeting_url` (link) são independentes e opcionais — dá até híbrido.
-- Fuso: guarda em UTC (timestamptz); a exibição usa o fuso do cliente. RLS por org.

create table if not exists public.sessions (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.orgs (id) on delete cascade,
  title        text not null,
  kind         text not null default 'in_person' check (kind in ('in_person','online')),
  starts_at    timestamptz not null,
  duration_min integer not null default 60 check (duration_min > 0),
  location     text,        -- endereço (quando presencial)
  meeting_url  text,        -- link (quando online) — pode coexistir com location
  recording_url text,       -- gravação p/ assistir depois (aluno que faltou; B2B/escola)
  class_id     uuid references public.classes (id) on delete set null,
  notes        text,
  status       text not null default 'scheduled'
                 check (status in ('scheduled','done','canceled','no_show')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists sessions_org_idx     on public.sessions (org_id);
create index if not exists sessions_starts_idx   on public.sessions (org_id, starts_at);

drop trigger if exists sessions_set_updated_at on public.sessions;
create trigger sessions_set_updated_at
  before update on public.sessions
  for each row execute function public.set_updated_at();

-- Participantes + presença por aluno.
create table if not exists public.session_students (
  session_id uuid not null references public.sessions (id) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  attendance text not null default 'pending' check (attendance in ('pending','present','absent')),
  primary key (session_id, student_id)
);
create index if not exists session_students_student_idx on public.session_students (student_id);

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.sessions         enable row level security;
alter table public.session_students enable row level security;

-- sessions: gestor do org administra; aluno vinculado (com conta) lê as suas.
drop policy if exists sessions_manage on public.sessions;
create policy sessions_manage on public.sessions
  for all using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));
drop policy if exists sessions_student_read on public.sessions;
create policy sessions_student_read on public.sessions
  for select using (exists (
    select 1 from public.session_students ss
    join public.students s on s.id = ss.student_id
    where ss.session_id = id and s.user_id = auth.uid()
  ));

-- session_students: gerido pela sessão (→ org do gestor).
drop policy if exists session_students_manage on public.session_students;
create policy session_students_manage on public.session_students
  for all using (exists (select 1 from public.sessions s
                         where s.id = session_id and public.can_manage_org(s.org_id)))
  with check (exists (select 1 from public.sessions s
                      where s.id = session_id and public.can_manage_org(s.org_id)));
-- o próprio aluno lê a sua participação.
drop policy if exists session_students_student_read on public.session_students;
create policy session_students_student_read on public.session_students
  for select using (exists (select 1 from public.students s
                            where s.id = student_id and s.user_id = auth.uid()));
