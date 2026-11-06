-- Le Casse de la Cinémathèque (R56) et le Relais (R57).
-- À lancer dans l'éditeur SQL de Supabase, après 0001 à 0008.

-- 1. Le Casse : qui a ouvert quelle serrure (pour de vrai ou pour de faux),
--    et les votes pour démasquer la Taupe. Les rôles se calculent dans les
--    applis à partir des membres de la ligue et du mois.
create table if not exists public.casse_ouvertures (
  ligue_id uuid not null references public.ligues on delete cascade,
  mois text not null check (mois ~ '^\d{4}-\d{2}$'),
  serrure smallint not null check (serrure between 0 and 3),
  joueur_id uuid not null default auth.uid() references public.joueurs on delete cascade,
  vraie boolean not null default true,
  cree_le timestamptz not null default now(),
  primary key (ligue_id, mois, serrure, joueur_id)
);

create table if not exists public.casse_votes (
  ligue_id uuid not null references public.ligues on delete cascade,
  mois text not null check (mois ~ '^\d{4}-\d{2}$'),
  joueur_id uuid not null default auth.uid() references public.joueurs on delete cascade,
  accuse uuid not null references public.joueurs on delete cascade,
  primary key (ligue_id, mois, joueur_id)
);

alter table public.casse_ouvertures enable row level security;
alter table public.casse_votes enable row level security;

drop policy if exists "voir le casse" on public.casse_ouvertures;
create policy "voir le casse" on public.casse_ouvertures for select using (public.est_membre(ligue_id));
drop policy if exists "ouvrir ma serrure" on public.casse_ouvertures;
create policy "ouvrir ma serrure" on public.casse_ouvertures for insert with check (joueur_id = auth.uid() and public.est_membre(ligue_id));

drop policy if exists "voir les votes" on public.casse_votes;
create policy "voir les votes" on public.casse_votes for select using (public.est_membre(ligue_id));
drop policy if exists "voter" on public.casse_votes;
create policy "voter" on public.casse_votes for insert with check (joueur_id = auth.uid() and public.est_membre(ligue_id));
drop policy if exists "changer de vote" on public.casse_votes;
create policy "changer de vote" on public.casse_votes for update using (joueur_id = auth.uid());

-- 2. Le Relais : une chaîne de films liés par un acteur, un réalisateur ou
--    un compositeur ; chacun a 48 heures pour prendre le relais.
create table if not exists public.relais (
  id uuid primary key default gen_random_uuid(),
  ligue_id uuid not null references public.ligues on delete cascade,
  maillons jsonb not null default '[]'::jsonb,
  porteur uuid references public.joueurs on delete set null,
  echeance timestamptz,
  casse boolean not null default false,
  points int not null default 0,
  cree_le timestamptz not null default now(),
  maj timestamptz not null default now()
);
create index if not exists relais_ligue on public.relais (ligue_id, cree_le desc);

alter table public.relais enable row level security;
drop policy if exists "voir le relais" on public.relais;
create policy "voir le relais" on public.relais for select using (public.est_membre(ligue_id));
drop policy if exists "lancer un relais" on public.relais;
create policy "lancer un relais" on public.relais for insert with check (public.est_membre(ligue_id));
drop policy if exists "passer le relais" on public.relais;
create policy "passer le relais" on public.relais for update using (public.est_membre(ligue_id));
