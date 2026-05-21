-- "Appel live" — file d'attente de mise en relation aléatoire (style
-- Omegle). L'utilisateur tape "Déclencher un appel live", s'inscrit dans
-- public.live_lobby, et la fonction enqueue_live_call() le jumelle
-- atomiquement avec un autre inconnu en attente.
--
-- Pas de notification diffusée à tout le monde : le jumelage est 1:1,
-- donc la file ne peut spammer personne, même avec des milliers
-- d'utilisateurs actifs en même temps.

create table if not exists public.live_lobby (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  status     text not null default 'waiting'
               check (status in ('waiting', 'matched', 'cancelled')),
  room_name  text,
  peer_id    uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  -- Bumpé périodiquement par le client en attente (heartbeat) pour qu'une
  -- longue attente ne le fasse pas sortir de la fenêtre de jumelage.
  seen_at    timestamptz not null default now()
);

-- Une seule ligne de file par utilisateur (enqueue fait delete + insert).
create unique index if not exists live_lobby_user_uidx
  on public.live_lobby (user_id);
create index if not exists live_lobby_status_idx
  on public.live_lobby (status, seen_at);

-- Les évènements UPDATE temps réel ont besoin de la ligne complète pour
-- que le filtre par colonne (user_id) fonctionne de façon fiable.
alter table public.live_lobby replica identity full;

alter table public.live_lobby enable row level security;

-- Un utilisateur ne peut voir / supprimer QUE sa propre ligne de file.
-- Les INSERT et l'UPDATE de jumelage passent tous par la fonction
-- SECURITY DEFINER ci-dessous — il n'y a donc volontairement aucune
-- policy INSERT / UPDATE ici.
drop policy if exists "live_lobby_select_own" on public.live_lobby;
create policy "live_lobby_select_own"
  on public.live_lobby
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "live_lobby_delete_own" on public.live_lobby;
create policy "live_lobby_delete_own"
  on public.live_lobby
  for delete
  to authenticated
  using (auth.uid() = user_id);

-- Publication temps réel — l'hôte en attente s'abonne aux UPDATE de sa
-- propre ligne pour savoir l'instant où un inconnu lui est jumelé.
do $$
begin
  alter publication supabase_realtime add table public.live_lobby;
exception
  when duplicate_object then null;
end$$;

-- Fonction de jumelage. Appelée quand un utilisateur tape "Déclencher un
-- appel live".
--   * Si un autre inconnu récent attend déjà → jumelle les deux lignes,
--     crée un nom de room partagé, renvoie (matched=true, room_name,
--     peer_id).
--   * Sinon → inscrit l'appelant en 'waiting', renvoie matched=false.
--
-- Un verrou consultatif (advisory lock) à portée transaction sérialise
-- toute la section critique : sans lui, deux appelants simultanés
-- pourraient tous deux observer une file vide et rester tous deux en
-- attente à l'infini.
create or replace function public.enqueue_live_call()
returns table (matched boolean, room_name text, peer_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me   uuid := auth.uid();
  v_peer uuid;
  v_room text;
begin
  if v_me is null then
    raise exception 'not authenticated';
  end if;

  perform pg_advisory_xact_lock(hashtext('live_lobby_match')::bigint);

  -- Ménage : supprime les lignes abandonnées que plus personne ne
  -- rafraîchit.
  delete from public.live_lobby
   where seen_at < now() - interval '10 minutes';

  -- Efface toute ligne précédente de l'appelant (attente périmée ou
  -- ancien jumelage).
  delete from public.live_lobby where user_id = v_me;

  -- Le plus ancien autre inconnu encore en attente et vu récemment.
  select l.user_id into v_peer
    from public.live_lobby l
   where l.status = 'waiting'
     and l.user_id <> v_me
     and l.seen_at > now() - interval '75 seconds'
   order by l.created_at asc
   limit 1;

  if v_peer is null then
    -- Personne en attente → on inscrit l'appelant.
    insert into public.live_lobby (user_id, status)
    values (v_me, 'waiting');
    return query select false, null::text, null::uuid;
    return;
  end if;

  -- Jumelage trouvé. Nom de room unique (respecte le regex backend
  -- ^[a-zA-Z0-9_-]{3,64}$).
  v_room := 'live-' || replace(gen_random_uuid()::text, '-', '');

  -- Bascule la ligne du pair en attente → 'matched' : c'est cet UPDATE
  -- qui déclenche l'évènement temps réel côté hôte.
  update public.live_lobby
     set status = 'matched', room_name = v_room,
         peer_id = v_me, seen_at = now()
   where user_id = v_peer;

  -- Enregistre aussi le côté de l'appelant comme jumelé.
  insert into public.live_lobby (user_id, status, room_name, peer_id)
  values (v_me, 'matched', v_room, v_peer);

  return query select true, v_room, v_peer;
end;
$$;

revoke all on function public.enqueue_live_call() from public;
grant execute on function public.enqueue_live_call() to authenticated;

-- Garde fraîche la ligne d'attente de l'appelant tant qu'il reste sur
-- l'écran de recherche, pour qu'une longue attente ne le fasse pas
-- vieillir hors de la fenêtre de jumelage.
create or replace function public.live_lobby_heartbeat()
returns void
language sql
security definer
set search_path = public
as $$
  update public.live_lobby
     set seen_at = now()
   where user_id = auth.uid()
     and status = 'waiting';
$$;

revoke all on function public.live_lobby_heartbeat() from public;
grant execute on function public.live_lobby_heartbeat() to authenticated;

-- Combien d'inconnus attendent en ce moment — alimente le compteur en
-- direct de l'écran "Déclencher un appel live", sans exposer chaque
-- ligne à chaque client. Exclut l'appelant lui-même.
create or replace function public.live_lobby_waiting_count()
returns integer
language sql
security definer
set search_path = public
as $$
  select count(*)::int
    from public.live_lobby
   where status = 'waiting'
     and user_id <> auth.uid()
     and seen_at > now() - interval '75 seconds';
$$;

revoke all on function public.live_lobby_waiting_count() from public;
grant execute on function public.live_lobby_waiting_count() to authenticated;
