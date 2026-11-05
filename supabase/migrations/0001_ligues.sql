-- Aura : le jeu partagé entre amis (ligues, saisons, séances, collection).
-- À lancer dans l'éditeur SQL de Supabase. Chaque joueur ne modifie que ses
-- propres lignes ; il voit celles des membres de ses ligues.

create table public.joueurs (
  id uuid primary key references auth.users on delete cascade,
  pseudo text not null check (char_length(pseudo) between 2 and 24),
  profil text not null default 'fidele',
  cree_le timestamptz not null default now()
);

create table public.ligues (
  id uuid primary key default gen_random_uuid(),
  nom text not null check (char_length(nom) between 2 and 40),
  code_invitation text not null unique default upper(substr(md5(random()::text), 1, 6)),
  cree_par uuid not null references public.joueurs on delete cascade,
  cree_le timestamptz not null default now()
);

create table public.membres (
  ligue_id uuid references public.ligues on delete cascade,
  joueur_id uuid references public.joueurs on delete cascade,
  rejoint_le timestamptz not null default now(),
  primary key (ligue_id, joueur_id)
);

create table public.saisons (
  id uuid primary key default gen_random_uuid(),
  ligue_id uuid not null references public.ligues on delete cascade,
  debut date not null,
  fin date not null,
  theme text,
  check (fin > debut)
);

-- Une séance jouée : la carte, le pronostic, la note, le Verdict.
create table public.seances (
  id uuid primary key default gen_random_uuid(),
  joueur_id uuid not null references public.joueurs on delete cascade default auth.uid(),
  saison_id uuid references public.saisons on delete set null,
  titre text not null,
  tmdb_id integer,
  type_carte text not null,
  pronostic smallint check (pronostic between 1 and 5),
  note smallint check (note between 1 and 5),
  verdict text check (char_length(verdict) <= 120),
  cases smallint not null default 0 check (cases between 0 and 3),
  vu_le timestamptz not null default now()
);

-- Plafond d'équité : jamais plus de 3 cases par jour et par joueur.
create function public.plafonner_cases() returns trigger
language plpgsql security definer set search_path = public as $$
declare deja int;
begin
  select coalesce(sum(cases), 0) into deja
  from seances
  where joueur_id = new.joueur_id
    and (vu_le at time zone 'Europe/Paris')::date = (new.vu_le at time zone 'Europe/Paris')::date
    and id <> new.id;
  new.cases := greatest(0, least(new.cases, 3 - deja));
  return new;
end $$;

create trigger seances_plafond before insert or update on public.seances
for each row execute function public.plafonner_cases();

-- La collection de figurines (profils, saisons, variantes rares).
create table public.figurines (
  joueur_id uuid references public.joueurs on delete cascade default auth.uid(),
  figurine text not null,
  variante text not null default 'normale',
  obtenue_le timestamptz not null default now(),
  primary key (joueur_id, figurine, variante)
);

-- Position sur le plateau d'une saison.
create view public.positions with (security_invoker = true) as
select s.saison_id, s.joueur_id, 1 + sum(s.cases) as case_actuelle
from public.seances s
where s.saison_id is not null
group by s.saison_id, s.joueur_id;

-- Sécurité par ligne
alter table public.joueurs enable row level security;
alter table public.ligues enable row level security;
alter table public.membres enable row level security;
alter table public.saisons enable row level security;
alter table public.seances enable row level security;
alter table public.figurines enable row level security;

create function public.partage_une_ligue(autre uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select autre = auth.uid() or exists (
    select 1 from membres a join membres b on a.ligue_id = b.ligue_id
    where a.joueur_id = auth.uid() and b.joueur_id = autre
  );
$$;

create function public.est_membre(ligue uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from membres where ligue_id = ligue and joueur_id = auth.uid());
$$;

create policy "voir les joueurs de mes ligues" on public.joueurs for select using (public.partage_une_ligue(id));
create policy "gérer mon joueur" on public.joueurs for all using (id = auth.uid()) with check (id = auth.uid());

create policy "voir mes ligues" on public.ligues for select using (public.est_membre(id) or cree_par = auth.uid());
create policy "créer une ligue" on public.ligues for insert with check (cree_par = auth.uid());

create policy "voir les membres de mes ligues" on public.membres for select using (public.est_membre(ligue_id));
create policy "quitter une ligue" on public.membres for delete using (joueur_id = auth.uid());

create policy "voir les saisons de mes ligues" on public.saisons for select using (public.est_membre(ligue_id));

create policy "voir les séances de mes amis" on public.seances for select using (public.partage_une_ligue(joueur_id));
create policy "noter mes séances" on public.seances for all using (joueur_id = auth.uid()) with check (joueur_id = auth.uid());

create policy "voir les figurines de mes amis" on public.figurines for select using (public.partage_une_ligue(joueur_id));

-- Rejoindre une ligue avec son code (sans exposer la liste des ligues).
create function public.rejoindre_ligue(code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare l uuid;
begin
  select id into l from ligues where code_invitation = upper(trim(code));
  if l is null then raise exception 'Code de ligue inconnu'; end if;
  insert into membres (ligue_id, joueur_id) values (l, auth.uid()) on conflict do nothing;
  return l;
end $$;

-- Le créateur entre automatiquement dans sa ligue.
create function public.ajouter_createur() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into membres (ligue_id, joueur_id) values (new.id, new.cree_par);
  return new;
end $$;

create trigger ligues_createur after insert on public.ligues
for each row execute function public.ajouter_createur();
