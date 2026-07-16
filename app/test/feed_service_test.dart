import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:naduri_alimi/services/feed_service.dart';

import 'feed_parse_test.dart' show sampleFeed;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('naduri_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  File cacheFile() => File('${tmp.path}/feed_cache.json');

  test('네트워크 성공 → 파싱 + 캐시 저장', () async {
    final svc = FeedService(
      client: MockClient((req) async => http.Response.bytes(utf8.encode(sampleFeed), 200)),
      cacheFile: cacheFile(),
    );
    final r = await svc.load();
    expect(r.fromCache, false);
    expect(r.feed.events.length, 2);
    expect(await cacheFile().exists(), true);
  });

  test('네트워크 실패 → 캐시 폴백(fromCache=true)', () async {
    await cacheFile().writeAsString(sampleFeed);
    final svc = FeedService(
      client: MockClient((req) async => http.Response('', 500)),
      cacheFile: cacheFile(),
    );
    final r = await svc.load();
    expect(r.fromCache, true);
    expect(r.feed.events.length, 2);
  });

  test('네트워크 실패 + 캐시 없음 → 예외', () async {
    final svc = FeedService(
      client: MockClient((req) async => throw const SocketException('offline')),
      cacheFile: cacheFile(),
    );
    expect(svc.load(), throwsA(anything));
  });

  test('캐시 파손 → null 취급(예외 아님)', () async {
    await cacheFile().writeAsString('{broken json');
    final svc = FeedService(client: MockClient((req) async => http.Response('', 500)), cacheFile: cacheFile());
    expect(await svc.loadFromCache(), isNull);
  });

  test('한글이 content-type 헤더 없이도 안 깨진다 (bodyBytes UTF-8 명시 디코드)', () async {
    final svc = FeedService(
      client: MockClient((req) async => http.Response.bytes(utf8.encode(sampleFeed), 200)),
      cacheFile: cacheFile(),
    );
    final r = await svc.load();
    expect(r.feed.events[0].title, '어린이 인형극');
  });
}
