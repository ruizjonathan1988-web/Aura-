-- Aura : le Cadeau cacheté et le Flair.
-- À lancer dans l'éditeur SQL de Supabase, après 0001 à 0005.
--
-- On offre un film à un ami de sa ligue, avec un mot, à ouvrir tel jour.
-- L'ami l'ouvre, le regarde et le note : le Flair de celui qui l'a offert,
-- c'est la part de ses cadeaux notés 4 ou 5.

create table if not exists public.cadeaux (
  id uuid primary key default gen_random_uuid(),
  ligue_id uuid not null references public.ligues on delete cascade,
  de uuid not null default auth.uid() references public.joueurs on delete cascade,
  pour uuid not null references public.joueurs on delete cascade,
  film jsonb not null,
  mot text check (char_length(mot) <= 120),
  ouvrir_le date not null,
  ouvert boolean not null default false,
  note smallint check (note between 1 and 5),
  cree_le timestamptz not null default now(),
  check (de <> pour)
);

alter table public.cadeaux enable row level security;

drop policy if exists "voir les cadeaux de ma ligue" on public.cadeaux;
create policy "voir les cadeaux de ma ligue" on public.cadeaux
  for select using (public.est_membre(ligue_id));

drop policy if exists "offrir un cadeau" on public.cadeaux;
create policy "offrir un cadeau" on public.cadeaux
  for insert with check (
    de = auth.uid()
    and public.est_membre(ligue_id)
    and exists (select 1 from public.membres m where m.ligue_id = cadeaux.ligue_id and m.joueur_id = cadeaux.pour)
  );

drop policy if exists "ouvrir et noter mon cadeau" on public.cadeaux;
create policy "ouvrir et noter mon cadeau" on public.cadeaux
  for update using (pour = auth.uid()) with check (pour = auth.uid());
