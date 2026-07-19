-- Listeny — 0010 — RPCs administrativas que o painel N3 chama (service-role).
-- force_delete_affiliate: apaga afiliado À FORÇA (limpeza de teste). Só o OWNER dispara na UI
-- do N3. Respeita a ordem dos FKs `on delete restrict`. Afiliado real que já operou deve ser
-- ARQUIVADO (status='archived'), não apagado.

create or replace function public.force_delete_affiliate(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from commission_events where affiliate_id = p_id;
  delete from payouts          where affiliate_id = p_id;
  delete from invoices         where affiliate_id = p_id;
  delete from referrals        where affiliate_id = p_id;
  -- cascateiam sozinhos: affiliate_socials/terms/banks/notifications.
  delete from affiliates       where id = p_id;
end;
$$;

revoke all on function public.force_delete_affiliate(uuid) from public;
revoke all on function public.force_delete_affiliate(uuid) from anon;
revoke all on function public.force_delete_affiliate(uuid) from authenticated;
