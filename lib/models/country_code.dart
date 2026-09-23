class CountryCode {
  final String name;
  final String code; // ISO 2-letter (e.g., 'LK', 'US')
  final String dialCode; // e.g., '+94', '+1'
  final String flag; // Emoji flag

  const CountryCode({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
  });

  String get displayName => '$flag $name ($dialCode)';

  /// Maps the country ISO code to its primary national currency code
  String get currencyCode {
    switch (code.toUpperCase()) {
      case 'LK': return 'LKR';
      case 'US': return 'USD';
      case 'GB': return 'GBP';
      case 'IN': return 'INR';
      case 'AE': return 'AED';
      case 'AU': return 'AUD';
      case 'CA': return 'CAD';
      case 'SG': return 'SGD';
      case 'MY': return 'MYR';
      case 'QA': return 'QAR';
      case 'SA': return 'SAR';
      case 'JP': return 'JPY';
      case 'CN': return 'CNY';
      case 'NZ': return 'NZD';
      case 'CH': return 'CHF';
      case 'DE':
      case 'FR':
      case 'IT':
      case 'ES':
      case 'NL':
      case 'BE':
      case 'AT':
      case 'GR':
      case 'IE':
      case 'PT':
      case 'FI': return 'EUR';
      case 'RU': return 'RUB';
      case 'BR': return 'BRL';
      case 'ZA': return 'ZAR';
      case 'KR': return 'KRW';
      case 'TH': return 'THB';
      case 'ID': return 'IDR';
      case 'PH': return 'PHP';
      case 'VN': return 'VND';
      case 'PK': return 'PKR';
      case 'BD': return 'BDT';
      case 'NP': return 'NPR';
      case 'KW': return 'KWD';
      case 'OM': return 'OMR';
      case 'BH': return 'BHD';
      case 'TR': return 'TRY';
      case 'EG': return 'EGP';
      case 'NG': return 'NGN';
      case 'KE': return 'KES';
      case 'MX': return 'MXN';
      case 'AR': return 'ARS';
      case 'CL': return 'CLP';
      case 'CO': return 'COP';
      case 'PE': return 'PEN';
      case 'PL': return 'PLN';
      case 'CZ': return 'CZK';
      case 'HU': return 'HUF';
      case 'RO': return 'RON';
      case 'SE': return 'SEK';
      case 'NO': return 'NOK';
      case 'DK': return 'DKK';
      default: return 'USD';
    }
  }

  /// Dynamic hint text showing standard national phone format
  String get exampleHint {
    switch (code.toUpperCase()) {
      case 'LK': return '77 123 4567';
      case 'US':
      case 'CA': return '415 555 2671';
      case 'GB': return '7911 123456';
      case 'IN': return '98765 43210';
      case 'AE': return '50 123 4567';
      case 'AU': return '412 345 678';
      case 'SG': return '8123 4567';
      case 'MY': return '12 345 6789';
      case 'QA': return '3312 3456';
      case 'SA': return '50 123 4567';
      case 'DE': return '151 1234567';
      default: return '123 456 789';
    }
  }

  /// Maximum allowed digits input based on country numbering plan
  int get maxInputLength {
    switch (code.toUpperCase()) {
      case 'LK': return 10; // 9 digits, or 10 if typed with leading 0
      case 'US':
      case 'CA': return 10;
      case 'IN': return 10;
      case 'GB': return 11; // 10 digits, or 11 with leading 0
      case 'AE': return 10; // 9 digits, or 10 with leading 0
      case 'AU': return 10; // 9 digits, or 10 with leading 0
      default: return 12;
    }
  }

  /// Validates the input mobile number according to the country telecom standard
  String? validateNumber(String raw) {
    if (raw.trim().isEmpty) {
      return 'Please enter your mobile phone number';
    }
    // Digits only
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return 'Mobile number must contain digits only';
    }

    // Strip leading 0 if present to obtain national significant number
    final national = digits.startsWith('0') ? digits.substring(1) : digits;

    switch (code.toUpperCase()) {
      case 'LK':
        if (national.length != 9) {
          return 'Sri Lankan mobile numbers must have 9 digits (e.g. 77 123 4567)';
        }
        if (!national.startsWith('7')) {
          return 'Sri Lankan mobile numbers must start with 7 (e.g. 70, 71, 74, 76, 77, 78)';
        }
        break;

      case 'IN':
        if (national.length != 10) {
          return 'Indian mobile numbers must have 10 digits';
        }
        if (!RegExp(r'^[6-9]').hasMatch(national)) {
          return 'Indian mobile numbers must start with 6, 7, 8, or 9';
        }
        break;

      case 'US':
      case 'CA':
        if (national.length != 10) {
          return 'US/Canada mobile numbers must have 10 digits';
        }
        break;

      case 'GB':
        if (national.length != 10) {
          return 'UK mobile numbers must have 10 digits';
        }
        if (!national.startsWith('7')) {
          return 'UK mobile numbers must start with 7';
        }
        break;

      case 'AE':
        if (national.length != 9) {
          return 'UAE mobile numbers must have 9 digits';
        }
        if (!national.startsWith('5')) {
          return 'UAE mobile numbers must start with 5 (e.g. 50, 52, 54, 55, 56)';
        }
        break;

      case 'AU':
        if (national.length != 9) {
          return 'Australian mobile numbers must have 9 digits';
        }
        if (!national.startsWith('4')) {
          return 'Australian mobile numbers must start with 4';
        }
        break;

      default:
        if (national.length < 7 || national.length > 12) {
          return 'Please enter a valid mobile number (7-12 digits)';
        }
        break;
    }

    return null; // Valid number!
  }

  static const CountryCode defaultCountry = CountryCode(
    name: 'Sri Lanka',
    code: 'LK',
    dialCode: '+94',
    flag: '🇱🇰',
  );

  static const List<CountryCode> popular = [
    CountryCode(name: 'Sri Lanka', code: 'LK', dialCode: '+94', flag: '🇱🇰'),
    CountryCode(name: 'United States', code: 'US', dialCode: '+1', flag: '🇺🇸'),
    CountryCode(name: 'United Kingdom', code: 'GB', dialCode: '+44', flag: '🇬🇧'),
    CountryCode(name: 'India', code: 'IN', dialCode: '+91', flag: '🇮🇳'),
    CountryCode(name: 'United Arab Emirates', code: 'AE', dialCode: '+971', flag: '🇦🇪'),
    CountryCode(name: 'Australia', code: 'AU', dialCode: '+61', flag: '🇦🇺'),
    CountryCode(name: 'Canada', code: 'CA', dialCode: '+1', flag: '🇨🇦'),
    CountryCode(name: 'Singapore', code: 'SG', dialCode: '+65', flag: '🇸🇬'),
    CountryCode(name: 'Malaysia', code: 'MY', dialCode: '+60', flag: '🇲🇾'),
    CountryCode(name: 'Qatar', code: 'QA', dialCode: '+974', flag: '🇶🇦'),
    CountryCode(name: 'Saudi Arabia', code: 'SA', dialCode: '+966', flag: '🇸🇦'),
    CountryCode(name: 'Germany', code: 'DE', dialCode: '+49', flag: '🇩🇪'),
  ];

  static const List<CountryCode> all = [
    CountryCode(name: 'Afghanistan', code: 'AF', dialCode: '+93', flag: '🇦🇫'),
    CountryCode(name: 'Albania', code: 'AL', dialCode: '+355', flag: '🇦🇱'),
    CountryCode(name: 'Algeria', code: 'DZ', dialCode: '+213', flag: '🇩🇿'),
    CountryCode(name: 'Andorra', code: 'AD', dialCode: '+376', flag: '🇦🇩'),
    CountryCode(name: 'Angola', code: 'AO', dialCode: '+244', flag: '🇦🇴'),
    CountryCode(name: 'Argentina', code: 'AR', dialCode: '+54', flag: '🇦🇷'),
    CountryCode(name: 'Armenia', code: 'AM', dialCode: '+374', flag: '🇦🇲'),
    CountryCode(name: 'Australia', code: 'AU', dialCode: '+61', flag: '🇦🇺'),
    CountryCode(name: 'Austria', code: 'AT', dialCode: '+43', flag: '🇦🇹'),
    CountryCode(name: 'Azerbaijan', code: 'AZ', dialCode: '+994', flag: '🇦🇿'),
    CountryCode(name: 'Bahamas', code: 'BS', dialCode: '+1242', flag: '🇧🇸'),
    CountryCode(name: 'Bahrain', code: 'BH', dialCode: '+973', flag: '🇧🇭'),
    CountryCode(name: 'Bangladesh', code: 'BD', dialCode: '+880', flag: '🇧🇩'),
    CountryCode(name: 'Barbados', code: 'BB', dialCode: '+1246', flag: '🇧🇧'),
    CountryCode(name: 'Belarus', code: 'BY', dialCode: '+375', flag: '🇧🇾'),
    CountryCode(name: 'Belgium', code: 'BE', dialCode: '+32', flag: '🇧🇪'),
    CountryCode(name: 'Belize', code: 'BZ', dialCode: '+501', flag: '🇧🇿'),
    CountryCode(name: 'Benin', code: 'BJ', dialCode: '+229', flag: '🇧🇯'),
    CountryCode(name: 'Bhutan', code: 'BT', dialCode: '+975', flag: '🇧🇹'),
    CountryCode(name: 'Bolivia', code: 'BO', dialCode: '+591', flag: '🇧🇴'),
    CountryCode(name: 'Bosnia and Herzegovina', code: 'BA', dialCode: '+387', flag: '🇧🇦'),
    CountryCode(name: 'Botswana', code: 'BW', dialCode: '+267', flag: '🇧🇼'),
    CountryCode(name: 'Brazil', code: 'BR', dialCode: '+55', flag: '🇧🇷'),
    CountryCode(name: 'Brunei', code: 'BN', dialCode: '+673', flag: '🇧🇳'),
    CountryCode(name: 'Bulgaria', code: 'BG', dialCode: '+359', flag: '🇧🇬'),
    CountryCode(name: 'Burkina Faso', code: 'BF', dialCode: '+226', flag: '🇧🇫'),
    CountryCode(name: 'Burundi', code: 'BI', dialCode: '+257', flag: '🇧🇮'),
    CountryCode(name: 'Cambodia', code: 'KH', dialCode: '+855', flag: '🇰🇭'),
    CountryCode(name: 'Cameroon', code: 'CM', dialCode: '+237', flag: '🇨🇲'),
    CountryCode(name: 'Canada', code: 'CA', dialCode: '+1', flag: '🇨🇦'),
    CountryCode(name: 'Cape Verde', code: 'CV', dialCode: '+238', flag: '🇨🇻'),
    CountryCode(name: 'Central African Republic', code: 'CF', dialCode: '+236', flag: '🇨🇫'),
    CountryCode(name: 'Chad', code: 'TD', dialCode: '+235', flag: '🇹🇩'),
    CountryCode(name: 'Chile', code: 'CL', dialCode: '+56', flag: '🇨🇱'),
    CountryCode(name: 'China', code: 'CN', dialCode: '+86', flag: '🇨🇳'),
    CountryCode(name: 'Colombia', code: 'CO', dialCode: '+57', flag: '🇨🇴'),
    CountryCode(name: 'Comoros', code: 'KM', dialCode: '+269', flag: '🇰🇲'),
    CountryCode(name: 'Congo', code: 'CG', dialCode: '+242', flag: '🇨🇬'),
    CountryCode(name: 'Costa Rica', code: 'CR', dialCode: '+506', flag: '🇨🇷'),
    CountryCode(name: 'Croatia', code: 'HR', dialCode: '+385', flag: '🇭🇷'),
    CountryCode(name: 'Cuba', code: 'CU', dialCode: '+53', flag: '🇨🇺'),
    CountryCode(name: 'Cyprus', code: 'CY', dialCode: '+357', flag: '🇨🇾'),
    CountryCode(name: 'Czech Republic', code: 'CZ', dialCode: '+420', flag: '🇨🇿'),
    CountryCode(name: 'Denmark', code: 'DK', dialCode: '+45', flag: '🇩🇰'),
    CountryCode(name: 'Djibouti', code: 'DJ', dialCode: '+253', flag: '🇩🇯'),
    CountryCode(name: 'Dominican Republic', code: 'DO', dialCode: '+1809', flag: '🇩🇴'),
    CountryCode(name: 'Ecuador', code: 'EC', dialCode: '+593', flag: '🇪🇨'),
    CountryCode(name: 'Egypt', code: 'EG', dialCode: '+20', flag: '🇪🇬'),
    CountryCode(name: 'El Salvador', code: 'SV', dialCode: '+503', flag: '🇸🇻'),
    CountryCode(name: 'Equatorial Guinea', code: 'GQ', dialCode: '+240', flag: '🇬🇶'),
    CountryCode(name: 'Eritrea', code: 'ER', dialCode: '+291', flag: '🇪🇷'),
    CountryCode(name: 'Estonia', code: 'EE', dialCode: '+372', flag: '🇪🇪'),
    CountryCode(name: 'Eswatini', code: 'SZ', dialCode: '+268', flag: '🇸🇿'),
    CountryCode(name: 'Ethiopia', code: 'ET', dialCode: '+251', flag: '🇪🇹'),
    CountryCode(name: 'Fiji', code: 'FJ', dialCode: '+679', flag: '🇫🇯'),
    CountryCode(name: 'Finland', code: 'FI', dialCode: '+358', flag: '🇫🇮'),
    CountryCode(name: 'France', code: 'FR', dialCode: '+33', flag: '🇫🇷'),
    CountryCode(name: 'Gabon', code: 'GA', dialCode: '+241', flag: '🇬🇦'),
    CountryCode(name: 'Gambia', code: 'GM', dialCode: '+220', flag: '🇬🇲'),
    CountryCode(name: 'Georgia', code: 'GE', dialCode: '+995', flag: '🇬🇪'),
    CountryCode(name: 'Germany', code: 'DE', dialCode: '+49', flag: '🇩🇪'),
    CountryCode(name: 'Ghana', code: 'GH', dialCode: '+233', flag: '🇬🇭'),
    CountryCode(name: 'Greece', code: 'GR', dialCode: '+30', flag: '🇬🇷'),
    CountryCode(name: 'Grenada', code: 'GD', dialCode: '+1473', flag: '🇬🇩'),
    CountryCode(name: 'Guatemala', code: 'GT', dialCode: '+502', flag: '🇬🇹'),
    CountryCode(name: 'Guinea', code: 'GN', dialCode: '+224', flag: '🇬🇳'),
    CountryCode(name: 'Guyana', code: 'GY', dialCode: '+592', flag: '🇬🇾'),
    CountryCode(name: 'Haiti', code: 'HT', dialCode: '+509', flag: '🇭🇹'),
    CountryCode(name: 'Honduras', code: 'HN', dialCode: '+504', flag: '🇭🇳'),
    CountryCode(name: 'Hong Kong', code: 'HK', dialCode: '+852', flag: '🇭🇰'),
    CountryCode(name: 'Hungary', code: 'HU', dialCode: '+36', flag: '🇭🇺'),
    CountryCode(name: 'Iceland', code: 'IS', dialCode: '+354', flag: '🇮🇸'),
    CountryCode(name: 'India', code: 'IN', dialCode: '+91', flag: '🇮🇳'),
    CountryCode(name: 'Indonesia', code: 'ID', dialCode: '+62', flag: '🇮🇩'),
    CountryCode(name: 'Iran', code: 'IR', dialCode: '+98', flag: '🇮🇷'),
    CountryCode(name: 'Iraq', code: 'IQ', dialCode: '+964', flag: '🇮🇶'),
    CountryCode(name: 'Ireland', code: 'IE', dialCode: '+353', flag: '🇮🇪'),
    CountryCode(name: 'Israel', code: 'IL', dialCode: '+972', flag: '🇮🇱'),
    CountryCode(name: 'Italy', code: 'IT', dialCode: '+39', flag: '🇮🇹'),
    CountryCode(name: 'Jamaica', code: 'JM', dialCode: '+1876', flag: '🇯🇲'),
    CountryCode(name: 'Japan', code: 'JP', dialCode: '+81', flag: '🇯🇵'),
    CountryCode(name: 'Jordan', code: 'JO', dialCode: '+962', flag: '🇯🇴'),
    CountryCode(name: 'Kazakhstan', code: 'KZ', dialCode: '+7', flag: '🇰🇿'),
    CountryCode(name: 'Kenya', code: 'KE', dialCode: '+254', flag: '🇰🇪'),
    CountryCode(name: 'Kuwait', code: 'KW', dialCode: '+965', flag: '🇰🇼'),
    CountryCode(name: 'Kyrgyzstan', code: 'KG', dialCode: '+996', flag: '🇰🇬'),
    CountryCode(name: 'Laos', code: 'LA', dialCode: '+856', flag: '🇱🇦'),
    CountryCode(name: 'Latvia', code: 'LV', dialCode: '+371', flag: '🇱🇻'),
    CountryCode(name: 'Lebanon', code: 'LB', dialCode: '+961', flag: '🇱🇧'),
    CountryCode(name: 'Lesotho', code: 'LS', dialCode: '+266', flag: '🇱🇸'),
    CountryCode(name: 'Liberia', code: 'LR', dialCode: '+231', flag: '🇱🇷'),
    CountryCode(name: 'Libya', code: 'LY', dialCode: '+218', flag: '🇱🇾'),
    CountryCode(name: 'Lithuania', code: 'LT', dialCode: '+370', flag: '🇱🇹'),
    CountryCode(name: 'Luxembourg', code: 'LU', dialCode: '+352', flag: '🇱🇺'),
    CountryCode(name: 'Madagascar', code: 'MG', dialCode: '+261', flag: '🇲🇬'),
    CountryCode(name: 'Malawi', code: 'MW', dialCode: '+265', flag: '🇲🇼'),
    CountryCode(name: 'Malaysia', code: 'MY', dialCode: '+60', flag: '🇲🇾'),
    CountryCode(name: 'Maldives', code: 'MV', dialCode: '+960', flag: '🇲🇻'),
    CountryCode(name: 'Mali', code: 'ML', dialCode: '+223', flag: '🇲🇱'),
    CountryCode(name: 'Malta', code: 'MT', dialCode: '+356', flag: '🇲🇹'),
    CountryCode(name: 'Mauritania', code: 'MR', dialCode: '+222', flag: '🇲🇷'),
    CountryCode(name: 'Mauritius', code: 'MU', dialCode: '+230', flag: '🇲🇺'),
    CountryCode(name: 'Mexico', code: 'MX', dialCode: '+52', flag: '🇲🇽'),
    CountryCode(name: 'Moldova', code: 'MD', dialCode: '+373', flag: '🇲🇩'),
    CountryCode(name: 'Monaco', code: 'MC', dialCode: '+377', flag: '🇲🇨'),
    CountryCode(name: 'Mongolia', code: 'MN', dialCode: '+976', flag: '🇲🇳'),
    CountryCode(name: 'Montenegro', code: 'ME', dialCode: '+382', flag: '🇲🇪'),
    CountryCode(name: 'Morocco', code: 'MA', dialCode: '+212', flag: '🇲🇦'),
    CountryCode(name: 'Mozambique', code: 'MZ', dialCode: '+258', flag: '🇲🇿'),
    CountryCode(name: 'Myanmar', code: 'MM', dialCode: '+95', flag: '🇲🇲'),
    CountryCode(name: 'Namibia', code: 'NA', dialCode: '+264', flag: '🇳🇦'),
    CountryCode(name: 'Nepal', code: 'NP', dialCode: '+977', flag: '🇳🇵'),
    CountryCode(name: 'Netherlands', code: 'NL', dialCode: '+31', flag: '🇳🇱'),
    CountryCode(name: 'New Zealand', code: 'NZ', dialCode: '+64', flag: '🇳🇿'),
    CountryCode(name: 'Nicaragua', code: 'NI', dialCode: '+505', flag: '🇳🇮'),
    CountryCode(name: 'Nigeria', code: 'NG', dialCode: '+234', flag: '🇳🇬'),
    CountryCode(name: 'Norway', code: 'NO', dialCode: '+47', flag: '🇳🇴'),
    CountryCode(name: 'Oman', code: 'OM', dialCode: '+968', flag: '🇴🇲'),
    CountryCode(name: 'Pakistan', code: 'PK', dialCode: '+92', flag: '🇵🇰'),
    CountryCode(name: 'Panama', code: 'PA', dialCode: '+507', flag: '🇵🇦'),
    CountryCode(name: 'Paraguay', code: 'PY', dialCode: '+595', flag: '🇵🇾'),
    CountryCode(name: 'Peru', code: 'PE', dialCode: '+51', flag: '🇵🇪'),
    CountryCode(name: 'Philippines', code: 'PH', dialCode: '+63', flag: '🇵🇭'),
    CountryCode(name: 'Poland', code: 'PL', dialCode: '+48', flag: '🇵🇱'),
    CountryCode(name: 'Portugal', code: 'PT', dialCode: '+351', flag: '🇵🇹'),
    CountryCode(name: 'Qatar', code: 'QA', dialCode: '+974', flag: '🇶🇦'),
    CountryCode(name: 'Romania', code: 'RO', dialCode: '+40', flag: '🇷🇴'),
    CountryCode(name: 'Russia', code: 'RU', dialCode: '+7', flag: '🇷🇺'),
    CountryCode(name: 'Rwanda', code: 'RW', dialCode: '+250', flag: '🇷🇼'),
    CountryCode(name: 'Saudi Arabia', code: 'SA', dialCode: '+966', flag: '🇸🇦'),
    CountryCode(name: 'Senegal', code: 'SN', dialCode: '+221', flag: '🇸🇳'),
    CountryCode(name: 'Serbia', code: 'RS', dialCode: '+381', flag: '🇷🇸'),
    CountryCode(name: 'Seychelles', code: 'SC', dialCode: '+248', flag: '🇸🇨'),
    CountryCode(name: 'Sierra Leone', code: 'SL', dialCode: '+232', flag: '🇸🇱'),
    CountryCode(name: 'Singapore', code: 'SG', dialCode: '+65', flag: '🇸🇬'),
    CountryCode(name: 'Slovakia', code: 'SK', dialCode: '+421', flag: '🇸🇰'),
    CountryCode(name: 'Slovenia', code: 'SI', dialCode: '+386', flag: '🇸🇮'),
    CountryCode(name: 'South Africa', code: 'ZA', dialCode: '+27', flag: '🇿🇦'),
    CountryCode(name: 'South Korea', code: 'KR', dialCode: '+82', flag: '🇰🇷'),
    CountryCode(name: 'Spain', code: 'ES', dialCode: '+34', flag: '🇪🇸'),
    CountryCode(name: 'Sri Lanka', code: 'LK', dialCode: '+94', flag: '🇱🇰'),
    CountryCode(name: 'Sudan', code: 'SD', dialCode: '+249', flag: '🇸🇩'),
    CountryCode(name: 'Sweden', code: 'SE', dialCode: '+46', flag: '🇸🇪'),
    CountryCode(name: 'Switzerland', code: 'CH', dialCode: '+41', flag: '🇨🇭'),
    CountryCode(name: 'Taiwan', code: 'TW', dialCode: '+886', flag: '🇹🇼'),
    CountryCode(name: 'Tanzania', code: 'TZ', dialCode: '+255', flag: '🇹🇿'),
    CountryCode(name: 'Thailand', code: 'TH', dialCode: '+66', flag: '🇹🇭'),
    CountryCode(name: 'Tunisia', code: 'TN', dialCode: '+216', flag: '🇹🇳'),
    CountryCode(name: 'Turkey', code: 'TR', dialCode: '+90', flag: '🇹🇷'),
    CountryCode(name: 'Uganda', code: 'UG', dialCode: '+256', flag: '🇺🇬'),
    CountryCode(name: 'Ukraine', code: 'UA', dialCode: '+380', flag: '🇺🇦'),
    CountryCode(name: 'United Arab Emirates', code: 'AE', dialCode: '+971', flag: '🇦🇪'),
    CountryCode(name: 'United Kingdom', code: 'GB', dialCode: '+44', flag: '🇬🇧'),
    CountryCode(name: 'United States', code: 'US', dialCode: '+1', flag: '🇺🇸'),
    CountryCode(name: 'Uruguay', code: 'UY', dialCode: '+598', flag: '🇺🇾'),
    CountryCode(name: 'Uzbekistan', code: 'UZ', dialCode: '+998', flag: '🇺🇿'),
    CountryCode(name: 'Venezuela', code: 'VE', dialCode: '+58', flag: '🇻🇪'),
    CountryCode(name: 'Vietnam', code: 'VN', dialCode: '+84', flag: '🇻🇳'),
    CountryCode(name: 'Yemen', code: 'YE', dialCode: '+967', flag: '🇾🇪'),
    CountryCode(name: 'Zambia', code: 'ZM', dialCode: '+260', flag: '🇿🇲'),
    CountryCode(name: 'Zimbabwe', code: 'ZW', dialCode: '+263', flag: '🇿🇼'),
  ];

  /// Auto-match a country code based on selected currency code
  static CountryCode fromCurrency(String currencyCode) {
    switch (currencyCode.toUpperCase()) {
      case 'LKR':
        return const CountryCode(name: 'Sri Lanka', code: 'LK', dialCode: '+94', flag: '🇱🇰');
      case 'INR':
        return const CountryCode(name: 'India', code: 'IN', dialCode: '+91', flag: '🇮🇳');
      case 'AED':
        return const CountryCode(name: 'United Arab Emirates', code: 'AE', dialCode: '+971', flag: '🇦🇪');
      case 'GBP':
        return const CountryCode(name: 'United Kingdom', code: 'GB', dialCode: '+44', flag: '🇬🇧');
      case 'AUD':
        return const CountryCode(name: 'Australia', code: 'AU', dialCode: '+61', flag: '🇦🇺');
      case 'CAD':
        return const CountryCode(name: 'Canada', code: 'CA', dialCode: '+1', flag: '🇨🇦');
      case 'SGD':
        return const CountryCode(name: 'Singapore', code: 'SG', dialCode: '+65', flag: '🇸🇬');
      case 'MYR':
        return const CountryCode(name: 'Malaysia', code: 'MY', dialCode: '+60', flag: '🇲🇾');
      case 'EUR':
        return const CountryCode(name: 'Germany', code: 'DE', dialCode: '+49', flag: '🇩🇪');
      case 'JPY':
        return const CountryCode(name: 'Japan', code: 'JP', dialCode: '+81', flag: '🇯🇵');
      case 'QAR':
        return const CountryCode(name: 'Qatar', code: 'QA', dialCode: '+974', flag: '🇶🇦');
      case 'SAR':
        return const CountryCode(name: 'Saudi Arabia', code: 'SA', dialCode: '+966', flag: '🇸🇦');
      case 'USD':
      default:
        return const CountryCode(name: 'Sri Lanka', code: 'LK', dialCode: '+94', flag: '🇱🇰');
    }
  }

  /// Auto-match a country code based on ISO 2-letter country code (e.g. 'LK', 'US')
  static CountryCode fromCountryCode(String code) {
    final clean = code.trim().toUpperCase();
    return supportedCountries.firstWhere(
      (c) => c.code.toUpperCase() == clean,
      orElse: () => defaultCountry,
    );
  }
}
