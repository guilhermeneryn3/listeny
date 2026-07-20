-- Listeny — 0016 — acesso do aluno / 1º acesso.
-- Quando o professor cria a conta do aluno com senha temporária, marcamos must_change_password
-- pra forçar a troca no primeiro login. O resto do modelo já existe: identidade global
-- (profiles), contexto (memberships role 'student'), link do roster (students.user_id).

alter table public.profiles
  add column if not exists must_change_password boolean not null default false;
