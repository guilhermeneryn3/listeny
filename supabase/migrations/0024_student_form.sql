-- Listeny — 0024 — cadastro de aluno configurável + autocadastro por link.
-- O professor escolhe quais campos entram no cadastro (e quais são obrigatórios); a mesma
-- config vale no formulário do professor E no link público de autocadastro. Catálogo de campos
-- mora no código (lib/studentFields.ts); valores extras vão em students.profile (jsonb).

-- 1) valores extras + status pendente (autocadastro aguarda aprovação)
alter table public.students add column if not exists profile jsonb not null default '{}'::jsonb;
alter table public.students drop constraint if exists students_status_check;
alter table public.students add constraint students_status_check
  check (status in ('active','inactive','pending'));

-- 2) config do formulário por org: campos habilitados/obrigatórios (ordenado) + toggle do link
create table if not exists public.org_student_form (
  org_id         uuid primary key references public.orgs (id) on delete cascade,
  enroll_enabled boolean not null default false,
  fields         jsonb not null default '[]'::jsonb, -- [{ "key": "...", "required": bool }] ordenado; presença = habilitado
  updated_at     timestamptz not null default now()
);

drop trigger if exists org_student_form_set_updated_at on public.org_student_form;
create trigger org_student_form_set_updated_at
  before update on public.org_student_form
  for each row execute function public.set_updated_at();

alter table public.org_student_form enable row level security;
drop policy if exists org_student_form_manage on public.org_student_form;
create policy org_student_form_manage on public.org_student_form
  for all using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));
-- a página pública de autocadastro lê a config no servidor (service-role), sem policy pública.

-- 3) RPC de autocadastro (anon): cria aluno PENDENTE se o org tem autocadastro ligado.
create or replace function public.self_enroll(
  p_org uuid, p_name text, p_email text, p_phone text, p_profile jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_enabled boolean;
begin
  select enroll_enabled into v_enabled from public.org_student_form where org_id = p_org;
  if v_enabled is not true then
    raise exception 'autocadastro desativado';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'nome obrigatório';
  end if;

  begin
    insert into public.students (org_id, name, email, phone, profile, status)
    values (
      p_org, btrim(p_name),
      nullif(btrim(coalesce(p_email, '')), ''),
      nullif(btrim(coalesce(p_phone, '')), ''),
      coalesce(p_profile, '{}'::jsonb),
      'pending'
    )
    returning id into v_id;
  exception when unique_violation then
    raise exception 'e-mail já cadastrado neste portal';
  end;

  return v_id;
end $$;

grant execute on function public.self_enroll(uuid, text, text, text, jsonb) to anon, authenticated;
