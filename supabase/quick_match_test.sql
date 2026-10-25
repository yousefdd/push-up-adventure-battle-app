\set A '''aaaaaaaa-0000-0000-0000-000000000001'''
\set B '''bbbbbbbb-0000-0000-0000-000000000002'''
\set C '''cccccccc-0000-0000-0000-000000000003'''
set role authenticated;
-- 1. A searches alone: gets a waiting public search
select set_config('request.jwt.claim.sub', :A, false) \gset
select '1 A searches' t, status, is_public, fight_secs from quick_match('pushup','Adrian',6,null,180);
-- 2. A searching again keeps the same search, no duplicates
select '2 A again' t, status, (select count(*) from duels where host=:A::uuid and status='waiting') n from quick_match('pushup','Adrian',6,null,180);
-- 3. C searches a different length: not paired
select set_config('request.jwt.claim.sub', :C, false) \gset
select '3 C other length' t, status, fight_secs from quick_match('pushup','Eve',2,null,60);
-- 4. status counts
select '4 status' t, * from matchmaking_status('pushup');
-- 5. B searches 3 min: paired with A, race starts
select set_config('request.jwt.claim.sub', :B, false) \gset
select '5 B paired' t, status, host_name, guest_name, fight_secs, round(extract(epoch from go_at-now())) go from quick_match('pushup','Leon',9,null,180);
-- 6. A's next refresh sees it is live (no new search)
select set_config('request.jwt.claim.sub', :A, false) \gset
select '6 A sees live' t, status, guest_name from duels where host=:A::uuid order by created_at desc limit 1;
-- 7. stale searches are ignored
reset role; update duels set searched_at = now() - interval '1 minute' where host=:C::uuid; set role authenticated;
select set_config('request.jwt.claim.sub', :B, false) \gset
select '7 stale skipped' t, status, host = :B::uuid as own_search from quick_match('pushup','Leon',9,null,60);
-- 8. bad length refused
do $$ begin perform quick_match('pushup','x',1,null,120); exception when others then raise notice '8 rejected: %', sqlerrm; end $$;
-- 9. anon cannot search
reset role; set role anon;
do $$ begin perform quick_match('pushup','x'); exception when others then raise notice '9 anon blocked: %', sqlerrm; end $$;
