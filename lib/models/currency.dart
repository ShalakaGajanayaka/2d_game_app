class Currency {
  final String code;
  final String name;
  final String symbol;
  final String flag;

  const Currency({
    required this.code,
    required this.name,
    required this.symbol,
    required this.flag,
  });

  static const Currency usd = Currency(
    code: 'USD',
    name: 'US Dollar',
    symbol: '\$',
    flag: '🇺🇸',
  );

  static const Currency defaultCurrency = usd;

  static const List<Currency> supportedCurrencies = [usd];
  static const List<Currency> popularCurrencies = [usd];
  static const List<Currency> allCurrencies = [usd];

  static Currency getByCode(String? code) => usd;
}
