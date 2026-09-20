import 'dart:typed_data';

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

List<({String name, Uint8List bytes})> makeFrames(int count) => [
  for (var i = 0; i < count; i++)
    (name: 'dino_4_2_${i + 1}.png', bytes: makePng((i * 60) % 256, 0, 0)),
];

void main() {
  testWidgets('모든 컷을 그리드로 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavePreviewDialog(
            baseName: 'dino_4_2',
            frames: makeFrames(3),
            sizes: const [(w: 8, h: 8), (w: 8, h: 8), (w: 8, h: 8)],
          ),
        ),
      ),
    );

    expect(find.text('3컷'), findsOneWidget);
    expect(find.textContaining('dino_4_2_1.png'), findsOneWidget);
    expect(find.textContaining('dino_4_2_2.png'), findsOneWidget);
    expect(find.textContaining('dino_4_2_3.png'), findsOneWidget);
    expect(find.text('다운로드 (ZIP)'), findsOneWidget);
  });

  testWidgets('사진 탭 → 삭제 버튼 표시 → 삭제하면 연속 번호로 재배열된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavePreviewDialog(
            baseName: 'dino_4_2',
            frames: makeFrames(3),
            sizes: const [(w: 8, h: 8), (w: 8, h: 8), (w: 8, h: 8)],
          ),
        ),
      ),
    );

    // 아직 삭제 버튼은 보이지 않는다
    expect(find.text('삭제'), findsNothing);

    // 중간 컷(2번) 탭 → 삭제 버튼 표시
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

  testWidgets('다운로드 버튼은 삭제 후 남은 프레임을 반환한다', (tester) async {
    List<({String name, Uint8List bytes})>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result =
                      await showDialog<List<({String name, Uint8List bytes})>>(
                        context: context,
                        builder: (_) => SavePreviewDialog(
                          baseName: 'dino_4_2',
                          frames: makeFrames(3),
                          sizes: const [
                            (w: 8, h: 8),
                            (w: 8, h: 8),
                            (w: 8, h: 8),
                          ],
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

    // 첫 컷 삭제
    await tester.tap(find.byKey(const ValueKey('tile-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('delete-0')));
    await tester.pump();

    // 다운로드 → 결과 반환
    await tester.tap(find.text('다운로드 (ZIP)'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.length, 2);
    expect(result![0].name, 'dino_4_2_1.png');
    expect(result![1].name, 'dino_4_2_2.png');
  });

  testWidgets('취소하면 null이 반환된다', (tester) async {
    List<({String name, Uint8List bytes})>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result =
                      await showDialog<List<({String name, Uint8List bytes})>>(
                        context: context,
                        builder: (_) => SavePreviewDialog(
                          baseName: 'dino_4_2',
                          frames: makeFrames(2),
                          sizes: const [(w: 8, h: 8), (w: 8, h: 8)],
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
}
