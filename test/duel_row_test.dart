import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:repraid/engine/exercise.dart';
import 'package:repraid/modes/online/duel_models.dart';
import 'package:repraid/modes/online/duel_service.dart';

// Rows captured from schema.sql running on PostgreSQL 16 (row_to_json of what
// join_duel / finish_duel return), so the app's field names and types are
// checked against the real table, not a hand-written guess.
const live =
    r'{"id":"435d18f2-f654-4248-a960-f424c8f59c87","code":"4F3R","exercise":"kneePushup","status":"live","host":"aaaaaaaa-0000-0000-0000-000000000001","host_name":"Adrian","host_level":6,"host_reps":0,"guest":"bbbbbbbb-0000-0000-0000-000000000002","guest_name":"Leon","guest_level":9,"guest_reps":0,"lead_secs":5,"fight_secs":60,"go_at":"2026-10-21T19:11:06.554875+00:00","winner":null,"created_at":"2026-10-21T19:10:58.481204+00:00","finished_at":null}';
const done =
    r'{"id":"435d18f2-f654-4248-a960-f424c8f59c87","code":"4F3R","exercise":"kneePushup","status":"finished","host":"aaaaaaaa-0000-0000-0000-000000000001","host_name":"Adrian","host_level":6,"host_reps":14,"guest":"bbbbbbbb-0000-0000-0000-000000000002","guest_name":"Leon","guest_level":9,"guest_reps":17,"lead_secs":5,"fight_secs":60,"go_at":"2026-10-21T19:09:55.607097+00:00","winner":"bbbbbbbb-0000-0000-0000-000000000002","created_at":"2026-10-21T19:10:58.481204+00:00","finished_at":"2026-10-21T19:10:58.607097+00:00"}';

const peeked = r'{"host_name":"Adrian","host_level":6,"host_avatar":null,"exercise":"pushup","fight_secs":300}';

const host = 'aaaaaaaa-0000-0000-0000-000000000001';
const guest = 'bbbbbbbb-0000-0000-0000-000000000002';

void main() {
  test('parses a live duel row', () {
    final row = DuelRow.fromJson(jsonDecode(live));
    expect(row.code, '4F3R');
    expect(row.exercise, ExerciseType.kneePushup);
    expect(row.isLive, isTrue);
    expect(row.goAt, isNotNull);
    expect(row.leadSecs, 5);
    expect(row.fightSecs, 60);
  });

  test('each phone sees itself as "me" in blue', () {
    final row = DuelRow.fromJson(jsonDecode(live));
    final hostView = row.boutFor(host);
    final guestView = row.boutFor(guest);
    expect(hostView.me.name, 'Adrian');
    expect(hostView.opponent.name, 'Leon');
    expect(hostView.opponentId, guest);
    expect(guestView.me.name, 'Leon');
    expect(guestView.me.level, 9);
    expect(guestView.opponent.name, 'Adrian');
    expect(guestView.opponentId, host);
    expect(guestView.exercise, ExerciseType.kneePushup);
  });

  test('server verdict reads correctly from both sides', () {
    final row = DuelRow.fromJson(jsonDecode(done));
    expect(row.isFinished, isTrue);
    final h = row.resultFor(host);
    final g = row.resultFor(guest);
    expect(h.outcome, DuelOutcome.loss);
    expect(h.myReps, 14);
    expect(h.opponentReps, 17);
    expect(g.outcome, DuelOutcome.win);
    expect(g.myReps, 17);
    expect(g.opponentReps, 14);
  });

  test('an invite shows who sent it and the agreed race length', () {
    final invite = DuelInvite.fromJson('K7QM', jsonDecode(peeked));
    expect(invite.hostName, 'Adrian');
    expect(invite.fightSecs, 300);
    expect(invite.exercise, ExerciseType.pushup);
    expect(raceLengths, [60, 180, 300]);
    expect(raceLengths.map(raceLabel), ['1 min', '3 min', '5 min']);
  });
}
