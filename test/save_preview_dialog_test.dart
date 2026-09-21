import 'dart:typed_data';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:spritescut/widgets/save_preview_dialog.dart';

Uint8List makePng(int r, int g, int b, {int size = 8}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

List<SaveFrame> makeFrames(int count, {int size = 8}) => [
  for (var i = 0; i < count; i++)
    (
      name: 'dino_4_2_${i + 1}.png',
      bytes: makePng((i * 60) % 256, 0, 0, size: size),
    ),
];

List<({int w, int h})> makeSizes(List<int> sizes) => [
  for (final s in sizes) (w: s, h: s),
];

/// 다이얼로그를 단독으로 띄운다.
Future<void> pumpDialog(
  WidgetTester tester, {
  required List<SaveFrame> frames,
  required List<({int w, int h})> sizes,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SavePreviewDialog(
          baseName: 'dino_4_2',
          frames: frames,
          sizes: sizes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 폴더 모드에서 프레임 타일을 길게 눌러 [to]로 드래그한다.
Future<void> longPressDrag(WidgetTester tester, Finder from, Finder to) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  await gesture.moveTo(tester.getCenter(to));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// [add-folder] → 이름 입력 → 확인 까지 폴더를 만든다.
Future<void> createFolder(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const ValueKey('add-folder')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('folder-name-field')),
    name,
  );
  await tester.tap(find.byKey(const ValueKey('folder-name-ok')));
  await tester.pumpAndSettle();
  // 폴더 생성 스낵바(타이머)가 남지 않도록 충분히 흘려보낸다.
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('모든 컷을 그리드로 표시한다', (tester) async {
    await pumpDialog(tester, frames: makeFrames(3), sizes: makeSizes([8, 8, 8]));

    expect(find.text('3컷'), findsOneWidget);
    expect(find.textContaining('dino_4_2_1.png'), findsOneWidget);
    expect(find.textContaining('dino_4_2_2.png'), findsOneWidget);
    expect(find.textContaining('dino_4_2_3.png'), findsOneWidget);
    expect(find.text('다운로드 (ZIP)'), findsOneWidget);

    // 폴더 정리가 기본 켜져 있어 사이드바가 보인다 (사용자 폴더는 0개).
    expect(find.byKey(const ValueKey('folder-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder-root')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder-0')), findsNothing);
  });

  testWidgets('사진 탭 → 삭제 버튼 표시 → 삭제하면 연속 번호로 재배열된다 (레거시 모드)', (tester) async {
    await pumpDialog(tester, frames: makeFrames(3), sizes: makeSizes([8, 8, 8]));

    // 삭제 오버레이는 레거시(폴더 OFF) UX — 스위치를 끄고 확인한다.
    await tester.tap(find.byKey(const ValueKey('folders-switch')));
    await tester.pumpAndSettle();

    // 아직 삭제 버튼은 보이지 않는다
    expect(find.text('삭제'), findsNothing);

    // 중간 컷(2번) 탭 → 단일 선택 → 삭제 버튼 표시
    await tester.tap(find.byKey(const ValueKey('tile-1')));
    await tester.pump();
    expect(find.text('삭제'), findsOneWidget);

    // 삭제 실행 → 2컷만 남고 이름이 연속으로 재배열
    await tester.tap(find.byKey(const ValueKey('delete-1')));
    await tester.pump();

    expect(find.text('2컷'), findsOneWidget);
    expect(find.text('(삭제 1)'), findsOneWidget);
    expect(find.textContaining('dino_4_2_1.png'), findsOneWidget);
    expect(find.textContaining('dino_4_2_2.png'), findsOneWidget);
    expect(find.textContaining('dino_4_2_3.png'), findsNothing);
    expect(find.text('삭제'), findsNothing);
  });

  testWidgets('다운로드 버튼은 삭제 후 남은 프레임을 루트 그룹으로 반환한다', (tester) async {
    List<SaveGroup>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<List<SaveGroup>>(
                    context: context,
                    builder: (_) => SavePreviewDialog(
                      baseName: 'dino_4_2',
                      frames: makeFrames(3),
                      sizes: makeSizes([8, 8, 8]),
                    ),
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    // 레거시(폴더 OFF) 모드로 전환해 탭→삭제 오버레이 사용
    await tester.tap(find.byKey(const ValueKey('folders-switch')));
    await tester.pumpAndSettle();

    // 첫 컷 삭제
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('delete-0')));
    await tester.pump();

    // 다운로드 → 폴더가 없으므로 전부 루트('') 그룹으로 반환
    await tester.tap(find.text('다운로드 (ZIP)'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.length, 1);
    expect(result![0].folder, '');
    final rest = result![0].frames;
    expect(rest.length, 2);
    expect(rest[0].name, 'dino_4_2_1.png');
    expect(rest[1].name, 'dino_4_2_2.png');
  });

  testWidgets('취소하면 null이 반환된다', (tester) async {
    List<SaveGroup>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<List<SaveGroup>>(
                    context: context,
                    builder: (_) => SavePreviewDialog(
                      baseName: 'dino_4_2',
                      frames: makeFrames(2),
                      sizes: makeSizes([8, 8]),
                    ),
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('폴더 정리 스위치로 사이드바를 켜고 끌 수 있다', (tester) async {
    await pumpDialog(
      tester,
      frames: makeFrames(2),
      sizes: makeSizes([8, 4]),
    );

    // 기본: 켜짐
    expect(find.byKey(const ValueKey('folder-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder-root')), findsOneWidget);

    // 끄면 사이드바(전체 보기/기본)가 사라진다
    await tester.tap(find.byKey(const ValueKey('folders-switch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('folder-all')), findsNothing);
    expect(find.byKey(const ValueKey('folder-root')), findsNothing);

    // 다시 켜면 복귀
    await tester.tap(find.byKey(const ValueKey('folders-switch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('folder-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder-root')), findsOneWidget);
  });

  testWidgets('폴더 추가로 빈 폴더를 만들 수 있다', (tester) async {
    await pumpDialog(tester, frames: makeFrames(3), sizes: makeSizes([8, 8, 8]));

    // 처음에는 사용자 폴더가 없다
    expect(find.byKey(const ValueKey('folder-0')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('add-folder')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('folder-name-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('folder-name-field')),
      '공격',
    );
    await tester.tap(find.byKey(const ValueKey('folder-name-ok')));
    await tester.pumpAndSettle();

    // 폴더가 생기고 사이드바에 표시된다
    expect(find.byKey(const ValueKey('folder-0')), findsOneWidget);
    expect(find.text('공격'), findsOneWidget);

    // 폴더 생성 스낵바(타이머)가 남지 않도록 흘려보낸다.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('같은 이름의 폴더는 만들 수 없다', (tester) async {
    await pumpDialog(tester, frames: makeFrames(2), sizes: makeSizes([8, 8]));

    await createFolder(tester, '새 폴더 1');
    expect(find.byKey(const ValueKey('folder-0')), findsOneWidget);

    // 중복 이름으로 추가 시도 → 확인 버튼 눌러도 거부
    await tester.tap(find.byKey(const ValueKey('add-folder')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('folder-name-field')),
      '새 폴더 1',
    );
    await tester.tap(find.byKey(const ValueKey('folder-name-ok')));
    await tester.pump();

    expect(
      find.text('같은 이름의 폴더가 이미 있습니다.'),
      findsOneWidget,
    );

    // 취소하면 폴더가 추가되지 않는다
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('취소'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('folder-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder-1')), findsNothing);
  });

  testWidgets('폴더 이름을 변경해도 이미지 배정이 유지된다', (tester) async {
    await pumpDialog(tester, frames: makeFrames(3), sizes: makeSizes([8, 8, 8]));

    await createFolder(tester, '공격');

    // 0번 컷을 폴더로 이동
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    await longPressDrag(
      tester,
      find.byKey(const ValueKey('tile-0')),
      find.byKey(const ValueKey('folder-0')),
    );
    expect(find.byKey(const ValueKey('tile-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-1')), findsNothing);

    // 이름 변경
    await tester.tap(find.byKey(const ValueKey('rename-folder-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('folder-name-field')),
      '보스',
    );
    await tester.tap(find.byKey(const ValueKey('folder-name-ok')));
    await tester.pumpAndSettle();

    expect(find.text('보스'), findsOneWidget);
    expect(find.text('공격'), findsNothing);

    // 변경 후에도 폴더 안 이미지가 유지된다
    expect(find.byKey(const ValueKey('tile-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-1')), findsNothing);
  });

  testWidgets('폴더 삭제 시 안의 이미지는 루트로 이동한다', (tester) async {
    await pumpDialog(tester, frames: makeFrames(3), sizes: makeSizes([8, 8, 8]));

    await createFolder(tester, '임시');

    // 0번 컷을 폴더로 이동
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    await longPressDrag(
      tester,
      find.byKey(const ValueKey('tile-0')),
      find.byKey(const ValueKey('folder-0')),
    );
    expect(find.byKey(const ValueKey('tile-1')), findsNothing);

    // 삭제 확인 다이얼로그
    await tester.tap(find.byKey(const ValueKey('delete-folder-0')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('기본(폴더 없음)으로 이동합니다'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('folder-delete-ok')));
    await tester.pumpAndSettle();

    // 폴더가 사라지고 루트 보기에서 모든 이미지가 다시 보인다
    expect(find.byKey(const ValueKey('folder-0')), findsNothing);
    expect(find.byKey(const ValueKey('tile-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-2')), findsOneWidget);
  });

  testWidgets('멀티 선택 후 드래그하면 선택 프레임이 폴더로 일괄 이동한다', (tester) async {
    await pumpDialog(
      tester,
      frames: makeFrames(3),
      sizes: makeSizes([8, 4, 8]),
    );

    await createFolder(tester, '이동');

    // 선택 모드 켜고 1·2번 컷 선택
    await tester.tap(find.byKey(const ValueKey('select-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tile-1')));
    await tester.pump();

    // 폴더로 드래그 → 폴더 보기로 전환되어 이동한 컷만 보인다
    await longPressDrag(
      tester,
      find.byKey(const ValueKey('tile-0')),
      find.byKey(const ValueKey('folder-0')),
    );

    expect(find.byKey(const ValueKey('tile-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-2')), findsNothing);
  });

  testWidgets('기본(폴더 없음)으로 드래그하면 이미지가 루트로 돌아간다', (tester) async {
    await pumpDialog(tester, frames: makeFrames(2), sizes: makeSizes([8, 8]));

    await createFolder(tester, '이동');

    // 0번 컷을 폴더로 이동
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    await longPressDrag(
      tester,
      find.byKey(const ValueKey('tile-0')),
      find.byKey(const ValueKey('folder-0')),
    );
    expect(find.byKey(const ValueKey('tile-1')), findsNothing);

    // 루트 드롭존으로 다시 드래그
    await longPressDrag(
      tester,
      find.byKey(const ValueKey('tile-0')),
      find.byKey(const ValueKey('folder-root')),
    );

    expect(find.byKey(const ValueKey('tile-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-1')), findsOneWidget);
  });

  testWidgets('ZIP 저장 시 사용자 폴더명이 하위 폴더로 반영된다', (tester) async {
    List<SaveGroup>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<List<SaveGroup>>(
                    context: context,
                    builder: (_) => SavePreviewDialog(
                      baseName: 'dino_4_2',
                      frames: makeFrames(3),
                      sizes: makeSizes([8, 8, 8]),
                    ),
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    // 폴더를 만들고 0·1번 컷을 그 안으로 이동
    await createFolder(tester, '공격');

    await tester.tap(find.byKey(const ValueKey('select-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tile-1')));
    await tester.pump();

    await longPressDrag(
      tester,
      find.byKey(const ValueKey('tile-0')),
      find.byKey(const ValueKey('folder-0')),
    );

    // 다운로드 → 루트(1컷) + 공격 폴더(2컷) 구조
    await tester.tap(find.text('다운로드 (ZIP)'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.length, 2);
    expect(result![0].folder, '');
    expect(result![0].frames.length, 1);
    expect(result![0].frames[0].name, 'dino_4_2_1.png');
    expect(result![1].folder, '공격');
    expect(result![1].frames.length, 2);
    expect(result![1].frames[0].name, 'dino_4_2_1.png');
    expect(result![1].frames[1].name, 'dino_4_2_2.png');
  });

  testWidgets('폴더 모드에서 선택하면 삭제 오버레이 대신 이동 버튼이 보인다', (tester) async {
    await pumpDialog(tester, frames: makeFrames(2), sizes: makeSizes([8, 8]));

    await createFolder(tester, '공격');

    // 탭해도 삭제 오버레이는 표시되지 않는다
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    expect(find.text('삭제'), findsNothing);

    // 선택 상태에서는 [이동]/[선택 삭제] 버튼이 나타난다
    expect(find.byKey(const ValueKey('move-selected')), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-selected')), findsOneWidget);
  });

  testWidgets('선택 후 [이동] 버튼으로 폴더에 넣는다', (tester) async {
    await pumpDialog(tester, frames: makeFrames(3), sizes: makeSizes([8, 8, 8]));

    await createFolder(tester, '공격');

    // 선택 모드에서 0·1번 컷 선택
    await tester.tap(find.byKey(const ValueKey('select-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tile-1')));
    await tester.pump();

    // [이동] → 대상 폴더 선택 다이얼로그
    await tester.tap(find.byKey(const ValueKey('move-selected')));
    await tester.pumpAndSettle();
    expect(find.text('이동할 폴더 선택'), findsOneWidget);
    expect(find.byKey(const ValueKey('move-target-root')), findsOneWidget);
    expect(find.byKey(const ValueKey('move-target-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('move-target-0')));
    await tester.pumpAndSettle();

    // 폴더 보기로 전환되어 이동한 컷만 보인다
    expect(find.byKey(const ValueKey('tile-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-2')), findsNothing);
  });

  testWidgets('선택 후 [이동]으로 기본(폴더 없음)에 되돌린다', (tester) async {
    await pumpDialog(tester, frames: makeFrames(2), sizes: makeSizes([8, 8]));

    await createFolder(tester, '이동');

    // 0번 컷을 폴더로 이동
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    await longPressDrag(
      tester,
      find.byKey(const ValueKey('tile-0')),
      find.byKey(const ValueKey('folder-0')),
    );
    expect(find.byKey(const ValueKey('tile-1')), findsNothing);

    // 폴더 안에서 다시 선택 후 [이동] → 기본(폴더 없음)
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('move-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('move-target-root')));
    await tester.pumpAndSettle();

    // 루트 보기로 전환되어 모든 이미지가 다시 보인다
    expect(find.byKey(const ValueKey('tile-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-1')), findsOneWidget);
  });

  testWidgets('선택 삭제 버튼으로 여러 프레임을 한 번에 삭제한다', (tester) async {
    await pumpDialog(tester, frames: makeFrames(3), sizes: makeSizes([8, 8, 8]));

    // 선택 모드에서 1번, 3번 컷 선택
    await tester.tap(find.byKey(const ValueKey('select-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tile-2')));
    await tester.pump();

    // 선택 삭제 버튼이 나타나고, 실행하면 1컷만 남는다
    expect(find.byKey(const ValueKey('delete-selected')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-selected')));
    await tester.pumpAndSettle();

    expect(find.text('1컷'), findsOneWidget);
    expect(find.textContaining('dino_4_2_1.png'), findsOneWidget);
    expect(find.textContaining('dino_4_2_2.png'), findsNothing);
    expect(find.textContaining('dino_4_2_3.png'), findsNothing);
  });
}