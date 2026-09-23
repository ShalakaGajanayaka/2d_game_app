import 'package:flutter/material.dart';
import '../models/country_code.dart';

class CountryCodePickerSheet extends StatefulWidget {
  final CountryCode selectedCountry;
  final ValueChanged<CountryCode> onCountrySelected;

  const CountryCodePickerSheet({
    super.key,
    required this.selectedCountry,
    required this.onCountrySelected,
  });

  static Future<CountryCode?> show(BuildContext context, CountryCode current) {
    return showModalBottomSheet<CountryCode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => CountryCodePickerSheet(
        selectedCountry: current,
        onCountrySelected: (code) => Navigator.of(ctx).pop(code),
      ),
    );
  }

  @override
  State<CountryCodePickerSheet> createState() => _CountryCodePickerSheetState();
}

class _CountryCodePickerSheetState extends State<CountryCodePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<CountryCode> _filteredList = CountryCode.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase().replaceAll('+', '');
    setState(() {
      if (query.isEmpty) {
        _filteredList = CountryCode.all;
      } else {
        _filteredList = CountryCode.all.where((c) {
          final dialDigits = c.dialCode.replaceAll('+', '').toLowerCase();
          return c.name.toLowerCase().contains(query) ||
              c.code.toLowerCase().contains(query) ||
              dialDigits.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final sheetHeight = mq.size.height * 0.85;

    return Container(
      height: sheetHeight,
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: mq.viewInsets.bottom + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title & close
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.public, color: Color(0xFF38BDF8), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Select Country Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search Box
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search by country or dial code (+94, Sri Lanka...)',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF1E293B),
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Popular Countries Chips (only when search query is empty)
          if (_searchController.text.isEmpty) ...[
            const Text(
              'POPULAR COUNTRIES',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: CountryCode.popular.map((country) {
                  final isSelected = widget.selectedCountry.dialCode == country.dialCode &&
                      widget.selectedCountry.code == country.code;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => widget.onCountrySelected(country),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF38BDF8).withOpacity(0.2)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF334155),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(country.flag, style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text(
                              country.name,
                              style: TextStyle(
                                color: isSelected ? const Color(0xFF38BDF8) : Colors.white,
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              country.dialCode,
                              style: TextStyle(
                                color: isSelected ? const Color(0xFF38BDF8) : Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF334155), height: 1),
            const SizedBox(height: 10),
          ],

          // All Countries Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ALL COUNTRIES',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '${_filteredList.length} countries',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Countries List
          Expanded(
            child: _filteredList.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, color: Colors.white24, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'No country found',
                          style: TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredList.length,
                    itemBuilder: (context, index) {
                      final country = _filteredList[index];
                      final isSelected = widget.selectedCountry.dialCode == country.dialCode &&
                          widget.selectedCountry.code == country.code;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF38BDF8).withOpacity(0.12)
                              : const Color(0xFF1E293B).withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF334155).withOpacity(0.5),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                          leading: Text(
                            country.flag,
                            style: const TextStyle(fontSize: 26),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  country.name,
                                  style: TextStyle(
                                    color: isSelected ? const Color(0xFF38BDF8) : Colors.white,
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF38BDF8).withOpacity(0.25)
                                      : const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF38BDF8)
                                        : const Color(0xFF334155),
                                  ),
                                ),
                                child: Text(
                                  country.dialCode,
                                  style: TextStyle(
                                    color: isSelected ? const Color(0xFF38BDF8) : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: Color(0xFF38BDF8), size: 18)
                              : null,
                          onTap: () => widget.onCountrySelected(country),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
