-- Listeny — 0019 — agendamento pelo aluno (opt-in). Reaproveita as sessões da 0012:
-- uma "vaga" = uma sessão marcada bookable (sem participante). O aluno reserva → vira
-- participante e a vaga fecha. Toggle por org (org_booking.enabled) — só liga se o professor quiser.

alter table public.sessions add column if not exists bookable boolean not null default false;

-- toggle opt-in por org
create table if not exists public.org_booking (
  org_id  uuid primary key references public.orgs (id) on delete cascade,
  enabled boolean not null default false
);
alter table public.org_booking enable row level security;
drop policy if exists org_booking_read on public.org_booking;
create policy org_booking_read on public.org_booking for select using (true);
drop policy if exists org_booking_manage on public.org_booking;
create policy org_booking_manage on public.org_booking
  for all using (public.can_manage_org(org_id)) with check (public.can_manage_org(org_id));

-- aluno/membro enxerga as VAGAS ABERTAS (pra poder reservar); gestor já lê por sessions_manage
drop policy if exists sessions_bookable_read on public.sessions;
create policy sessions_bookable_read on public.sessions
  for select using (bookable and (public.is_org_member(org_id) or public.is_org_owner(org_id)));

-- reserva: valida tudo e cria o vínculo (aluno não pode inserir sessão direto → RPC definer)
create or replace function public.book_session(p_session uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  sess public.sessions;
  v_enabled boolean;
  sid uuid;
begin
  if auth.uid() is null then raise exception 'não autenticado'; end if;

  select * into sess from public.sessions where id = p_session;
  if not found then raise exception 'vaga inexistente'; end if;
  if not sess.bookable then raise exception 'vaga indisponível'; end if;
  if sess.starts_at <= now() then raise exception 'horário já passou'; end if;

  select enabled into v_enabled from public.org_booking where org_id = sess.org_id;
  if not coalesce(v_enabled, false) then raise exception 'agendamento desativado'; end if;

  if exists (select 1 from public.session_students where session_id = p_session) then
    raise exception 'vaga já reservada';
  end if;

  select id into sid from public.students
   where org_id = sess.org_id and user_id = auth.uid() limit 1;
  if sid is null then raise exception 'você não é aluno deste portal'; end if;

  insert into public.session_students (session_id, student_id) values (p_session, sid);
  update public.sessions set bookable = false where id = p_session;
  return jsonb_build_object('ok', true, 'session_id', p_session);
end;
$$;
revoke all on function public.book_session(uuid) from public, anon;
grant execute on function public.book_session(uuid) to authenticated;
