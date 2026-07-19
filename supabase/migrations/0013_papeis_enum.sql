-- Listeny — 0013 — amplia os papéis de acesso (RBAC institucional).
-- Novos valores do enum membership_role: director (diretor), coordinator (coordenador),
-- parent (responsável). Ficam ao lado de teacher/student/staff da 0002.
--
-- IMPORTANTE: valores de enum precisam ser COMMITADOS antes de serem usados. Rode este
-- arquivo SOZINHO (separado do 0014) no SQL Editor. `if not exists` = idempotente.

alter type public.membership_role add value if not exists 'director';
alter type public.membership_role add value if not exists 'coordinator';
alter type public.membership_role add value if not exists 'parent';
