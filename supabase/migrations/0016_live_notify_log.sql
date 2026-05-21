-- Journal anti-spam pour la notification de réengagement « quelqu'un est
-- en live ». Le fan-out backend (POST /api/notify-live) enregistre ici
-- qui il a notifié, et saute toute personne déjà notifiée dans les
-- dernières 24 h — donc chaque utilisateur reçoit AU PLUS une de ces
-- notifications par jour, quel que soit le nombre d'appels live lancés.

create table if not exists public.live_notify_log (
  user_id          uuid primary key references auth.users(id) on delete cascade,
  last_notified_at timestamptz not null default now()
);

-- Seul le backend (clé service-role) lit ou écrit cette table. RLS
-- activé sans aucune policy → les clients authentifiés normaux ne
-- peuvent ni la lire ni la modifier.
alter table public.live_notify_log enable row level security;
