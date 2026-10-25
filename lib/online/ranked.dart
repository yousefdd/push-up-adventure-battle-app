import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n/i18n.dart';
import 'supabase_config.dart';

/// The eight ranks, lowest first. Each has three divisions: III, II, I.
/// The last, Champion, is kept a mystery until you are close.
enum RankTier {
  bronze('Bronze', 0, Color(0xFFD08A4E), Color(0xFF7A4322)),
  silver('Silver', 1100, Color(0xFFDDE5F0), Color(0xFF7D8BA3)),
  gold('Gold', 1250, Color(0xFFFFD25A), Color(0xFFB07A10)),
  platinum('Platinum', 1400, Color(0xFF6FF0DC), Color(0xFF1D8C84)),
  diamond('Diamond', 1550, Color(0xFF7DB8FF), Color(0xFF2C55C9)),
  master('Master', 1750, Color(0xFFC3A6FF), Color(0xFF6A3FD0)),
  grandmaster('Grandmaster', 1950, Color(0xFFFF7A7A), Color(0xFF9E1C2C)),
  champion('Champion', 2150, Color(0xFF8FF6FF), Color(0xFF2B0F5E));

  const RankTier(this.label, this.start, this.light, this.dark);
  final String label;

  /// Rating where the rank begins.
  final int start;
  final Color light, dark;

  /// Where the divisions span: Bronze's from 950 (below is still Bronze III),
  /// Champion's up to 2550 (Champion I has no ceiling).
  int get bottom => this == RankTier.bronze ? 950 : start;
  int get top => this == RankTier.champion ? 2550 : RankTier.values[index + 1].start;

  /// From Diamond up, wins pay gold Cinder Coins instead of silver.
  bool get paysGold => index >= RankTier.diamond.index;
}

/// Where a rating sits: rank, division, and the way to the next step.
class Rank {
  const Rank(this.tier, this.division, this.floor, this.next);

  final RankTier tier;

  /// 3, 2 or 1 (1 is the top of the rank).
  final int division;

  /// Rating where this step starts, and where the next one starts (null at the very top).
  final int floor;
  final int? next;

  /// The rank for [rating]. New players start at 1000: Bronze II.
  static Rank of(int rating) {
    var tier = RankTier.bronze;
    for (final t in RankTier.values) {
      if (rating >= t.start) tier = t;
    }
    final step = (tier.top - tier.bottom) / 3;
    final i = ((rating - tier.bottom) / step).floor().clamp(0, 2);
    final floor = tier == RankTier.bronze && i == 0 ? 0 : (tier.bottom + step * i).round();
    final last = tier == RankTier.champion && i == 2;
    return Rank(tier, 3 - i, floor, last ? null : (tier.bottom + step * (i + 1)).round());
  }

  String get roman => const {3: 'III', 2: 'II', 1: 'I'}[division]!;

  /// "Gold II", "غولد II".
  String get name => '${tr(tier.label)} $roman';

  /// 0..1 toward the next step (1 at the very top).
  double progress(int rating) {
    final n = next;
    if (n == null) return 1;
    final from = tier == RankTier.bronze && division == 3 ? tier.bottom : floor;
    return ((rating - from) / (n - from)).clamp(0.0, 1.0);
  }

  bool operator <(Rank o) => tier.index < o.tier.index || (tier == o.tier && division > o.division);

  @override
  bool operator ==(Object other) => other is Rank && other.tier == tier && other.division == division;

  @override
  int get hashCode => Object.hash(tier, division);
}

/// My ranked record and coins, as the server keeps them.
class PlayerStats {
  const PlayerStats({
    this.rating = 1000,
    this.peak = 1000,
    this.games = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.gold = 0,
    this.silver = 0,
  });

  factory PlayerStats.fromJson(Map<String, dynamic> j) => PlayerStats(
        rating: (j['rating'] as num?)?.toInt() ?? 1000,
        peak: (j['peak_rating'] as num?)?.toInt() ?? 1000,
        games: (j['ranked_games'] as num?)?.toInt() ?? 0,
        wins: (j['wins'] as num?)?.toInt() ?? 0,
        losses: (j['losses'] as num?)?.toInt() ?? 0,
        draws: (j['draws'] as num?)?.toInt() ?? 0,
        gold: (j['coins'] as num?)?.toInt() ?? 0,
        silver: (j['silver'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'rating': rating,
        'peak_rating': peak,
        'ranked_games': games,
        'wins': wins,
        'losses': losses,
        'draws': draws,
        'coins': gold,
        'silver': silver,
      };

  PlayerStats withCoins({int? gold, int? silver}) => PlayerStats(
        rating: rating,
        peak: peak,
        games: games,
        wins: wins,
        losses: losses,
        draws: draws,
        gold: gold ?? this.gold,
        silver: silver ?? this.silver,
      );

  final int rating, peak, games, wins, losses, draws;

  /// Gold Cinder Coins (hard to earn: Diamond and up, hard worlds) and
  /// silver coins (easier: lower ranks, early worlds).
  final int gold, silver;

  Rank get rank => Rank.of(rating);
}

/// What one ranked race did to me, from the server's settlement.
class RankChange {
  const RankChange({required this.before, required this.delta, this.gold = 0, this.silver = 0});
  final int before, delta, gold, silver;
  int get after => before + delta;
  Rank get oldRank => Rank.of(before);
  Rank get newRank => Rank.of(after);
  bool get promoted => oldRank < newRank;
  bool get demoted => newRank < oldRank;
}

/// What clearing an adventure world paid.
class Reward {
  const Reward(this.amount, {required this.gold});
  final int amount;
  final bool gold;
}

/// Loads and caches my stats. The last known values are kept on the phone
/// so the rank and coins show at once, and offline.
class Ranked {
  static const _key = 'rr.stats';
  static final stats = ValueNotifier<PlayerStats>(const PlayerStats());

  static SupabaseClient? get _client => SupabaseConfig.client;

  /// The cached values first, then the server's when it answers.
  static Future<PlayerStats> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_key);
    if (cached != null) {
      try {
        stats.value = PlayerStats.fromJson(Map<String, dynamic>.from(jsonDecode(cached) as Map));
      } catch (_) {}
    }
    final c = _client;
    if (c == null) return stats.value;
    try {
      if (c.auth.currentUser == null) await c.auth.signInAnonymously();
      final row = await c.rpc('my_stats');
      _store(PlayerStats.fromJson(Map<String, dynamic>.from(row as Map)), prefs);
    } catch (_) {
      // Offline, or the server is not set up for ranked play yet.
    }
    return stats.value;
  }

  static void _store(PlayerStats s, SharedPreferences prefs) {
    stats.value = s;
    prefs.setString(_key, jsonEncode(s.toJson()));
  }

  /// Clearing an adventure world pays silver (early worlds) or a gold
  /// Cinder Coin (world 8 up, or Nightmare). The server limits how often.
  static Future<Reward?> claimAdventure(int world, {bool hard = false}) async {
    final c = _client;
    if (c == null) return null;
    try {
      if (c.auth.currentUser == null) await c.auth.signInAnonymously();
      final rows = await c.rpc('claim_adventure_reward', params: {'p_world': world, 'p_hard': hard}) as List;
      if (rows.isEmpty) return null;
      final r = Map<String, dynamic>.from(rows.first as Map);
      final prefs = await SharedPreferences.getInstance();
      _store(stats.value.withCoins(gold: (r['coins'] as num).toInt(), silver: (r['silver'] as num).toInt()), prefs);
      final granted = (r['granted'] as num).toInt();
      return granted > 0 ? Reward(granted, gold: r['gold'] as bool? ?? false) : null;
    } catch (_) {
      return null;
    }
  }
}
