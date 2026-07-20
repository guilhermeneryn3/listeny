-- Listeny — 0017 — módulo Aulas/conteúdo: aula/tarefa/meta atribuída a alunos/turma.
-- O professor cria e atribui; o aluno vê o que é seu e marca como concluído. Mídia via link
-- (upload de arquivo fica p/ follow-up; kind já comporta image/file). RLS por org + aluno-dono.

create table if not exists public.lessons (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.orgs (id) on delete cascade,
  title       text not null,
  type        text not null default 'lesson' check (type in ('lesson','homework','goal')),
  description text,
  due_date    date,
  class_id    uuid references public.classes (id) on delete set null,
  created_by  uuid references auth.users (id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists lessons_org_idx on public.lessons (org_id);

drop trigger if exists lessons_set_updated_at on public.lessons;
create trigger lessons_set_updated_at
  before update on public.lessons
  for each row execute function public.set_updated_at();

create table if not exists public.lesson_assignments (
  lesson_id    uuid not null references public.lessons (id) on delete cascade,
  student_id   uuid not null references public.students (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending','done')),
  completed_at timestamptz,
  primary key (lesson_id, student_id)
);
create index if not exists lesson_assignments_student_idx on public.lesson_assignments (student_id);

create table if not exists public.lesson_media (
  id         uuid primary key default gen_random_uuid(),
  lesson_id  uuid not null references public.lessons (id) on delete cascade,
  url        text not null,
  name       text,
  kind       text not null default 'link' check (kind in ('link','image','file')),
  created_at timestamptz not null default now()
);
create index if not exists lesson_media_lesson_idx on public.lesson_media (lesson_id);

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.lessons            enable row level security;
alter table public.lesson_assignments enable row level security;
alter table public.lesson_media       enable row level security;

-- helper: o aluno logado está atribuído a esta aula?
create or replace function public.is_lesson_assignee(p_lesson uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.lesson_assignments la
    join public.students s on s.id = la.student_id
    where la.lesson_id = p_lesson and s.user_id = auth.uid()
  );
$$;

-- lessons: gestor gerencia; aluno atribuído lê.
drop policy if exists lessons_manage on public.lessons;
create policy lessons_manage on public.lessons
  for all using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));
drop policy if exists lessons_assignee_read on public.lessons;
create policy lessons_assignee_read on public.lessons
  for select using (public.is_lesson_assignee(id));

-- lesson_assignments: gestor gerencia; o aluno lê e ATUALIZA a própria (marcar concluída).
drop policy if exists lesson_assignments_manage on public.lesson_assignments;
create policy lesson_assignments_manage on public.lesson_assignments
  for all using (exists (select 1 from public.lessons l
                         where l.id = lesson_id and public.can_manage_org(l.org_id)))
  with check (exists (select 1 from public.lessons l
                      where l.id = lesson_id and public.can_manage_org(l.org_id)));
drop policy if exists lesson_assignments_self_read on public.lesson_assignments;
create policy lesson_assignments_self_read on public.lesson_assignments
  for select using (exists (select 1 from public.students s
                            where s.id = student_id and s.user_id = auth.uid()));
drop policy if exists lesson_assignments_self_update on public.lesson_assignments;
create policy lesson_assignments_self_update on public.lesson_assignments
  for update using (exists (select 1 from public.students s
                            where s.id = student_id and s.user_id = auth.uid()))
  with check (exists (select 1 from public.students s
                      where s.id = student_id and s.user_id = auth.uid()));

-- lesson_media: gestor gerencia; gestor ou aluno atribuído lê.
drop policy if exists lesson_media_manage on public.lesson_media;
create policy lesson_media_manage on public.lesson_media
  for all using (exists (select 1 from public.lessons l
                         where l.id = lesson_id and public.can_manage_org(l.org_id)))
  with check (exists (select 1 from public.lessons l
                      where l.id = lesson_id and public.can_manage_org(l.org_id)));
drop policy if exists lesson_media_read on public.lesson_media;
create policy lesson_media_read on public.lesson_media
  for select using (
    exists (select 1 from public.lessons l where l.id = lesson_id and public.can_manage_org(l.org_id))
    or public.is_lesson_assignee(lesson_id)
  );
