-- Ranked play: Elo with eight ranks (the last, Champion, from 2150), gold Cinder Coins and silver coins.
-- Run after schema.sql (Supabase → SQL Editor → paste → Run). Safe to run again.
--
-- Rules
--   Only "Find an opponent" races are ranked; friend codes stay friendly.
--   Elo K: 32 for the first 20 ranked races, then 24. Rating never below 100.
--   Higher ranks climb slower: wins pay less and losses cost more from
--   Platinum up (gain_mult / loss_mult).
--   Below Diamond (rating < 1550) a win pays 3–6 silver coins, a loss costs 2.
--   From Diamond up a win pays 2–4 gold Cinder Coins, a loss costs 1.
--   Daily caps: 30 silver and 10 gold from races; only the first 3 wins a day
--   against the same rival pay. A race with no reps at all is void.
--   Adventure: a cleared world pays 2 silver (worlds 1–7) or 1 gold (world 8
--   up, or Nightmare), at most 5 a day and one every 8 minutes.

create table if not exists public.players (
  id uuid primary key,
  rating int not null default 1000,
  peak_rating int not null default 1000,
  ranked_games int not null default 0,
  wins int not null default 0,
  losses int not null default 0,
  draws int not null default 0,
  coins int not null default 0 check (coins >= 0),    -- gold Cinder Coins
  silver int not null default 0 check (silver >= 0),  -- silver coins
  coins_day date not null default current_date,
  coins_today int not null default 0,
  silver_today int not null default 0,
  adventure_day date not null default current_date,
  adventure_today int not null default 0,
  adventure_last timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.players add column if not exists silver int not null default 0 check (silver >= 0);
alter table public.players add column if not exists silver_today int not null default 0;
alter table public.players enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'players'
                 and policyname = 'players read their own row') then
    create policy "players read their own row" on public.players for select to authenticated using (auth.uid() = id);
  end if;
end $$;
revoke insert, update, delete on public.players from anon, authenticated;

alter table public.duels add column if not exists ranked boolean not null default false;
alter table public.duels add column if not exists host_rating int;
alter table public.duels add column if not exists guest_rating int;
alter table public.duels add column if not exists host_rating_delta int;
alter table public.duels add column if not exists guest_rating_delta int;
alter table public.duels add column if not exists host_coins_delta int;
alter table public.duels add column if not exists guest_coins_delta int;
alter table public.duels add column if not exists host_silver_delta int;
alter table public.duels add column if not exists guest_silver_delta int;

create or replace function public.ensure_player(p_id uuid)
returns public.players language plpgsql security definer set search_path = public as $$
declare me public.players;
begin
  insert into players (id) values (p_id) on conflict (id) do nothing;
  select * into me from players where id = p_id for update;
  if me.coins_day <> current_date then
    update players set coins_day = current_date, coins_today = 0, silver_today = 0 where id = p_id returning * into me;
  end if;
  if me.adventure_day <> current_date then
    update players set adventure_day = current_date, adventure_today = 0 where id = p_id returning * into me;
  end if;
  return me;
end $$;
revoke all on function public.ensure_player(uuid) from public, anon, authenticated;

create or replace function public.my_stats()
returns public.players language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  return ensure_player(auth.uid());
end $$;

create or replace function public.gain_mult(r int) returns numeric language sql immutable set search_path = public as $$
  select case when r < 1400 then 1.0 when r < 1550 then 0.95 when r < 1750 then 0.85 when r < 1950 then 0.75
              when r < 2150 then 0.65 when r < 2400 then 0.55 else 0.5 end $$;
create or replace function public.loss_mult(r int) returns numeric language sql immutable set search_path = public as $$
  select case when r < 1550 then 1.0 when r < 1750 then 1.1 when r < 1950 then 1.2 when r < 2150 then 1.3 else 1.4 end $$;

create or replace function public.race_reward(me public.players, rival_rating int, outcome int, paid boolean,
                                              out gold int, out silver_amt int)
language plpgsql immutable set search_path = public as $$
declare bonus int := least(3, greatest(0, (rival_rating - me.rating) / 100));
begin
  gold := 0; silver_amt := 0;
  if outcome = 1 and paid then
    if me.rating >= 1550 then gold := greatest(0, least(2 + least(bonus, 2), 10 - me.coins_today));
    else silver_amt := greatest(0, least(3 + bonus, 30 - me.silver_today)); end if;
  elsif outcome = -1 then
    if me.rating >= 1550 then gold := -least(1, me.coins); else silver_amt := -least(2, me.silver); end if;
  end if;
end $$;
revoke all on function public.race_reward(public.players, int, int, boolean) from public, anon, authenticated;

create or replace function public.settle_ranked(p_duel uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  d public.duels; h public.players; g public.players;
  score_h numeric; expect_h numeric; raw_h numeric; raw_g numeric;
  dh int; dg int; rh record; rg record; rival_wins int := 0;
begin
  select * into d from duels where id = p_duel for update;
  if not d.ranked or d.guest is null or d.host_rating_delta is not null then return; end if;
  if d.host_reps + d.guest_reps = 0 then
    update duels set host_rating_delta = 0, guest_rating_delta = 0, host_coins_delta = 0, guest_coins_delta = 0,
                     host_silver_delta = 0, guest_silver_delta = 0 where id = p_duel;
    return;
  end if;
  h := ensure_player(d.host);
  g := ensure_player(d.guest);
  score_h := case when d.winner = d.host then 1 when d.winner = d.guest then 0 else 0.5 end;
  expect_h := 1 / (1 + power(10, (g.rating - h.rating) / 400.0));
  raw_h := (case when h.ranked_games < 20 then 32 else 24 end) * (score_h - expect_h);
  raw_g := (case when g.ranked_games < 20 then 32 else 24 end) * ((1 - score_h) - (1 - expect_h));
  dh := round(raw_h * case when raw_h >= 0 then gain_mult(h.rating) else loss_mult(h.rating) end);
  dg := round(raw_g * case when raw_g >= 0 then gain_mult(g.rating) else loss_mult(g.rating) end);
  dh := greatest(100, h.rating + dh) - h.rating;
  dg := greatest(100, g.rating + dg) - g.rating;
  if d.winner is not null then
    select count(*) into rival_wins from duels
     where status = 'finished' and ranked and winner = d.winner and id <> d.id and finished_at >= current_date
       and ((host = d.host and guest = d.guest) or (host = d.guest and guest = d.host));
  end if;
  select * into rh from race_reward(h, g.rating, case when score_h = 1 then 1 when score_h = 0 then -1 else 0 end, rival_wins < 3);
  select * into rg from race_reward(g, h.rating, case when score_h = 0 then 1 when score_h = 1 then -1 else 0 end, rival_wins < 3);
  update players set rating = rating + dh, peak_rating = greatest(peak_rating, rating + dh), ranked_games = ranked_games + 1,
    wins = wins + (score_h = 1)::int, losses = losses + (score_h = 0)::int, draws = draws + (score_h = 0.5)::int,
    coins = coins + rh.gold, silver = silver + rh.silver_amt,
    coins_today = coins_today + greatest(rh.gold, 0), silver_today = silver_today + greatest(rh.silver_amt, 0), updated_at = now()
  where id = d.host;
  update players set rating = rating + dg, peak_rating = greatest(peak_rating, rating + dg), ranked_games = ranked_games + 1,
    wins = wins + (score_h = 0)::int, losses = losses + (score_h = 1)::int, draws = draws + (score_h = 0.5)::int,
    coins = coins + rg.gold, silver = silver + rg.silver_amt,
    coins_today = coins_today + greatest(rg.gold, 0), silver_today = silver_today + greatest(rg.silver_amt, 0), updated_at = now()
  where id = d.guest;
  update duels set host_rating = h.rating, guest_rating = g.rating, host_rating_delta = dh, guest_rating_delta = dg,
                   host_coins_delta = rh.gold, guest_coins_delta = rg.gold,
                   host_silver_delta = rh.silver_amt, guest_silver_delta = rg.silver_amt
   where id = p_duel;
end $$;
revoke all on function public.settle_ranked(uuid) from public, anon, authenticated;

-- Either player: close the race once time is up, record the winner and, for
-- a ranked race, move both ratings and coins. Safe to call from both phones.
create or replace function public.finish_duel(p_duel uuid)
returns public.duels language plpgsql security definer set search_path = public as $$
declare row public.duels;
begin
  select * into row from duels where id = p_duel for update;
  if not found or auth.uid() not in (row.host, row.guest) then raise exception 'not your duel'; end if;
  if row.status = 'live' and now() >= row.go_at + make_interval(secs => row.fight_secs + 2) then
    update duels set status = 'finished', finished_at = now(),
      winner = case when host_reps > guest_reps then host when guest_reps > host_reps then guest end
    where id = p_duel;
    perform settle_ranked(p_duel);
    select * into row from duels where id = p_duel;
  end if;
  return row;
end $$;

-- Matchmade races are ranked; both ratings are recorded when they start.
create or replace function public.mark_ranked()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'live' and old.status = 'waiting' and new.is_public and new.guest is not null then
    new.ranked := true;
    new.host_rating := (ensure_player(new.host)).rating;
    new.guest_rating := (ensure_player(new.guest)).rating;
  end if;
  return new;
end $$;
revoke all on function public.mark_ranked() from public, anon, authenticated;
create or replace trigger duels_mark_ranked before update on public.duels for each row execute function public.mark_ranked();

-- A cleared adventure world. The phone cannot prove it played, so this is
-- small and rate limited.
create or replace function public.claim_adventure_reward(p_world int, p_hard boolean default false)
returns table (granted int, coins int, silver int, gold boolean)
language plpgsql security definer set search_path = public as $$
declare me public.players; amount int; is_gold boolean;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  me := ensure_player(auth.uid());
  is_gold := coalesce(p_world, 1) >= 8 or coalesce(p_hard, false);
  amount := case when is_gold then 1 else 2 end;
  if me.adventure_today >= 5 or (me.adventure_last is not null and me.adventure_last > now() - interval '8 minutes') then
    amount := 0;
  end if;
  update players p set
    coins = p.coins + case when is_gold then amount else 0 end,
    silver = p.silver + case when is_gold then 0 else amount end,
    adventure_today = p.adventure_today + (amount > 0)::int,
    adventure_last = case when amount > 0 then now() else p.adventure_last end,
    updated_at = now()
  where p.id = auth.uid()
  returning p.coins, p.silver into me.coins, me.silver;
  return query select amount, me.coins, me.silver, is_gold;
end $$;

revoke all on function public.my_stats() from public, anon;
revoke all on function public.claim_adventure_reward(int, boolean) from public, anon;
grant execute on function public.my_stats() to authenticated;
grant execute on function public.claim_adventure_reward(int, boolean) to authenticated;
revoke all on function public.finish_duel(uuid) from public, anon;
grant execute on function public.finish_duel(uuid) to authenticated;
