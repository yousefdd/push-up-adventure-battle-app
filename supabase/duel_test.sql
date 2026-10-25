\set A '''aaaaaaaa-0000-0000-0000-000000000001'''
\set B '''bbbbbbbb-0000-0000-0000-000000000002'''
\set C '''cccccccc-0000-0000-0000-000000000003'''
\pset footer off
-- 1. host creates
set role authenticated; select set_config('request.jwt.claim.sub', :A, false) \gset
select id as duel, code from create_duel('pushup', 'Adrian', 6) \gset
select set_config('t.duel', :'duel', false) \gset
select '1 create' as test, length(:'code') = 4 as code_is_4, (select status from duels where id = :'duel') as status;
-- 2. host cannot join own code
select set_config('t.code', :'code', false) \gset
do $$ begin perform join_duel(current_setting('t.code'), 'x'); exception when others then raise notice '2 own-code rejected: %', sqlerrm; end $$;
-- 3. wrong code
select set_config('request.jwt.claim.sub', :B, false) \gset
do $$ begin perform join_duel('ZZZZ', 'Leon'); exception when others then raise notice '3 bad code rejected: %', sqlerrm; end $$;
-- 4. friend joins (lower-case code works)
select '4 join' as test, status, guest_name, round(extract(epoch from go_at - now())) as secs_to_go from join_duel(lower(:'code'), 'Leon', 9);
-- 5. same code cannot be used twice
select set_config('request.jwt.claim.sub', :C, false) \gset
do $$ begin perform join_duel(current_setting('t.code'), 'Eve'); exception when others then raise notice '5 reused code rejected: %', sqlerrm; end $$;
-- 6. a stranger cannot see the duel
select '6 stranger reads' as test, count(*) as rows_visible from duels;
-- 7. players cannot write the table directly
select set_config('request.jwt.claim.sub', :B, false) \gset
do $$ begin update duels set guest_reps = 999; exception when others then raise notice '7 direct update blocked: %', sqlerrm; end $$;
-- 8. reps before GO are ignored
select report_reps(:'duel', 5);
select '8 before go' as test, guest_reps from duels where id = :'duel';
-- 9. fast-forward: race started 10 s ago
reset role; update duels set go_at = now() - interval '10 seconds' where id = :'duel'; set role authenticated;
select report_reps(:'duel', 7);
select set_config('request.jwt.claim.sub', :A, false) \gset
select report_reps(:'duel', 100);  -- impossible: capped at 2/s
select '9 live scores' as test, host_reps as a_capped, guest_reps as b from duels where id = :'duel';
-- 10. scores never go down
select report_reps(:'duel', 3);
select '10 monotonic' as test, host_reps from duels where id = :'duel';
-- 11. finishing early does nothing
select '11 early finish' as test, status from finish_duel(:'duel');
-- 12. after the 60 s (+grace) the server settles the winner
reset role; update duels set go_at = now() - interval '63 seconds' where id = :'duel'; set role authenticated;
select '12 finish' as test, status, host_reps, guest_reps, winner = :A::uuid as host_won from finish_duel(:'duel');
-- 13. late reps after the end are ignored
select report_reps(:'duel', 50);
select '13 after end' as test, host_reps from duels where id = :'duel';
-- 14. a stranger cannot finish someone else's duel
select set_config('request.jwt.claim.sub', :C, false) \gset
do $$ begin perform finish_duel(current_setting('t.duel')::uuid); exception when others then raise notice '14 stranger finish blocked: %', sqlerrm; end $$;
-- 15. signed-out (anon) callers cannot create duels
reset role; set role anon;
do $$ begin perform create_duel('pushup','x'); exception when others then raise notice '15 anon blocked: %', sqlerrm; end $$;
-- 16. pictures travel with the duel
reset role; set role authenticated; select set_config('request.jwt.claim.sub', :A, false) \gset
select id as duel2, code as code2 from create_duel('pushup', 'Adrian', 6, 'aGVsbG8=') \gset
select set_config('request.jwt.claim.sub', :B, false) \gset
select '16 avatars' as test, host_avatar, guest_avatar from join_duel(:'code2', 'Leon', 9, 'd29ybGQ=');
-- 17. an oversized picture is refused
do $$ begin perform create_duel('pushup', 'Big', 1, repeat('A', 60001)); exception when others then raise notice '17 big picture rejected: %', sqlerrm; end $$;
-- 18. no picture still works
select '18 no picture' as test, host_avatar is null as empty from create_duel('pushup', 'Plain');
-- 19. the host picks 3 minutes; the guest sees it before accepting
select set_config('request.jwt.claim.sub', :A, false) \gset
select id as duel3, code as code3 from create_duel('pushup', 'Adrian', 6, null, 180) \gset
select set_config('request.jwt.claim.sub', :B, false) \gset
select '19 peek' as test, host_name, fight_secs from peek_duel(lower(:'code3'));
-- 20. accepting a different length than the invite is refused
select set_config('t.code3', :'code3', false) \gset
do $$ begin perform join_duel(current_setting('t.code3'), 'Leon', 9, null, 60); exception when others then raise notice '20 wrong length rejected: %', sqlerrm; end $$;
-- 21. accepting the agreed length starts a 3-minute race
select '21 agreed join' as test, status, fight_secs from join_duel(:'code3', 'Leon', 9, null, 180);
-- 22. only 1, 3 or 5 minutes
select set_config('request.jwt.claim.sub', :A, false) \gset
do $$ begin perform create_duel('pushup', 'Adrian', 6, null, 120); exception when others then raise notice '22 2-minute race rejected: %', sqlerrm; end $$;
-- 23. a 5-minute race takes reps until its own end, not the 1-minute mark
select id as duel5, code as code5 from create_duel('pushup', 'Adrian', 6, null, 300) \gset
select set_config('request.jwt.claim.sub', :B, false) \gset
select status from join_duel(:'code5', 'Leon', 9, null, 300) \gset
reset role; update duels set go_at = now() - interval '200 seconds' where id = :'duel5'; set role authenticated;
select report_reps(:'duel5', 120);
select '23 five-minute reps' as test, guest_reps from duels where id = :'duel5';
-- 24. peeking a used code finds nothing
select '24 peek used' as test, count(*) from peek_duel(:'code3');
