-- Aura : se proposer des films et des séries, depuis VJOD ou Aura (R47).
-- À lancer dans l'éditeur SQL de Supabase, après 0001 à 0007.
--
-- La maison : les profils d'un même serveur Jellyfin. Chaque appareil a son
-- joueur anonyme ; « personne » (« <serveur>:<utilisateur Jellyfin> ») relie
-- tous les appareils d'un même profil, pour que son aura se cumule.
-- Les amis de ligue (sans compte sur le serveur) sont visés par leur joueur.
--
-- L'aura se calcule dans les applis à partir des propositions visibles :
-- regardé +1, aimé +2, aimé par plusieurs +3 de plus.

alter table public.joueurs add column if not exists maison text check (char_length(maison) <= 80);
alter table public.joueurs add column if not exists personne text check (char_length(personne) <= 160);
create index if not exists joueurs_maison on public.joueurs (maison);
create index if not exists joueurs_personne on public.joueurs (personne);

create or replace function public.ma_maison() returns setof text
language sql stable security definer set search_path = public as $$
  select maison from joueurs where id = auth.uid() and maison is not null
$$;

create or replace function public.mes_personnes() returns setof text
language sql stable security definer set search_path = public as $$
  select personne from joueurs where id = auth.uid() and personne is not null
$$;

revoke execute on function public.ma_maison() from anon;
revoke execute on function public.mes_personnes() from anon;

-- Les profils de la maison se voient entre eux.
drop policy if exists "voir ma maison" on public.joueurs;
create policy "voir ma maison" on public.joueurs
  for select using (maison is not null and maison in (select public.ma_maison()));

create table if not exists public.propositions (
  id uuid primary key default gen_random_uuid(),
  de uuid not null default auth.uid() references public.joueurs on delete cascade,
  de_personne text check (char_length(de_personne) <= 160),
  de_nom text not null check (char_length(de_nom) between 1 and 40),
  pour_personne text check (char_length(pour_personne) <= 160),
  pour_joueur uuid references public.joueurs on delete cascade,
  pour_nom text not null check (char_length(pour_nom) between 1 and 40),
  maison text check (char_length(maison) <= 80),
  ligue_id uuid references public.ligues on delete cascade,
  film_cle text not null check (char_length(film_cle) between 3 and 80),
  film jsonb not null,
  mot text check (char_length(mot) <= 140),
  vu_le timestamptz,
  aime boolean not null default false,
  note smallint check (note between 1 and 5),
  cree_le timestamptz not null default now(),
  check ((pour_personne is null) <> (pour_joueur is null)),
  check (maison is not null or ligue_id is not null)
);

-- Une seule proposition d'un même film à une même personne.
create unique index if not exists propositions_unique
  on public.propositions (de, coalesce(pour_personne, pour_joueur::text), film_cle);
create index if not exists propositions_maison on public.propositions (maison);
create index if not exists propositions_ligue on public.propositions (ligue_id);

alter table public.propositions enable row level security;

drop policy if exists "voir les propositions" on public.propositions;
create policy "voir les propositions" on public.propositions
  for select using (
    de = auth.uid()
    or pour_joueur = auth.uid()
    or (de_personne is not null and de_personne in (select public.mes_personnes()))
    or (pour_personne is not null and pour_personne in (select public.mes_personnes()))
    or (maison is not null and maison in (select public.ma_maison()))
    or (ligue_id is not null and public.est_membre(ligue_id))
  );

drop policy if exists "proposer" on public.propositions;
create policy "proposer" on public.propositions
  for insert with check (
    de = auth.uid()
    and (de_personne is null or de_personne in (select public.mes_personnes()))
    and (maison is null or maison in (select public.ma_maison()))
    and (ligue_id is null or public.est_membre(ligue_id))
    and (pour_joueur is null or exists (
      select 1 from public.membres m where m.ligue_id = propositions.ligue_id and m.joueur_id = propositions.pour_joueur
    ))
  );

-- Celui qui reçoit dit s'il a vu et aimé ; il ne change rien d'autre.
drop policy if exists "dire si j'ai vu" on public.propositions;
create policy "dire si j'ai vu" on public.propositions
  for update using (
    pour_joueur = auth.uid()
    or (pour_personne is not null and pour_personne in (select public.mes_personnes()))
  );
revoke update on public.propositions from anon, authenticated;
grant update (vu_le, aime, note) on public.propositions to authenticated;

drop policy if exists "retirer ma proposition" on public.propositions;
create policy "retirer ma proposition" on public.propositions
  for delete using (de = auth.uid());
