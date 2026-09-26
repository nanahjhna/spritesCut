import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:spritescut/services/gif_splitter.dart';

/// 4프레임짜리 테스트용 GIF를 만든다. 각 프레임은 지정한 색 사각형이다.
Uint8List _fakeGif({
  required List<({int r, int g, int b})> frameColors,
  int width = 40,
  int height = 40,
  int inset = 10,
}) {
  final encoder = img.GifEncoder()..repeat = 0;
  for (final c in frameColors) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    // 투명 여백 + 가운데 색 사각형
    img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      image,
      x1: inset,
      y1: inset,
      x2: width - inset,
      y2: height - inset,
      color: img.ColorRgba8(c.r, c.g, c.b, 255),
    );
    encoder.addFrame(image, duration: 10);
  }
  return Uint8List.fromList(encoder.finish()!);
}

void main() {
  group('GifSplitter.decode', () {
    test('GIF 바이트에서 모든 프레임을 추출한다', () {
      final bytes = _fakeGif(
        frameColors: [
          (r: 255, g: 0, b: 0),
          (r: 0, g: 255, b: 0),
          (r: 0, g: 0, b: 255),
        ],
      );

      final frames = GifSplitter.decode(bytes);

      expect(frames.length, 3);
      for (final frame in frames) {
        expect(frame.width, 40);
        expect(frame.height, 40);
        expect(frame.durationMs, 100); // 10 * 1/100초 = 100ms
      }
    });

    test('GIF가 아니면 FormatException을 던진다', () {
      final notGif = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(
        () => GifSplitter.decode(notGif),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('GifSplitter.contentBounds', () {
    test('불투명 픽셀의 최소 경계 상자를 구한다', () {
      final a = img.Image(width: 40, height: 40, numChannels: 4);
      img.fillRect(
        a,
        x1: 10,
        y1: 10,
        x2: 29,
        y2: 29,
        color: img.ColorRgba8(255, 0, 0, 255),
      );

      final bounds = GifSplitter.contentBounds([a]);

      expect(bounds, isNotNull);
      expect(bounds!.x, 10);
      expect(bounds.y, 10);
      expect(bounds.width, 20);
      expect(bounds.height, 20);
    });

    test('모든 픽셀이 투명이면 null을 반환한다', () {
      final empty = img.Image(width: 8, height: 8, numChannels: 4);
      expect(GifSplitter.contentBounds([empty]), isNull);
    });
  });

  group('GifSplitter.cropFrames', () {
    test('bounds가 주어지면 해당 영역으로 모든 프레임을 자른다', () {
      final frames = [
        for (var i = 0; i < 3; i++)
          img.Image(width: 40, height: 40, numChannels: 4)
            ..setPixelRgba(5, 5, 255, 0, 0, 255)
            ..setPixelRgba(20, 20, 0, 255, 0, 255),
      ];

      final cropped = GifSplitter.cropFrames(
        frames,
        bounds: (x: 5, y: 5, width: 16, height: 16),
      );

      expect(cropped.length, 3);
      for (final image in cropped) {
        expect(image.width, 16);
        expect(image.height, 16);
      }
    });

    test('bounds가 null이면 원본 프레임을 그대로 반환한다', () {
      final frames = [img.Image(width: 12, height: 8, numChannels: 4)];
      expect(GifSplitter.cropFrames(frames, bounds: null), same(frames));
    });
  });

  group('GifSplitter.composeSheet', () {
    test('가로 한 줄 레이아웃은 프레임을 좌우로 이어붙인다', () {
      final frames = [
        for (var i = 0; i < 4; i++)
          img.Image(width: 10, height: 6, numChannels: 4)
            ..setPixelRgba(0, 0, 255, 0, 0, 255),
      ];

      final sheet = GifSplitter.composeSheet(frames, layout: SheetLayout.horizontal);

      expect(sheet.width, 40);
      expect(sheet.height, 6);
    });

    test('세로 한 줄 레이아웃은 프레임을 위아래로 이어붙인다', () {
      final frames = [
        for (var i = 0; i < 3; i++)
          img.Image(width: 10, height: 6, numChannels: 4)
            ..setPixelRgba(0, 0, 255, 0, 0, 255),
      ];

      final sheet = GifSplitter.composeSheet(frames, layout: SheetLayout.vertical);

      expect(sheet.width, 10);
      expect(sheet.height, 18);
    });

    test('격자 레이아웃은 프레임 수에 맞는 정사각형 격자를 만든다', () {
      final frames = [
        for (var i = 0; i < 9; i++)
          img.Image(width: 10, height: 6, numChannels: 4)
            ..setPixelRgba(0, 0, 255, 0, 0, 255),
      ];

      final sheet = GifSplitter.composeSheet(frames, layout: SheetLayout.grid);

      // 9컷 → 3×3 격자
      expect(sheet.width, 30);
      expect(sheet.height, 18);
    });

    test('서로 다른 크기의 프레임은 가장 큰 셀에 중앙 정렬된다', () {
      final small = img.Image(width: 4, height: 4, numChannels: 4)
        ..setPixelRgba(0, 0, 0, 255, 255, 255);
      final large = img.Image(width: 10, height: 8, numChannels: 4)
        ..setPixelRgba(0, 0, 0, 255, 255, 255);

      final sheet = GifSplitter.composeSheet([small, large], layout: SheetLayout.horizontal);

      // 셀은 최대 크기(10×8) 기준
      expect(sheet.width, 20);
      expect(sheet.height, 8);
    });

    test('프레임이 없으면 FormatException을 던진다', () {
      expect(
        () => GifSplitter.composeSheet([], layout: SheetLayout.grid),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('GifSplitter.frameFileNames', () {
    test('번호를 0부터 네 자리로 채운 파일명을 만든다', () {
      final names = GifSplitter.frameFileNames(
        namePrefix: 'walk',
        count: 3,
      );

      expect(names, ['walk0000.png', 'walk0001.png', 'walk0002.png']);
    });

    test('파일명에 안전하지 않은 문자를 치환한다', () {
      final names = GifSplitter.frameFileNames(
        namePrefix: 'my walk/run?',
        count: 1,
      );

      expect(names.first, 'my_walk_run0000.png');
    });
  });

  test('실제 GIF 분할 → 시트 합성 → PNG 인코딩이 end-to-end로 동작한다', () {
    final bytes = _fakeGif(
      frameColors: [
        (r: 255, g: 0, b: 0),
        (r: 0, g: 255, b: 0),
        (r: 0, g: 0, b: 255),
        (r: 255, g: 255, b: 0),
      ],
    );

    final frames = GifSplitter.decode(bytes);
    expect(frames.length, 4);

    final sheetBytes = GifSplitter.encodeSheet(
      [for (final f in frames) f.image],
      layout: SheetLayout.horizontal,
    );
    final decodedSheet = img.decodePng(sheetBytes);

    expect(decodedSheet, isNotNull);
    expect(decodedSheet!.width, 40 * 4); // 1컷 40px × 4컷
    expect(decodedSheet.height, 40);
  });
}
