-- Aura : les mesures de rétention, anonymes.
-- À lancer dans l'éditeur SQL de Supabase, après 0001 et 0002.
--
-- Chaque appareil a un compte anonyme (pas d'e-mail, pas de pseudo requis).
-- L'appli envoie de petits événements : ouverture (une fois par jour), carte
-- jouée, billet validé, Plan du jour, Duel, Bluff. Rien d'autre.

create table if not exists public.evenements (
  id bigint generated always as identity primary key,
  joueur_id uuid not null default auth.uid() references auth.users on delete cascade,
  type text not null check (type in ('ouverture', 'carte_jouee', 'billet', 'plan_du_jour', 'duel', 'bluff')),
  donnees jsonb not null default '{}'::jsonb,
  cree_le timestamptz not null default now()
);

create index if not exists evenements_joueur on public.evenements (joueur_id, cree_le);

alter table public.evenements enable row level security;

drop policy if exists "envoyer mes événements" on public.evenements;
create policy "envoyer mes événements" on public.evenements
  for insert with check (joueur_id = auth.uid());

-- Les quatre chiffres, à lire dans l'éditeur SQL : select * from public.mesures;
-- (vue réservée à l'administrateur : ni l'appli ni les joueurs ne la voient).
create or replace view public.mesures as
with premieres as (
  select joueur_id, min(cree_le)::date as jour0
  from evenements where type = 'ouverture'
  group by joueur_id
),
retours as (
  select p.joueur_id, p.jour0,
    bool_or(e.cree_le::date = p.jour0 + 1) as j1,
    bool_or(e.cree_le::date between p.jour0 + 7 and p.jour0 + 13) as j7,
    bool_or(e.cree_le::date between p.jour0 + 30 and p.jour0 + 44) as j30
  from premieres p
  join evenements e on e.joueur_id = p.joueur_id and e.type = 'ouverture'
  group by p.joueur_id, p.jour0
)
select
  count(*) as joueurs,
  round(100.0 * count(*) filter (where j1) / nullif(count(*) filter (where jour0 <= current_date - 1), 0), 1) as retour_j1_pourcent,
  round(100.0 * count(*) filter (where j7) / nullif(count(*) filter (where jour0 <= current_date - 7), 0), 1) as retour_j7_pourcent,
  round(100.0 * count(*) filter (where j30) / nullif(count(*) filter (where jour0 <= current_date - 30), 0), 1) as retour_j30_pourcent,
  (select round(100.0 * count(*) filter (where type = 'billet') / nullif(count(*) filter (where type = 'carte_jouee'), 0), 1)
     from evenements) as cartes_devenues_billets_pourcent
from retours;

revoke all on public.mesures from anon, authenticated;
