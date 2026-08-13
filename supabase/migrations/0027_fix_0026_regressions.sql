-- Listeny — 0027 — corrige duas regressões introduzidas pela 0026.
-- A 0026 quebrou o ciclo de RLS de sessions, mas:
--  (1) recriou `sessions_student_read` só com participante, PERDENDO o ramo de RESPONSÁVEL
--      que a 0014 tinha adicionado (is_guardian_of) → pais deixaram de ler as sessões do filho;
--  (2) revogou `is_session_participant`/`session_org` de anon, mas essas funções rodam DENTRO
--      das policies (avaliadas p/ qualquer papel que lê a tabela) → anônimo tomava
--      `42501 permission denied for function` ao ler sessions/session_students (antes: vazio).
-- Correções: (1) reembute o guardian na função; (2) devolve o grant a anon (retorna vazio, sem
-- vazamento — auth.uid() nulo). Helpers de policy seguem executáveis por todos, como os is_org_*.

-- (1) participante OU responsável (restaura a semântica da 0014, recursion-safe)
create or replace function public.is_session_participant(p_session uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.session_students ss
    join public.students s on s.id = ss.student_id
    where ss.session_id = p_session
      and (s.user_id = auth.uid() or public.is_guardian_of(s.id))
  );
$$;

-- (2) helpers de policy precisam ser executáveis por quem lê a tabela (inclui anon)
grant execute on function public.is_session_participant(uuid) to anon, authenticated;
grant execute on function public.session_org(uuid)            to anon, authenticated;
