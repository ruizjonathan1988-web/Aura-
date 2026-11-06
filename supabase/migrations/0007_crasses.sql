-- Aura : les crasses entre amis de la ligue (R40).
-- À lancer dans l'éditeur SQL de Supabase, après 0001 à 0006.
--
-- Une crasse par semaine et par joueur, à un ami de sa ligue. Celui qui la
-- reçoit l'encaisse, la pare (une charge de pouvoir) ou la renvoie (une fois
-- par mois, le renvoi ne compte pas dans la crasse de la semaine).

create table if not exists public.crasses (
  id uuid primary key default gen_random_uuid(),
  ligue_id uuid not null references public.ligues on delete cascade,
  de uuid not null default auth.uid() references public.joueurs on delete cascade,
  pour uuid not null references public.joueurs on delete cascade,
  type text not null check (type in ('niveauImpose', 'popcorn', 'volDAudace', 'fauxSpoiler')),
  renvoi boolean not null default false,
  reponse text check (reponse in ('encaissee', 'paree', 'renvoyee')),
  cree_le timestamptz not null default now(),
  check (de <> pour)
);

create index if not exists crasses_de_semaine on public.crasses (de, cree_le);

alter table public.crasses enable row level security;

drop policy if exists "voir les crasses de ma ligue" on public.crasses;
create policy "voir les crasses de ma ligue" on public.crasses
  for select using (public.est_membre(ligue_id));

drop policy if exists "faire une crasse" on public.crasses;
create policy "faire une crasse" on public.crasses
  for insert with check (
    de = auth.uid()
    and public.est_membre(ligue_id)
    and exists (select 1 from public.membres m where m.ligue_id = crasses.ligue_id and m.joueur_id = crasses.pour)
    and (
      renvoi
      or not exists (
        select 1 from public.crasses c
        where c.de = auth.uid() and not c.renvoi and c.cree_le >= date_trunc('week', now())
      )
    )
  );

drop policy if exists "répondre à une crasse" on public.crasses;
create policy "répondre à une crasse" on public.crasses
  for update using (pour = auth.uid()) with check (pour = auth.uid());
