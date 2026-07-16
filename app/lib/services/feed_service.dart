/// feed.json 취득 — 네트워크(raw.githubusercontent.com) + 로컬 파일 캐시.
/// 오프라인/타임아웃이면 캐시로 폴백. 서버가 따로 없는 앱이라 이 파일이 유일한 데이터 소스.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/event.dart';

class FeedService {
  static const feedUrl = 'https://raw.githubusercontent.com/sooya8922/naduri-alimi/master/feed.json';
  static const _cacheName = 'feed_cache.json';
  static const _timeout = Duration(seconds: 15);

  // 테스트 주입용(기본은 실제 http/앱 지원 디렉터리). 프로덕션 코드에선 넘기지 않는다.
  final http.Client _client;
  final File? _cacheOverride;

  FeedService({http.Client? client, File? cacheFile})
      : _client = client ?? http.Client(),
        _cacheOverride = cacheFile;

  Future<File> _cacheFile() async {
    if (_cacheOverride != null) return _cacheOverride;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_cacheName');
  }

  /// 항상 Feed를 돌려주려 최선을 다한다: 네트워크 → 성공 시 캐시 갱신,
  /// 실패 시 캐시 폴백, 캐시도 없으면 예외(첫 실행 + 오프라인).
  Future<({Feed feed, bool fromCache})> load() async {
    try {
      final res = await _client.get(Uri.parse(feedUrl)).timeout(_timeout);
      if (res.statusCode == 200) {
        // bodyBytes로 UTF-8 명시 디코드 (한글 — content-type 헤더에 의존하지 않음)
        final body = utf8.decode(res.bodyBytes);
        final feed = Feed.fromJson(json.decode(body) as Map<String, dynamic>);
        try {
          // 원자적 쓰기: 임시파일에 쓰고 rename → 쓰는 중 프로세스 강제종료돼도 기존 캐시 안 깨짐
          final f = await _cacheFile();
          final tmp = File('${f.path}.tmp');
          await tmp.writeAsString(body);
          await tmp.rename(f.path);
        } catch (_) {/* 캐시 실패는 치명 아님 */}
        return (feed: feed, fromCache: false);
      }
      throw HttpException('HTTP ${res.statusCode}');
    } catch (_) {
      final cached = await loadFromCache();
      if (cached != null) return (feed: cached, fromCache: true);
      rethrow;
    }
  }

  Future<Feed?> loadFromCache() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return null;
      return Feed.fromJson(json.decode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null; // 캐시 파손 → 없는 셈 친다
    }
  }
}
