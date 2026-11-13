import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Have I Been Pwned range search: only the first five hex characters of the SHA-1 leave the device.
class BreachChecker {
  BreachChecker({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final Map<String, int> _cache = {};

  static (String, String) split(String password) {
    final hash = sha1.convert(utf8.encode(password)).toString().toUpperCase();
    return (hash.substring(0, 5), hash.substring(5));
  }

  Future<int> timesSeen(String password) async {
    final (prefix, suffix) = split(password);
    final cached = _cache['$prefix$suffix'];
    if (cached != null) return cached;
    final response = await _http
        .get(Uri.parse('https://api.pwnedpasswords.com/range/$prefix'), headers: {'Add-Padding': 'true'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw http.ClientException('breach check failed (${response.statusCode})');
    var count = 0;
    for (final line in const LineSplitter().convert(response.body)) {
      final parts = line.split(':');
      if (parts.length == 2 && parts[0].trim() == suffix) count = int.tryParse(parts[1].trim()) ?? 0;
    }
    return _cache['$prefix$suffix'] = count;
  }
}
