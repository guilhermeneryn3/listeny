-- Listeny — 0014 — base institucional: tipo de unidade, plano, papéis, responsáveis, convites.
-- Aditivo sobre 0001–0012: 1A (alunos/turmas) e 1B (agenda) seguem funcionando — só ampliamos
-- can_manage_org (passa a incluir diretor/coordenador) e somamos tabelas.
-- Rode DEPOIS do 0013 (que commita os novos papéis do enum).

-- ── Tipo de unidade e plano em orgs ──────────────────────────────────────────
do $$ begin
  create type public.org_kind as enum ('individual','institution');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.org_plan as enum ('free','basico','intermediario','premium','enterprise');
exception when duplicate_object then null; end $$;

alter table public.orgs add column if not exists kind public.org_kind not null default 'individual';
alter table public.orgs add column if not exists plan public.org_plan not null default 'free';

-- plan é server-only (billing); kind o dono escolhe no onboarding. Estende o guard da 0002.
create or replace function public.guard_org_billing()
returns trigger language plpgsql as $$
begin
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.tier := 'free';
    new.status := 'active';
    new.plan := 'free';
    return new;
  end if;
  if new.tier is distinct from old.tier
     or new.status is distinct from old.status
     or new.plan is distinct from old.plan then
    raise exception 'tier/status/plan do org são definidos apenas pelo servidor';
  end if;
  return new;
end;
$$;

-- ── Helpers de acesso (redefine — agora incluem diretor/coordenador) ─────────
create or replace function public.is_org_admin(p_org uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select public.is_org_owner(p_org) or exists (
    select 1 from public.memberships m
    where m.org_id = p_org and m.user_id = auth.uid() and m.role = 'director'
  );
$$;

create or replace function public.is_org_staff(p_org uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.memberships m
    where m.org_id = p_org and m.user_id = auth.uid()
      and m.role in ('director','coordinator','teacher','staff')
  );
$$;
-- can_manage_org (0011) = is_org_owner OR is_org_staff → herda a ampliação automaticamente.

-- ── Responsáveis (pais) ──────────────────────────────────────────────────────
create table if not exists public.student_guardians (
  student_id        uuid not null references public.students (id) on delete cascade,
  guardian_user_id  uuid not null references auth.users (id) on delete cascade,
  relationship      text,
  created_at        timestamptz not null default now(),
  primary key (student_id, guardian_user_id)
);
create index if not exists student_guardians_guardian_idx on public.student_guardians (guardian_user_id);

alter table public.student_guardians enable row level security;
drop policy if exists student_guardians_manage on public.student_guardians;
create policy student_guardians_manage on public.student_guardians
  for all using (exists (select 1 from public.students s
                         where s.id = student_id and public.can_manage_org(s.org_id)))
  with check (exists (select 1 from public.students s
                      where s.id = student_id and public.can_manage_org(s.org_id)));
drop policy if exists student_guardians_self on public.student_guardians;
create policy student_guardians_self on public.student_guardians
  for select using (guardian_user_id = auth.uid());

-- helper: o usuário é responsável por este aluno?
create or replace function public.is_guardian_of(p_student uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.student_guardians g
    where g.student_id = p_student and g.guardian_user_id = auth.uid()
  );
$$;

-- estende a leitura: responsável lê o(s) filho(s) e as sessões deles.
drop policy if exists students_select on public.students;
create policy students_select on public.students
  for select using (
    public.can_manage_org(org_id) or user_id = auth.uid() or public.is_guardian_of(id)
  );

drop policy if exists sessions_student_read on public.sessions;
create policy sessions_student_read on public.sessions
  for select using (exists (
    select 1 from public.session_students ss
    join public.students s on s.id = ss.student_id
    where ss.session_id = id and (s.user_id = auth.uid() or public.is_guardian_of(s.id))
  ));

-- ── Convites (entrar num org sem ser dono) ───────────────────────────────────
create table if not exists public.invitations (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.orgs (id) on delete cascade,
  email      text not null,
  role       public.membership_role not null default 'teacher',
  student_id uuid references public.students (id) on delete set null,  -- p/ convite de responsável
  token      text not null unique,
  status     text not null default 'pending'
               check (status in ('pending','accepted','declined','expired')),
  invited_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  expires_at timestamptz
);
create index if not exists invitations_org_idx   on public.invitations (org_id);
create index if not exists invitations_email_idx on public.invitations (lower(email));

alter table public.invitations enable row level security;
-- admin do org (dono/diretor) gerencia os convites do seu org
drop policy if exists invitations_manage on public.invitations;
create policy invitations_manage on public.invitations
  for all using (public.is_org_admin(org_id)) with check (public.is_org_admin(org_id));
-- o convidado lê os convites endereçados ao seu e-mail
drop policy if exists invitations_invitee_read on public.invitations;
create policy invitations_invitee_read on public.invitations
  for select using (lower(email) = lower(coalesce(auth.email(), '')));

-- aceite: cria a membership (contorna a RLS de insert que exige dono) com segurança.
create or replace function public.accept_invitation(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  inv  public.invitations;
  uid  uuid := auth.uid();
  mail text := auth.email();
begin
  if uid is null then raise exception 'não autenticado'; end if;

  select * into inv from public.invitations
   where token = p_token and status = 'pending'
     and (expires_at is null or expires_at > now());
  if not found then raise exception 'convite inválido ou expirado'; end if;
  if lower(inv.email) <> lower(coalesce(mail, '')) then
    raise exception 'convite endereçado a outro e-mail';
  end if;

  insert into public.memberships (org_id, user_id, role)
  values (inv.org_id, uid, inv.role)
  on conflict (org_id, user_id) do update set role = excluded.role;

  if inv.role = 'parent' and inv.student_id is not null then
    insert into public.student_guardians (student_id, guardian_user_id)
    values (inv.student_id, uid)
    on conflict do nothing;
  end if;

  update public.invitations set status = 'accepted' where id = inv.id;
  return jsonb_build_object('org_id', inv.org_id);
end;
$$;
revoke all on function public.accept_invitation(text) from public, anon;
grant execute on function public.accept_invitation(text) to authenticated;
