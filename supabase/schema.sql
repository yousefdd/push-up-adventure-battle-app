-- RepRaid online duels: two friends, one invite code, one 60-second race.
--
-- Paste this whole file into Supabase → SQL Editor → Run, once.
-- Also enable Authentication → Sign In / Providers → "Allow anonymous sign-ins".
--
-- Players never write the table directly. Every change goes through the
-- functions below, which run as the table owner and check who is calling,
-- so a player can only ever touch their own side of their own duel.


create table if not exists public.duels (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique,
  exercise     text not null check (exercise in ('pushup', 'kneePushup')),
  status       text not null default 'waiting'
               check (status in ('waiting', 'live', 'finished', 'cancelled')),

  host         uuid not null,
  host_name    text not null,
  host_level   int  not null default 1,
  host_reps    int  not null default 0,
  -- Profile picture: a small JPEG as base64 (the app sends ~256 px).
  host_avatar  text check (host_avatar is null or length(host_avatar) <= 60000),

  guest        uuid,
  guest_name   text,
  guest_level  int,
  guest_reps   int  not null default 0,
  guest_avatar text check (guest_avatar is null or length(guest_avatar) <= 60000),

  lead_secs    int  not null default 5,
  fight_secs   int  not null default 60,
  -- The instant the race itself starts ("GO!"); the countdown runs for
  -- lead_secs before it. Set by the server so both phones agree.
  go_at        timestamptz,

  winner       uuid,          -- null on a draw
  created_at   timestamptz not null default now(),
  finished_at  timestamptz
);

alter table public.duels add column if not exists host_avatar text
  check (host_avatar is null or length(host_avatar) <= 60000);
alter table public.duels add column if not exists guest_avatar text
  check (guest_avatar is null or length(guest_avatar) <= 60000);

-- A race is 1, 3 or 5 minutes, agreed before it starts.
alter table public.duels drop constraint if exists duels_fight_secs_len;
alter table public.duels add constraint duels_fight_secs_len check (fight_secs in (60, 180, 300));

create index if not exists duels_waiting_code on public.duels (code)
  where status = 'waiting';

alter table public.duels enable row level security;

-- Each player can read only the duels they are in. Realtime row updates use
-- this same rule, so nobody can watch someone else's duel.
drop policy if exists "players read their duels" on public.duels;
create policy "players read their duels" on public.duels
  for select to authenticated
  using (auth.uid() = host or auth.uid() = guest);

revoke insert, update, delete on public.duels from anon, authenticated;

-- Live score updates reach the other phone through Realtime.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'duels'
  ) then
    alter publication supabase_realtime add table public.duels;
  end if;
end $$;

-- Server clock, so both phones can line their countdowns up exactly.
create or replace function public.server_time()
returns timestamptz
language sql stable set search_path = public
as $$ select now() $$;

-- The picture parameter changed the signatures; drop the old ones so the
-- calls are not ambiguous on a project that ran an earlier version.
drop function if exists public.create_duel(text, text, int);
drop function if exists public.create_duel(text, text, int, text);
drop function if exists public.join_duel(text, text, int);
drop function if exists public.join_duel(text, text, int, text);

-- Host: open a duel and get a 4-letter invite code.
create or replace function public.create_duel(
  p_exercise text, p_name text, p_level int default 1, p_avatar text default null, p_secs int default 60)
returns public.duels
language plpgsql security definer set search_path = public
as $$
declare
  -- No 0/O or 1/I/L, so a code read aloud can't be mistyped.
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  new_code text;
  row public.duels;
begin
  if auth.uid() is null then
    raise exception 'sign in first';
  end if;

  -- One open invite per player: close any earlier one still waiting.
  update duels set status = 'cancelled'
   where host = auth.uid() and status = 'waiting';

  loop
    new_code := '';
    for i in 1..4 loop
      new_code := new_code
        || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from duels where code = new_code);
  end loop;

  if length(p_avatar) > 60000 then
    raise exception 'picture too large';
  end if;
  if coalesce(p_secs, 60) not in (60, 180, 300) then
    raise exception 'a race is 1, 3 or 5 minutes';
  end if;

  insert into duels (code, exercise, host, host_name, host_level, host_avatar, fight_secs)
  values (new_code, p_exercise, auth.uid(),
          left(coalesce(nullif(trim(p_name), ''), 'Player'), 20),
          greatest(coalesce(p_level, 1), 1), p_avatar, coalesce(p_secs, 60))
  returning * into row;
  return row;
end $$;

-- Guest: look at an invite before accepting it — who sent it, which
-- exercise and how long the race is. Only waiting invites, nothing private.
create or replace function public.peek_duel(p_code text)
returns table (host_name text, host_level int, host_avatar text, exercise text, fight_secs int)
language sql security definer set search_path = public stable
as $$
  select d.host_name, d.host_level, d.host_avatar, d.exercise, d.fight_secs
    from duels d
   where d.code = upper(trim(p_code)) and d.status = 'waiting'
     and d.created_at > now() - interval '30 minutes'
   limit 1;
$$;

-- Guest: join with the code. Starts the race for both players.
-- p_secs is the length the guest agreed to; if the host changed it since,
-- the join is refused so nobody races a length they did not accept.
create or replace function public.join_duel(
  p_code text, p_name text, p_level int default 1, p_avatar text default null, p_secs int default null)
returns public.duels
language plpgsql security definer set search_path = public
as $$
declare
  row public.duels;
begin
  if auth.uid() is null then
    raise exception 'sign in first';
  end if;

  select * into row from duels
   where code = upper(trim(p_code)) and status = 'waiting'
     and created_at > now() - interval '30 minutes'
   for update;

  if not found then
    raise exception 'code not found or already used';
  end if;
  if length(p_avatar) > 60000 then
    raise exception 'picture too large';
  end if;
  if row.host = auth.uid() then
    raise exception 'that is your own code — send it to your friend';
  end if;
  if p_secs is not null and p_secs <> row.fight_secs then
    raise exception 'the race length changed — look at the invite again';
  end if;

  update duels set
    guest       = auth.uid(),
    guest_name  = left(coalesce(nullif(trim(p_name), ''), 'Player'), 20),
    guest_level = greatest(coalesce(p_level, 1), 1),
    guest_avatar = p_avatar,
    status      = 'live',
    -- 3 s for both phones to open the race screen, then the countdown.
    go_at       = now() + make_interval(secs => 3 + row.lead_secs)
  where id = row.id
  returning * into row;
  return row;
end $$;

-- Either player: report my verified rep count. Monotonic, only during the
-- race (plus a short grace for the last packet), and capped at a human pace
-- of 2 reps per second so an edited client can't post an impossible score.
create or replace function public.report_reps(p_duel uuid, p_reps int)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  row public.duels;
  elapsed double precision;
  allowed int;
begin
  select * into row from duels where id = p_duel for update;
  if not found or row.status <> 'live' or row.go_at is null then
    return;
  end if;

  elapsed := extract(epoch from (now() - row.go_at));
  if elapsed < 0 or elapsed > row.fight_secs + 3 then
    return;
  end if;
  allowed := least(greatest(p_reps, 0), ceil(elapsed * 2)::int);

  if auth.uid() = row.host then
    update duels set host_reps = greatest(host_reps, allowed) where id = p_duel;
  elsif auth.uid() = row.guest then
    update duels set guest_reps = greatest(guest_reps, allowed) where id = p_duel;
  end if;
end $$;

-- finish_duel is defined in ranked.sql (run it after this file).

-- Host: withdraw an invite nobody has used yet.
create or replace function public.cancel_duel(p_duel uuid)
returns void
language sql security definer set search_path = public
as $$
  update duels set status = 'cancelled'
   where id = p_duel and host = auth.uid() and status = 'waiting';
$$;

-- ------------------------------------------------------------ quick match
-- "Find an opponent": no code. Players searching for the same exercise and
-- race length are paired by the server. A search is a public waiting duel
-- that its owner refreshes every few seconds; one that stops refreshing
-- (app closed, phone offline) is ignored after 20 s.
alter table public.duels add column if not exists is_public boolean not null default false;
alter table public.duels add column if not exists searched_at timestamptz;
create index if not exists duels_matchmaking on public.duels (exercise, fight_secs, created_at)
  where status = 'waiting' and is_public;

-- Search, or keep searching. Returns either a live duel (you were paired:
-- start the race) or your own waiting search (call again in a few seconds).
-- The newer search always joins the older one, so two players searching at
-- the same instant never lock each other.
create or replace function public.quick_match(
  p_exercise text, p_name text, p_level int default 1, p_avatar text default null, p_secs int default 60)
returns public.duels
language plpgsql security definer set search_path = public
as $$
declare
  mine public.duels;
  other public.duels;
  secs int := coalesce(p_secs, 60);
begin
  if auth.uid() is null then
    raise exception 'sign in first';
  end if;
  if secs not in (60, 180, 300) then
    raise exception 'a race is 1, 3 or 5 minutes';
  end if;
  if length(p_avatar) > 60000 then
    raise exception 'picture too large';
  end if;

  select * into mine from duels
   where host = auth.uid() and status = 'waiting' and is_public
     and exercise = p_exercise and fight_secs = secs
   order by created_at desc limit 1;

  select * into other from duels
   where status = 'waiting' and is_public
     and exercise = p_exercise and fight_secs = secs
     and host <> auth.uid()
     and searched_at > now() - interval '20 seconds'
     and (mine.id is null or created_at < mine.created_at)
   order by created_at
   limit 1
   for update skip locked;

  if other.id is not null then
    -- Paired: close every other open search or invite of mine, join theirs.
    update duels set status = 'cancelled' where host = auth.uid() and status = 'waiting';
    update duels set
      guest        = auth.uid(),
      guest_name   = left(coalesce(nullif(trim(p_name), ''), 'Player'), 20),
      guest_level  = greatest(coalesce(p_level, 1), 1),
      guest_avatar = p_avatar,
      status       = 'live',
      go_at        = now() + make_interval(secs => 3 + other.lead_secs)
    where id = other.id
    returning * into other;
    return other;
  end if;

  if mine.id is not null then
    update duels set searched_at = now() where id = mine.id returning * into mine;
    return mine;
  end if;

  update duels set status = 'cancelled' where host = auth.uid() and status = 'waiting';
  insert into duels (code, exercise, host, host_name, host_level, host_avatar, fight_secs, is_public, searched_at)
  values ('Q' || upper(substr(md5(gen_random_uuid()::text), 1, 9)), p_exercise, auth.uid(),
          left(coalesce(nullif(trim(p_name), ''), 'Player'), 20),
          greatest(coalesce(p_level, 1), 1), p_avatar, secs, true, now())
  returning * into mine;
  return mine;
end $$;

-- How busy matchmaking is right now, for "3 searching · 2 racing".
create or replace function public.matchmaking_status(p_exercise text default null)
returns table (searching int, racing int)
language sql security definer set search_path = public stable
as $$
  select
    (select count(distinct host)::int from duels
      where status = 'waiting' and is_public and searched_at > now() - interval '20 seconds'
        and (p_exercise is null or exercise = p_exercise)),
    (select count(*)::int * 2 from duels
      where status = 'live' and go_at > now() - interval '6 minutes'
        and (p_exercise is null or exercise = p_exercise));
$$;

revoke all on function public.create_duel(text, text, int, text, int) from public, anon;
revoke all on function public.join_duel(text, text, int, text, int) from public, anon;
revoke all on function public.peek_duel(text) from public, anon;
revoke all on function public.report_reps(uuid, int) from public, anon;
revoke all on function public.cancel_duel(uuid) from public, anon;
grant execute on function public.create_duel(text, text, int, text, int) to authenticated;
grant execute on function public.join_duel(text, text, int, text, int) to authenticated;
grant execute on function public.peek_duel(text) to authenticated;
grant execute on function public.report_reps(uuid, int) to authenticated;
grant execute on function public.cancel_duel(uuid) to authenticated;
grant execute on function public.server_time() to anon, authenticated;
revoke all on function public.quick_match(text, text, int, text, int) from public, anon;
revoke all on function public.matchmaking_status(text) from public, anon;
grant execute on function public.quick_match(text, text, int, text, int) to authenticated;
grant execute on function public.matchmaking_status(text) to authenticated;

-- ------------------------------------------------------------ ranked play
-- Ratings, ranks, coins and finish_duel live in ranked.sql: run it next.
