-- Listeny — 0026 — corrige recursão de RLS entre `sessions` e `session_students`.
-- A 0012 criou policies que se leem em CICLO: `sessions_student_read` (em sessions) lê
-- session_students, e `session_students_manage` (em session_students) lê sessions de volta.
-- Ao inserir/ler uma sessão pelo client AUTENTICADO o Postgres aborta com
-- `42P17: infinite recursion detected in policy for relation "sessions"`.
-- Quebra o ciclo com funções SECURITY DEFINER (as leituras internas ignoram RLS).
-- Semântica preservada: participante lê as suas sessões; gestor do org gerencia os vínculos.

-- É participante da sessão? (lê session_students SEM RLS → não reentra em sessions)
create or replace function public.is_session_participant(p_session uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.session_students ss
    join public.students s on s.id = ss.student_id
    where ss.session_id = p_session and s.user_id = auth.uid()
  );
$$;
revoke all on function public.is_session_participant(uuid) from public, anon;
grant execute on function public.is_session_participant(uuid) to authenticated;

-- Org de uma sessão (lê sessions SEM RLS → não reentra em session_students)
create or replace function public.session_org(p_session uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select org_id from public.sessions where id = p_session;
$$;
revoke all on function public.session_org(uuid) from public, anon;
grant execute on function public.session_org(uuid) to authenticated;

-- Recria as policies sem o cruzamento recursivo.
drop policy if exists sessions_student_read on public.sessions;
create policy sessions_student_read on public.sessions
  for select using (public.is_session_participant(id));

drop policy if exists session_students_manage on public.session_students;
create policy session_students_manage on public.session_students
  for all using (public.can_manage_org(public.session_org(session_id)))
  with check (public.can_manage_org(public.session_org(session_id)));
