import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../engine/exercise.dart';
import '../../i18n/i18n.dart';
import '../../online/ranked.dart';
import 'duel_models.dart';

/// The race lengths two players can agree on, in seconds.
const raceLengths = [60, 180, 300];

/// "1 min", "3 min", "5 min".
String raceLabel(int secs) => I18n.isAr
    ? const {60: 'دقيقة', 180: '3 دقائق', 300: '5 دقائق'}[secs] ?? '${secs ~/ 60} د'
    : tr('{n} min', {'n': secs ~/ 60});

/// An invite seen before accepting it: who sent it and how long the race is.
class DuelInvite {
  DuelInvite.fromJson(this.code, Map<String, dynamic> j)
      : hostName = j['host_name'] as String,
        hostLevel = (j['host_level'] as num).toInt(),
        hostPhoto = DuelRow._photo(j['host_avatar']),
        exercise = ExerciseType.values.byName(j['exercise'] as String),
        fightSecs = (j['fight_secs'] as num).toInt();

  final String code, hostName;
  final int hostLevel, fightSecs;
  final Uint8List? hostPhoto;
  final ExerciseType exercise;
}

/// One row of the `duels` table (see supabase/schema.sql).
class DuelRow {
  DuelRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        code = j['code'] as String,
        exercise = ExerciseType.values.byName(j['exercise'] as String),
        status = j['status'] as String,
        host = j['host'] as String,
        hostName = j['host_name'] as String,
        hostLevel = (j['host_level'] as num).toInt(),
        hostReps = (j['host_reps'] as num).toInt(),
        guest = j['guest'] as String?,
        guestName = j['guest_name'] as String?,
        guestLevel = (j['guest_level'] as num?)?.toInt(),
        guestReps = (j['guest_reps'] as num).toInt(),
        hostPhoto = _photo(j['host_avatar']),
        guestPhoto = _photo(j['guest_avatar']),
        leadSecs = (j['lead_secs'] as num).toInt(),
        fightSecs = (j['fight_secs'] as num).toInt(),
        goAt = j['go_at'] == null ? null : DateTime.parse(j['go_at'] as String),
        winner = j['winner'] as String?,
        ranked = j['ranked'] as bool? ?? false,
        hostRating = (j['host_rating'] as num?)?.toInt(),
        guestRating = (j['guest_rating'] as num?)?.toInt(),
        hostRatingDelta = (j['host_rating_delta'] as num?)?.toInt(),
        guestRatingDelta = (j['guest_rating_delta'] as num?)?.toInt(),
        hostGoldDelta = (j['host_coins_delta'] as num?)?.toInt(),
        guestGoldDelta = (j['guest_coins_delta'] as num?)?.toInt(),
        hostSilverDelta = (j['host_silver_delta'] as num?)?.toInt(),
        guestSilverDelta = (j['guest_silver_delta'] as num?)?.toInt();

  final String id, code, status, host, hostName;
  final ExerciseType exercise;
  final int hostLevel, hostReps, guestReps, leadSecs, fightSecs;
  final String? guest, guestName, winner;
  final int? guestLevel;
  final Uint8List? hostPhoto, guestPhoto;

  /// Matchmade: the server moves both ratings and embers when it settles.
  final bool ranked;
  final int? hostRating, guestRating, hostRatingDelta, guestRatingDelta, hostGoldDelta, guestGoldDelta, hostSilverDelta, guestSilverDelta;

  /// My rating before the race, for the race screen.
  int? ratingOf(String player) => player == host ? hostRating : guestRating;

  static Uint8List? _photo(Object? b64) {
    if (b64 is! String || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Server instant the race itself starts ("GO!").
  final DateTime? goAt;

  bool get isLive => status == 'live';
  bool get isFinished => status == 'finished';

  int repsOf(String player) => player == host ? hostReps : guestReps;

  /// The bout as seen from [me]: my side is always "me", whichever role I
  /// have, so the screen shows me in blue on the left on both phones.
  DuelBout boutFor(String me) {
    final iAmHost = me == host;
    DuelPlayer side(bool hostSide, String avatar) => DuelPlayer(
          name: hostSide ? hostName : (guestName ?? tr('Friend')),
          level: hostSide ? hostLevel : (guestLevel ?? 1),
          avatar: avatar,
          photo: hostSide ? hostPhoto : guestPhoto,
        );
    return DuelBout(
      boutId: id,
      myId: me,
      opponentId: iAmHost ? (guest ?? '') : host,
      exercise: exercise,
      window: DuelWindow(fightSecs: fightSecs, leadSecs: leadSecs),
      me: side(iAmHost, 'assets/rc/Adrian.png'),
      opponent: side(!iAmHost, 'assets/rc/Leon.png'),
    );
  }

  /// Final result from [me]'s side, as the server decided it.
  DuelResult resultFor(String me) {
    final mine = repsOf(me);
    final theirs = me == host ? guestReps : hostReps;
    final outcome = winner == null ? DuelOutcome.draw : (winner == me ? DuelOutcome.win : DuelOutcome.loss);
    final iAmHost = me == host;
    final before = iAmHost ? hostRating : guestRating;
    final delta = iAmHost ? hostRatingDelta : guestRatingDelta;
    final gold = iAmHost ? hostGoldDelta : guestGoldDelta;
    final silver = iAmHost ? hostSilverDelta : guestSilverDelta;
    return DuelResult(
      outcome: outcome,
      myReps: mine,
      opponentReps: theirs,
      ranked: ranked,
      rank: ranked && before != null && delta != null
          ? RankChange(before: before, delta: delta, gold: gold ?? 0, silver: silver ?? 0)
          : null,
    );
  }
}

/// Online duels between two friends over Supabase.
///
/// The host creates a duel and gets a 4-letter code; the friend joins with it.
/// The server then sets one start instant for both phones, each phone reports
/// its verified rep count as it changes, and Realtime pushes the row back so
/// the other phone's counter moves. When time is up the server settles the
/// winner with the same rules for both sides.
class DuelService {
  DuelService(this.supabase);
  final SupabaseClient supabase;

  /// server clock − this phone's clock, measured by [syncClock].
  Duration _clockOffset = Duration.zero;

  String get myId => supabase.auth.currentUser!.id;

  /// Signs in without an account (Supabase anonymous sign-in) the first time.
  Future<void> signIn() async {
    if (supabase.auth.currentUser == null) {
      await supabase.auth.signInAnonymously();
    }
  }

  /// Measures the gap between the server clock and this phone's clock, so a
  /// server start time can be turned into the same instant on both phones.
  Future<void> syncClock() async {
    final sent = DateTime.now();
    final server = DateTime.parse(await supabase.rpc('server_time') as String);
    final received = DateTime.now();
    final midway = sent.add(received.difference(sent) ~/ 2);
    _clockOffset = server.difference(midway);
  }

  /// A server instant expressed on this phone's clock.
  DateTime toLocal(DateTime serverInstant) => serverInstant.toLocal().subtract(_clockOffset);

  /// Opens an invite for a race of [secs] (one of [raceLengths]).
  Future<DuelRow> create(ExerciseType exercise, String name, int level, {String? photo, int secs = 60}) async {
    final row = await supabase.rpc('create_duel', params: {
      'p_exercise': exercise.name,
      'p_name': name,
      'p_level': level,
      'p_avatar': photo,
      'p_secs': secs,
    });
    return DuelRow.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Matchmaking: search for anyone racing the same exercise and length.
  /// Returns a live duel when paired; otherwise my own waiting search, which
  /// must be refreshed by calling this again every few seconds.
  Future<DuelRow> quickMatch(ExerciseType exercise, String name, int level, {String? photo, int secs = 60}) async {
    final row = await supabase.rpc('quick_match', params: {
      'p_exercise': exercise.name,
      'p_name': name,
      'p_level': level,
      'p_avatar': photo,
      'p_secs': secs,
    });
    return DuelRow.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Players searching and racing right now.
  Future<(int searching, int racing)> matchmakingStatus(ExerciseType exercise) async {
    final rows = await supabase.rpc('matchmaking_status', params: {'p_exercise': exercise.name}) as List;
    if (rows.isEmpty) return (0, 0);
    final r = Map<String, dynamic>.from(rows.first as Map);
    return ((r['searching'] as num).toInt(), (r['racing'] as num).toInt());
  }

  /// The invite behind [code], or null if it is gone or already taken.
  Future<DuelInvite?> peek(String code) async {
    final rows = await supabase.rpc('peek_duel', params: {'p_code': code}) as List;
    return rows.isEmpty ? null : DuelInvite.fromJson(code, Map<String, dynamic>.from(rows.first as Map));
  }

  /// Accepts the invite; [secs] is the length the guest agreed to.
  Future<DuelRow> join(String code, String name, int level, {String? photo, int? secs}) async {
    final row = await supabase.rpc('join_duel', params: {
      'p_code': code,
      'p_name': name,
      'p_level': level,
      'p_avatar': photo,
      'p_secs': secs,
    });
    return DuelRow.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Live updates of one duel row (initial value, then every change).
  Stream<DuelRow> watch(String duelId) => supabase
      .from('duels')
      .stream(primaryKey: ['id'])
      .eq('id', duelId)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => DuelRow.fromJson(rows.first));

  /// The opponent's score as pulses, for the race screen's rival counter.
  Stream<LivePulse> opponentPulses(DuelBout bout) => watch(bout.boutId).map((row) => LivePulse(
        playerId: bout.opponentId,
        reps: row.repsOf(bout.opponentId),
        declared: row.repsOf(bout.opponentId),
        atSecond: 0,
      ));

  /// Sends my latest verified count. Failures are dropped on purpose: the next
  /// rep sends the full count again, and counts only ever go up.
  Future<void> reportReps(String duelId, int reps) async {
    try {
      await supabase.rpc('report_reps', params: {
        'p_duel': duelId,
        'p_reps': reps,
      });
    } catch (_) {}
  }

  /// Waits out the server's grace period, then asks it to settle the race.
  /// Returns null if the server could not be reached; the screen then keeps
  /// its own local result.
  Future<DuelResult?> settle(DuelBout bout, DateTime goAtServer) async {
    final end = toLocal(goAtServer).add(Duration(seconds: bout.window.fightSecs + 2, milliseconds: 600));
    final wait = end.difference(DateTime.now());
    if (!wait.isNegative) await Future<void>.delayed(wait);

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final raw = await supabase.rpc('finish_duel', params: {'p_duel': bout.boutId});
        final row = DuelRow.fromJson(Map<String, dynamic>.from(raw as Map));
        if (row.isFinished) return row.resultFor(bout.myId);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return null;
  }

  /// Taunts travel as a realtime broadcast on the duel's own channel: they
  /// are chatter, not score, so nothing is stored.
  RealtimeChannel _tauntChannel(String duelId) => _channels[duelId] ??= supabase.channel('duel-taunts:$duelId');
  final _channels = <String, RealtimeChannel>{};

  /// The rival's taunts for one duel.
  Stream<String> taunts(DuelBout bout) {
    final out = StreamController<String>.broadcast();
    _tauntChannel(bout.boutId)
        .onBroadcast(
          event: 'taunt',
          callback: (message) {
            // Depending on the client version the fields arrive nested.
            final inner = message['payload'];
            final payload = inner is Map ? inner : message;
            final from = payload['from'], text = payload['text'];
            if (from != bout.myId && text is String && text.length <= 40) out.add(text);
          },
        )
        .subscribe();
    return out.stream;
  }

  Future<void> sendTaunt(DuelBout bout, String text) async {
    try {
      await _tauntChannel(bout.boutId).sendBroadcastMessage(event: 'taunt', payload: {'from': bout.myId, 'text': text});
    } catch (_) {}
  }

  Future<void> cancel(String duelId) async {
    try {
      await supabase.rpc('cancel_duel', params: {'p_duel': duelId});
    } catch (_) {}
  }
}
