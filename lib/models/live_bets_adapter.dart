class LiveBetsAdapter {
  static const List<String> lkrNames = [
    'tharindu03', 'kasun_k', 'dinuka_lk', 'roshan_99', 'saman_boss', 'nimal_pro',
    'chaminda_sl', 'ravi_777', 'shehan_vip', 'nuwan_91', 'pathum_x', 'kavindu_fly',
    'lahiru_99', 'dilan_01', 'anushka_pro', 'chathura_win', 'danushka_lk', 'pubudu_77',
    'sanka_ace', 'isuru_top', 'mahesh_vip', 'asanka_sl', 'janaka_boss', 'supun_king',
    'manoj_99', 'ruwan_lk', 'thilina_pro', 'dimuthu_x', 'malith_007', 'gayan_win',
    'sanath_pro', 'ashan_sl', 'pramod_99', 'sandun_boss', 'indika_lk', 'nadeeka_pro',
    'suranga_vip', 'duminda_01', 'lakshan_pro', 'harsha_99', 'chinthaka_lk', 'hasitha_win',
    'sudeera_boss', 'madushanka_77', 'navin_pro', 'bandara_sl', 'kusal_vip', 'charith_x',
  ];

  static const List<String> inrNames = [
    'rahul_99', 'amit_pro', 'vikram_king', 'priya_win', 'rohit_boss', 'raj_777',
    'arjun_sl', 'sachin_pro', 'deepak_99', 'manish_vip', 'pooja_win', 'anil_pro',
    'suresh_king', 'neha_777', 'ajay_boss', 'vijay_top', 'sunil_ace', 'karan_win',
  ];

  static const List<String> usdNames = [
    // Original established gamer tags
    'alex_pro', 'sam_99', 'crypto_king', 'wolf_win', 'neo_007', 'falcon_vip',
    'lucky_win', 'shadow_x', 'zenith_boss', 'viper_pro', 'pilot_99', 'storm_rider',
    'nova_star', 'matrix_777', 'cyber_ace', 'apex_hunter', 'iron_blade', 'titan_win',
    'flash_runner', 'speedy_sam', 'elena_vip', 'johnd_top', 'omega_boss', 'phantom_x',
    'vortex_01', 'silver_falcon', 'blaze_777', 'hunter_x', 'valkyrie_pro', 'turbo_win',
    // Crypto, Web3 & FinTech handles
    'satoshi_77', 'chain_runner', 'whale_trader', 'hodl_boss', 'sol_master', 'eth_bull',
    'bit_pilot', 'neon_rider', 'quantum_x', 'block_star', 'dex_whale', 'crypto_wolf',
    'moon_shot', 'ledger_pro', 'token_king', 'defi_ninja', 'yield_boss', 'gwei_runner',
    'halving_99', 'gas_master', 'vault_hunter', 'coin_phantom', 'bull_runner', 'bear_slayer',
    'hash_rate', 'satoshi_pro', 'altcoin_x', 'tether_king', 'usdt_hunter', 'meta_pilot',
    // Aviation, Flight & Altitude handles
    'sky_hawk', 'aero_pro', 'cloud_chaser', 'jet_falcon', 'sonic_boom', 'altitude_x',
    'top_gunner', 'glide_master', 'turbo_fly', 'air_marshal', 'flight_ace', 'strato_fly',
    'rotor_pro', 'sky_voyager', 'aero_strike', 'tailwind_99', 'crosswind_x', 'mach_one',
    'jetstream_01', 'propeller_77', 'airborne_pro', 'hangar_boss', 'cloud_strider', 'skyline_king',
    'vector_fly', 'pilot_shark', 'aviator_pro', 'sky_cruiser', 'runway_boss', 'flight_deck',
    // Casino, High-Roller & Fortune handles
    'golden_roll', 'jackpot_777', 'spin_king', 'fortune_ace', 'high_roller', 'royal_flush',
    'ace_spade', 'wild_card', 'seven_star', 'bonus_hunt', 'coin_master', 'cash_grab',
    'multiplier_x', 'all_in_king', 'poker_face', 'card_shark', 'vegas_pro', 'monaco_vip',
    'macau_boss', 'roulette_77', 'double_down', 'bankroll_99', 'cashout_king', 'big_win_pro',
    'golden_rush', 'diamond_777', 'ruby_streak', 'streak_master', 'luck_factor', 'payout_pro',
    // Cyber, Sci-Fi & Tactical handles
    'hazard_zero', 'dark_knight', 'apex_beast', 'silent_strike', 'bullet_pro', 'ghost_walker',
    'blaze_runner', 'hyper_drive', 'pulse_fire', 'cyber_punk', 'synth_wave', 'grid_runner',
    'glitch_777', 'reboot_x', 'pixel_pro', 'vector_core', 'circuit_boss', 'laser_sharp',
    'radar_lock', 'orbit_x', 'stellar_pro', 'cosmic_drift', 'nebula_99', 'supernova_01',
    'eclipse_boss', 'meteor_strike', 'astral_plane', 'solar_flare', 'infinity_x', 'singularity',
    // Apex Predators & Animal handles
    'tiger_claw', 'lion_heart', 'black_panther', 'viper_strike', 'cobra_eye', 'raptor_99',
    'eagle_eye', 'hawk_vision', 'wolf_pack', 'shadow_fox', 'polar_bear', 'grizzly_pro',
    'rhino_rush', 'bull_charge', 'apex_shark', 'mamba_strike', 'jaguar_speed', 'falcon_claw',
    'wild_stallion', 'lynx_prowl', 'cougar_strike', 'silver_wolf', 'golden_eagle', 'storm_crow',
    // Elite Ranks & Leader handles
    'major_rush', 'general_win', 'captain_fly', 'admiral_ace', 'baron_cash', 'duke_hazard',
    'warlord_777', 'warlord_pro', 'crusader_x', 'sentinel_99', 'guardian_pro', 'warden_boss',
    'overlord_x', 'commander_01', 'champion_77', 'hero_rider', 'legend_99', 'mythic_ace',
    'prime_factor', 'ultra_marine', 'alpha_dog', 'delta_force', 'bravo_six', 'tango_down',
    'echo_strike', 'sierra_run', 'victor_crest', 'strike_leader', 'iron_clad', 'steel_forge',
    // Modern Competitive Gamer tags
    'max_win', 'leo_apex', 'kai_zen', 'zack_attack', 'finn_fly', 'axel_rod',
    'rex_titan', 'troy_pro', 'zane_x', 'noah_ark', 'logan_run', 'lucas_99',
    'chase_win', 'mason_pro', 'ethan_hunt', 'oliver_top', 'caleb_01', 'cole_cash',
    'dylan_99', 'liam_fast', 'ryan_blade', 'blake_storm', 'carter_ace', 'hunter_dean',
    'travis_x', 'connor_pro', 'brody_win', 'parker_boss', 'nolan_flight', 'grant_777',
    // Velocity & High-Power handles
    'rapid_fire', 'swift_flight', 'flash_point', 'warp_speed', 'light_year', 'nitro_boost',
    'octane_99', 'turbo_charge', 'overdrive_x', 'burnout_pro', 'speed_demon', 'velocity_99',
    'mach_speed', 'ignite_pro', 'combustion', 'atomic_power', 'dynamo_rush', 'voltage_01',
    'shockwave_77', 'thunder_bolt', 'lightning_x', 'firestorm_99', 'magma_core', 'blizzard_pro',
    'horizon_fly', 'vanguard_77',
  ];

  // LKR bet distributions:
  // 65% small: Rs. 50 - Rs. 500
  // 25% medium: Rs. 750 - Rs. 5,000
  // 10% high-rollers: Rs. 7,500 - Rs. 50,000
  static const List<double> lkrSmall = [50, 100, 150, 200, 250, 300, 400, 500];
  static const List<double> lkrMedium = [750, 1000, 1500, 2000, 2500, 3000, 4000, 5000];
  static const List<double> lkrHigh = [7500, 10000, 15000, 20000, 25000, 50000];

  // INR bet distributions
  static const List<double> inrSmall = [50, 100, 150, 200, 250, 300, 400, 500];
  static const List<double> inrMedium = [750, 1000, 1500, 2000, 2500, 3000, 5000];
  static const List<double> inrHigh = [7500, 10000, 15000, 20000];

  // USD / Default bet distributions - Realistic Casino Distribution
  static const List<double> usdSmall = [1, 2, 3, 5, 8, 10, 12, 15, 20, 25];
  static const List<double> usdMedium = [30, 40, 50, 60, 75, 80, 100];
  static const List<double> usdHigh = [120, 150, 180, 200, 250, 300, 500];

  /// Transforms an incoming bet from the server into a currency-accurate, localized bet
  static Map<String, dynamic> localize(Map<String, dynamic> rawBet, String currencyCode) {
    if (rawBet['isMe'] == true) {
      return Map<String, dynamic>.from(rawBet);
    }

    final id = rawBet['id']?.toString() ?? '';
    final bool isBot = id.startsWith('bot_');

    // Preserve real connected players' actual usernames and bets
    if (!isBot && rawBet['name'] != null && rawBet['name'].toString().trim().isNotEmpty) {
      return Map<String, dynamic>.from(rawBet);
    }

    // Stable deterministic seed based on bot ID so amounts and names never flicker
    final int seed = id.hashCode.abs();
    final cleanCurrency = currencyCode.toUpperCase();

    // High-dispersion permutation indexing for bots to eliminate name collisions
    // Coprime 73 ensures 100% bijective mapping across pool sizes up to 260
    int botIndex = seed;
    int roundOffset = 0;
    final botMatch = RegExp(r'bot_[a-zA-Z0-9]+_(\d+)_(\d+)').firstMatch(id);
    if (botMatch != null) {
      final int parsedIdx = int.tryParse(botMatch.group(1) ?? '') ?? seed;
      final int parsedTime = int.tryParse(botMatch.group(2) ?? '') ?? seed;
      botIndex = parsedIdx;
      roundOffset = (parsedTime ~/ 1000).abs();
    }

    String name;
    double betAmount;

    if (cleanCurrency == 'LKR') {
      final int nameIdx = ((botIndex * 73) + roundOffset) % lkrNames.length;
      name = lkrNames[nameIdx];
      final roll = seed % 100;
      if (roll < 65) {
        betAmount = lkrSmall[(seed ~/ 100) % lkrSmall.length];
      } else if (roll < 90) {
        betAmount = lkrMedium[(seed ~/ 100) % lkrMedium.length];
      } else {
        betAmount = lkrHigh[(seed ~/ 100) % lkrHigh.length];
      }
    } else if (cleanCurrency == 'INR') {
      final int nameIdx = ((botIndex * 73) + roundOffset) % inrNames.length;
      name = inrNames[nameIdx];
      final roll = seed % 100;
      if (roll < 65) {
        betAmount = inrSmall[(seed ~/ 100) % inrSmall.length];
      } else if (roll < 90) {
        betAmount = inrMedium[(seed ~/ 100) % inrMedium.length];
      } else {
        betAmount = inrHigh[(seed ~/ 100) % inrHigh.length];
      }
    } else {
      final int nameIdx = ((botIndex * 73) + roundOffset) % usdNames.length;
      name = usdNames[nameIdx];
      final roll = seed % 100;
      if (roll < 75) {
        betAmount = usdSmall[(seed ~/ 100) % usdSmall.length];
      } else if (roll < 95) {
        betAmount = usdMedium[(seed ~/ 100) % usdMedium.length];
      } else {
        betAmount = usdHigh[(seed ~/ 100) % usdHigh.length];
      }
    }

    final mult = rawBet['cashedOutMultiplier'] ?? rawBet['mult'];
    final bool cashedOut = rawBet['cashedOut'] == true;
    final double? winAmount = (cashedOut && mult != null)
        ? (betAmount * (mult as num).toDouble())
        : null;

    return {
      'id': id,
      'isMe': false,
      'name': name,
      'bet': betAmount,
      'cashedOut': cashedOut,
      'cashedOutMultiplier': mult,
      'winAmount': winAmount,
    };
  }

  /// Format numbers with comma grouping, e.g. 23,315.00 or 1,450,000.00
  static String formatAmount(num amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    final regExp = RegExp(r'\B(?=(\d{3})+(?!\d))');
    final formattedInt = intPart.replaceAll(regExp, ',');
    return '$formattedInt.$decPart';
  }
}
