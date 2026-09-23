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
    'alex_pro', 'sam_99', 'crypto_king', 'wolf_win', 'neo_007', 'falcon_vip',
    'lucky_win', 'shadow_x', 'zenith_boss', 'viper_pro', 'pilot_99', 'storm_rider',
    'nova_star', 'matrix_777', 'cyber_ace', 'apex_hunter', 'iron_blade', 'titan_win',
    'flash_runner', 'speedy_sam', 'elena_vip', 'johnd_top', 'omega_boss', 'phantom_x',
    'vortex_01', 'silver_falcon', 'blaze_777', 'hunter_x', 'valkyrie_pro', 'turbo_win',
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

  // USD / Default bet distributions
  static const List<double> usdSmall = [5, 10, 15, 20, 25, 30, 40, 50];
  static const List<double> usdMedium = [60, 75, 100, 150, 200, 250];
  static const List<double> usdHigh = [300, 500, 750, 1000, 1500, 2000];

  /// Transforms an incoming bet from the server into a currency-accurate, localized bet
  static Map<String, dynamic> localize(Map<String, dynamic> rawBet, String currencyCode) {
    if (rawBet['isMe'] == true) {
      return Map<String, dynamic>.from(rawBet);
    }

    final id = rawBet['id']?.toString() ?? '';
    // Stable deterministic seed based on bot ID so amounts and names never flicker
    final int seed = id.hashCode.abs();
    final cleanCurrency = currencyCode.toUpperCase();

    String name;
    double betAmount;

    if (cleanCurrency == 'LKR') {
      name = lkrNames[seed % lkrNames.length];
      final roll = seed % 100;
      if (roll < 65) {
        betAmount = lkrSmall[(seed ~/ 100) % lkrSmall.length];
      } else if (roll < 90) {
        betAmount = lkrMedium[(seed ~/ 100) % lkrMedium.length];
      } else {
        betAmount = lkrHigh[(seed ~/ 100) % lkrHigh.length];
      }
    } else if (cleanCurrency == 'INR') {
      name = inrNames[seed % inrNames.length];
      final roll = seed % 100;
      if (roll < 65) {
        betAmount = inrSmall[(seed ~/ 100) % inrSmall.length];
      } else if (roll < 90) {
        betAmount = inrMedium[(seed ~/ 100) % inrMedium.length];
      } else {
        betAmount = inrHigh[(seed ~/ 100) % inrHigh.length];
      }
    } else {
      name = usdNames[seed % usdNames.length];
      final roll = seed % 100;
      if (roll < 65) {
        betAmount = usdSmall[(seed ~/ 100) % usdSmall.length];
      } else if (roll < 90) {
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
