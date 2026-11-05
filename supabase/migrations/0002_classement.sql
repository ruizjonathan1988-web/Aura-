-- Aura : le classement du mois dans une ligue.
-- À lancer dans l'éditeur SQL de Supabase, après 0001_ligues.sql.
--
-- Le plateau est celui du mois : chaque joueur part de la case 1 le 1er et
-- avance avec ses séances du mois (3 cases par jour au plus, déjà plafonnées
-- à l'insertion). La même position vaut dans toutes ses ligues.

create or replace function public.classement(ligue uuid)
returns table (joueur_id uuid, pseudo text, profil text, case_actuelle int, seances int)
language sql stable security definer set search_path = public as $$
  with mois as (
    select s.joueur_id as jid, s.cases
    from seances s
    where date_trunc('month', s.vu_le at time zone 'Europe/Paris')
        = date_trunc('month', now() at time zone 'Europe/Paris')
  )
  select j.id,
         j.pseudo,
         j.profil,
         least(30, 1 + coalesce(sum(m.cases), 0))::int,
         count(m.jid)::int
  from membres mb
  join joueurs j on j.id = mb.joueur_id
  left join mois m on m.jid = j.id
  where mb.ligue_id = ligue
    and public.est_membre(ligue)
  group by j.id, j.pseudo, j.profil
  order by 4 desc, 2;
$$;

-- Les comptes sont anonymes (un pseudo, pas d'e-mail) : penser à activer
-- « Allow anonymous sign-ins » dans Authentication > Sign In / Providers.
