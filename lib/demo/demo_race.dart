import 'dart:async';
import 'dart:math' as math;

import '../i18n/i18n.dart';
import '../modes/online/duel_models.dart';

/// The video build: `flutter build apk --dart-define=DEMO=true`. Its races
/// are against a bot on the phone, with reps counted without a camera, so a
/// whole race can be filmed. They never reach the server, so no real rating
/// or coins move. Normal builds compile all of this away.
const kDemoBuild = bool.fromEnvironment('DEMO');

/// A rival who keeps a slightly slower pace than the scripted hero, and
/// taunts now and then.
class DemoRival {
  DemoRival({this.secondsPerRep = 1.75});
  final double secondsPerRep;

  final pulses = StreamController<LivePulse>.broadcast();
  final taunts = StreamController<String>.broadcast();
  final _timers = <Timer>[];

  static DuelPlayer get player => DuelPlayer(name: I18n.isAr ? 'فهد' : 'Fahad', level: 8, avatar: 'assets/rc/Leon.png');

  /// Starts once the countdown ([leadSecs]) is over.
  void start({required int leadSecs}) {
    final rnd = math.Random();
    var reps = 0;
    _timers.add(Timer(Duration(seconds: leadSecs), () {
      _timers.add(Timer.periodic(Duration(milliseconds: (secondsPerRep * 1000).round()), (t) {
        if (rnd.nextDouble() < 0.12) return; // a breath now and then
        reps++;
        pulses.add(LivePulse(playerId: 'bot', reps: reps, declared: reps, atSecond: (t.tick * secondsPerRep).round()));
      }));
    }));
    _timers.add(Timer(Duration(seconds: leadSecs + 7), () => taunts.add(tr('Is that all? 😏'))));
  }

  void stop() {
    for (final t in _timers) {
      t.cancel();
    }
    pulses.close();
    taunts.close();
  }
}
