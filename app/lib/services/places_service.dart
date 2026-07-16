/// places.json 취득 — feed_service와 같은 패턴(네트워크 + 로컬 캐시 폴백).
/// 장소 데이터는 월 1회 갱신이라 캐시 히트가 대부분이다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/place.dart';

class PlacesService {
  static const placesUrl = 'https://raw.githubusercontent.com/sooya8922/naduri-alimi/master/places.json';
  static const _cacheName = 'places_cache.json';
  static const _timeout = Duration(seconds: 15);

  final http.Client _client;
  final File? _cacheOverride;

  PlacesService({http.Client? client, File? cacheFile})
      : _client = client ?? http.Client(),
        _cacheOverride = cacheFile;

  Future<File> _cacheFile() async {
    if (_cacheOverride != null) return _cacheOverride;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_cacheName');
  }

  Future<({Places places, bool fromCache})> load() async {
    try {
      final res = await _client.get(Uri.parse(placesUrl)).timeout(_timeout);
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes);
        final places = Places.fromJson(json.decode(body) as Map<String, dynamic>);
        try {
          final f = await _cacheFile();
          final tmp = File('${f.path}.tmp');
          await tmp.writeAsString(body);
          await tmp.rename(f.path);
        } catch (_) {/* 캐시 실패는 치명 아님 */}
        return (places: places, fromCache: false);
      }
      throw HttpException('HTTP ${res.statusCode}');
    } catch (_) {
      try {
        final f = await _cacheFile();
        if (await f.exists()) {
          final cached = Places.fromJson(json.decode(await f.readAsString()) as Map<String, dynamic>);
          return (places: cached, fromCache: true);
        }
      } catch (_) {/* 캐시 파손 → 없는 셈 */}
      rethrow;
    }
  }
}
