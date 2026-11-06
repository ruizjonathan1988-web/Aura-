-- Aura : inviter un ami rapporte quelque chose aux deux.
-- À lancer dans l'éditeur SQL de Supabase, après 0001, 0002 et 0003.
--
-- Quand quelqu'un rejoint une ligue avec un code, lui et le créateur de la
-- ligue reçoivent la figurine dorée « invitation » (une seule fois chacun).

create or replace function public.rejoindre_ligue(code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  l uuid;
  createur uuid;
  nouveau boolean;
begin
  select id, cree_par into l, createur from ligues where code_invitation = upper(trim(code));
  if l is null then raise exception 'Code de ligue inconnu'; end if;
  insert into membres (ligue_id, joueur_id) values (l, auth.uid()) on conflict do nothing;
  get diagnostics nouveau = row_count;
  if nouveau and createur <> auth.uid() then
    insert into figurines (joueur_id, figurine, variante) values
      (auth.uid(), 'invitation', 'doree'),
      (createur, 'invitation', 'doree')
    on conflict do nothing;
  end if;
  return l;
end $$;

-- Chacun voit sa propre collection (les amis la voyaient déjà).
drop policy if exists "voir ma collection" on public.figurines;
create policy "voir ma collection" on public.figurines for select using (joueur_id = auth.uid());
