// 가볼 만한 곳 탭 위젯 테스트 — 페이크 서비스 주입(네트워크/파일IO 비의존, widget_test.dart 교훈).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naduri_alimi/models/place.dart';
import 'package:naduri_alimi/screens/places_tab.dart';
import 'package:naduri_alimi/services/places_service.dart';

import 'place_parse_test.dart' show samplePlaces;

class FakePlacesService extends PlacesService {
  final bool fail;
  FakePlacesService({this.fail = false});

  @override
  Future<({Places places, bool fromCache})> load() async {
    if (fail) throw Exception('offline');
    return (places: Places.fromJson(json.decode(samplePlaces) as Map<String, dynamic>), fromCache: false);
  }
}

Widget app({bool fail = false}) =>
    MaterialApp(home: Scaffold(body: PlacesTab(service: FakePlacesService(fail: fail))));

void main() {
  testWidgets('장소 카드 렌더 + 유모차 배지', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('허브아일랜드'), findsOneWidget);
    expect(find.text('유모차'), findsOneWidget);
    expect(find.text('6세 이상'), findsOneWidget);
  });

  testWidgets('마이리얼트립 버튼 — 상품 확인된 장소(mrt 有)에만 노출', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    // 허브아일랜드(mrt 有) 상세 → 버튼 있음
    await tester.tap(find.textContaining('허브아일랜드'));
    await tester.pumpAndSettle();
    expect(find.textContaining('입장권·할인 보기'), findsOneWidget);
    expect(find.textContaining('제휴 링크'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // 시트 닫기
    await tester.pumpAndSettle();

    // 어느 박물관(mrt 無) 상세 → 버튼/대가성 문구 없음
    await tester.tap(find.text('과학·전시'));
    await tester.pump();
    await tester.tap(find.textContaining('어느 박물관'));
    await tester.pumpAndSettle();
    expect(find.textContaining('입장권·할인 보기'), findsNothing);
    expect(find.textContaining('제휴 링크'), findsNothing);
  });

  testWidgets('카테고리 그룹 필터 — 과학·전시 선택 시 박물관만', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('과학·전시'));
    await tester.pump();
    expect(find.textContaining('어느 박물관'), findsOneWidget);
    expect(find.textContaining('허브아일랜드'), findsNothing);

    await tester.tap(find.text('테마·놀이'));
    await tester.pump();
    expect(find.textContaining('허브아일랜드'), findsOneWidget);
    expect(find.textContaining('어느 박물관'), findsNothing);
  });

  testWidgets('지역 필터 — 서울 선택 시 빈 상태(샘플은 전부 경기)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('서울'));
    await tester.pump();
    expect(find.textContaining('조건에 맞는 장소가 없어요'), findsOneWidget);
  });

  testWidgets('실패 경로 — 오류 UI + 다시 시도', (tester) async {
    await tester.pumpWidget(app(fail: true));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('불러오지 못했'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  test('catGroups가 places.py 카테고리를 빠짐없이 커버(조용한 누락 방지)', () {
    // places.py가 내보내는 cat 값 전집합 — 여기 없는 값이 생기면 이 테스트를 갱신할 것
    const pipelineCats = {
      '테마파크', '워터파크', '동물원', '수족관', '천문대', '과학관',
      '박물관', '전시관', '자연휴양림', '수목원·정원', '생태습지',
      '전통체험', '공예체험', '농촌체험', '공원', '레포츠', '물놀이', '명소',
    };
    final covered = catGroups.values.expand((s) => s).toSet();
    expect(covered, pipelineCats);
  });
}
