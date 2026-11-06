-- Aura : l'Affiche de la semaine jouée en ligue, et la Soirée jeu
-- (la télé en plateau, les téléphones en manettes).
-- À lancer dans l'éditeur SQL de Supabase, après 0001 à 0004.

-- 1. La semaine de ligue : une ligne par joueur et par geste.
--    affiche        : le film choisi par le Programmateur (ou par Pop)
--    bluff          : un faux synopsis écrit par un joueur
--    vote_bluff     : le synopsis que le joueur croit vrai
--    curseur        : le ressenti placé après la séance (0 à 10)
--    verdict        : la phrase du joueur (le Faussaire l'invente)
--    vote_faussaire : qui le joueur soupçonne d'être le Faussaire
create table if not exists public.semaine_ligue (
  ligue_id uuid not null references public.ligues on delete cascade,
  semaine date not null,
  joueur_id uuid not null default auth.uid() references public.joueurs on delete cascade,
  type text not null check (type in ('affiche', 'bluff', 'vote_bluff', 'curseur', 'verdict', 'vote_faussaire')),
  valeur jsonb not null,
  cree_le timestamptz not null default now(),
  primary key (ligue_id, semaine, joueur_id, type)
);

alter table public.semaine_ligue enable row level security;

drop policy if exists "voir la semaine de mes ligues" on public.semaine_ligue;
create policy "voir la semaine de mes ligues" on public.semaine_ligue
  for select using (public.est_membre(ligue_id));
drop policy if exists "jouer ma semaine" on public.semaine_ligue;
create policy "jouer ma semaine" on public.semaine_ligue
  for insert with check (joueur_id = auth.uid() and public.est_membre(ligue_id));
drop policy if exists "changer d'avis" on public.semaine_ligue;
create policy "changer d'avis" on public.semaine_ligue
  for update using (joueur_id = auth.uid()) with check (joueur_id = auth.uid());

-- 2. La Soirée jeu : la télé crée la soirée et tient l'état du jeu ; les
--    téléphones la rejoignent avec un code de 4 lettres et envoient leurs
--    gestes. Le code fait office de clé : il n'est connu que du salon.
create table if not exists public.soirees (
  code text primary key check (code ~ '^[A-Z]{4}$'),
  hote uuid not null default auth.uid(),
  etat jsonb not null default '{}'::jsonb,
  maj timestamptz not null default now()
);

create table if not exists public.soiree_joueurs (
  code text not null references public.soirees on delete cascade,
  joueur_id uuid not null default auth.uid(),
  pseudo text not null check (char_length(pseudo) between 1 and 24),
  profil text not null default 'fidele',
  envie text not null default 'frissonner',
  rejoint_le timestamptz not null default now(),
  primary key (code, joueur_id)
);

create table if not exists public.soiree_actions (
  id bigint generated always as identity primary key,
  code text not null references public.soirees on delete cascade,
  joueur_id uuid not null default auth.uid(),
  action jsonb not null,
  cree_le timestamptz not null default now()
);

alter table public.soirees enable row level security;
alter table public.soiree_joueurs enable row level security;
alter table public.soiree_actions enable row level security;

drop policy if exists "voir une soirée" on public.soirees;
create policy "voir une soirée" on public.soirees for select using (auth.uid() is not null);
drop policy if exists "créer ma soirée" on public.soirees;
create policy "créer ma soirée" on public.soirees for insert with check (hote = auth.uid());
drop policy if exists "mener ma soirée" on public.soirees;
create policy "mener ma soirée" on public.soirees for update using (hote = auth.uid());

drop policy if exists "voir les joueurs" on public.soiree_joueurs;
create policy "voir les joueurs" on public.soiree_joueurs for select using (auth.uid() is not null);
drop policy if exists "rejoindre" on public.soiree_joueurs;
create policy "rejoindre" on public.soiree_joueurs for insert with check (joueur_id = auth.uid());
drop policy if exists "changer d'envie" on public.soiree_joueurs;
create policy "changer d'envie" on public.soiree_joueurs for update using (joueur_id = auth.uid());

drop policy if exists "jouer un geste" on public.soiree_actions;
create policy "jouer un geste" on public.soiree_actions for insert with check (joueur_id = auth.uid());
drop policy if exists "l'hôte lit les gestes" on public.soiree_actions;
create policy "l'hôte lit les gestes" on public.soiree_actions for select using (
  joueur_id = auth.uid()
  or exists (select 1 from public.soirees s where s.code = soiree_actions.code and s.hote = auth.uid())
);
