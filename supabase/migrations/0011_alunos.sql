-- Listeny — 0011 — alunos e turmas (roster do professor).
-- Fase 1A: o professor traz os PRÓPRIOS alunos e os gerencia. O aluno pode NÃO ter conta
-- (é um registro do org); quando criar conta, liga-se via user_id (convite fica p/ depois).
-- RLS: quem gerencia o org (dono ou membership teacher/staff) administra; o próprio aluno,
-- se tiver conta vinculada, lê a sua linha.

-- Helper: o usuário logado pode GERENCIAR este org? (dono OU staff). SECURITY DEFINER p/ não
-- recursar na RLS de memberships (mesmo motivo dos helpers da 0002).
create or replace function public.is_org_staff(p_org uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.memberships m
    where m.org_id = p_org and m.user_id = auth.uid()
      and m.role in ('teacher','staff')
  );
$$;

create or replace function public.can_manage_org(p_org uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select public.is_org_owner(p_org) or public.is_org_staff(p_org);
$$;

-- ── Alunos ───────────────────────────────────────────────────────────────────
create table if not exists public.students (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.orgs (id) on delete cascade,
  name       text not null,
  email      text,
  phone      text,
  avatar_url text,
  notes      text,
  status     text not null default 'active' check (status in ('active','inactive')),
  user_id    uuid references auth.users (id) on delete set null,  -- link quando o aluno tiver conta
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists students_org_idx on public.students (org_id);
-- um e-mail por org (quando informado)
create unique index if not exists students_org_email_uidx
  on public.students (org_id, lower(email)) where email is not null;

drop trigger if exists students_set_updated_at on public.students;
create trigger students_set_updated_at
  before update on public.students
  for each row execute function public.set_updated_at();

-- ── Turmas ───────────────────────────────────────────────────────────────────
create table if not exists public.classes (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.orgs (id) on delete cascade,
  name        text not null,
  description text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists classes_org_idx on public.classes (org_id);

drop trigger if exists classes_set_updated_at on public.classes;
create trigger classes_set_updated_at
  before update on public.classes
  for each row execute function public.set_updated_at();

create table if not exists public.class_students (
  class_id   uuid not null references public.classes (id) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (class_id, student_id)
);
create index if not exists class_students_student_idx on public.class_students (student_id);

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.students       enable row level security;
alter table public.classes        enable row level security;
alter table public.class_students enable row level security;

-- students: gestor do org administra; aluno vinculado lê a própria linha.
drop policy if exists students_select on public.students;
create policy students_select on public.students
  for select using (public.can_manage_org(org_id) or user_id = auth.uid());
drop policy if exists students_insert on public.students;
create policy students_insert on public.students
  for insert with check (public.can_manage_org(org_id));
drop policy if exists students_update on public.students;
create policy students_update on public.students
  for update using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));
drop policy if exists students_delete on public.students;
create policy students_delete on public.students
  for delete using (public.can_manage_org(org_id));

-- classes: só gestor do org.
drop policy if exists classes_all on public.classes;
create policy classes_all on public.classes
  for all using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));

-- class_students: gerido pela turma (→ org do gestor).
drop policy if exists class_students_all on public.class_students;
create policy class_students_all on public.class_students
  for all using (exists (select 1 from public.classes c
                         where c.id = class_id and public.can_manage_org(c.org_id)))
  with check (exists (select 1 from public.classes c
                      where c.id = class_id and public.can_manage_org(c.org_id)));
