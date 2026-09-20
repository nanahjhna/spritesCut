import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:spritescut/services/color_bg_remover.dart';

/// 흰 배경(255,255,255) + 중앙 빨간 사각형(255,0,0) 스프라이트 시트 생성.
Uint8List makeSheet({int w = 64, int h = 64}) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgba(x, y, 255, 255, 255, 255);
    }
  }
  for (var y = 20; y < 40; y++) {
    for (var x = 20; x < 40; x++) {
      image.setPixelRgba(x, y, 255, 0, 0, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('ColorBgRemover', () {
    test('단색 배경색을 자동 감지한다 (흰 배경 + 빨간 스프라이트)', () {
      final image = img.decodePng(makeSheet())!;
      final bg = ColorBgRemover.detectBackgroundColor(image);

      expect(bg, isNotNull);
      expect(bg!.r, greaterThan(200));
      expect(bg.g, greaterThan(200));
      expect(bg.b, greaterThan(200));
    });

    test('배경 픽셀은 투명(alpha 0), 스프라이트 픽셀은 유지된다', () {
      final out = ColorBgRemover.removeBackground(
        makeSheet(),
        backgroundColor: (r: 255, g: 255, b: 255),
        tolerance: 0.1,
        feather: 0.02,
      );
      final image = img.decodePng(out)!;

      // 모서리 = 배경 → 완전 투명
      expect(image.getPixel(0, 0).a, 0);
      expect(image.getPixel(image.width - 1, image.height - 1).a, 0);
      expect(image.getPixel(0, image.height - 1).a, 0);

      // 중앙 = 빨간 스프라이트 → 유지
      expect(image.getPixel(30, 30).a, 255);
      // 스프라이트 색상도 그대로 유지
      expect(image.getPixel(30, 30).r.toInt(), 255);
      expect(image.getPixel(30, 30).g.toInt(), 0);
    });

    test('tolerance가 클수록 유사한 색까지 제거된다', () {
      // 흰색에 가까운 배경만 있는 이미지 (250, 248, 252)
      final image = img.Image(width: 16, height: 16, numChannels: 4);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          image.setPixelRgba(x, y, 250, 248, 252, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodePng(image));

      final low = img.decodePng(
        ColorBgRemover.removeBackground(
          bytes,
          backgroundColor: (r: 255, g: 255, b: 255),
          tolerance: 0.005,
          feather: 0.0,
        ),
      )!;
      final high = img.decodePng(
        ColorBgRemover.removeBackground(
          bytes,
          backgroundColor: (r: 255, g: 255, b: 255),
          tolerance: 0.1,
          feather: 0.0,
        ),
      )!;

      // 낮은 오차 → 유지, 높은 오차 → 제거
      expect(low.getPixel(8, 8).a, greaterThan(0));
      expect(high.getPixel(8, 8).a, 0);
    });

    test('feather 구간의 경계 픽셀은 부분 투명 처리된다', () {
      // 흰색(255)에 근접한 회색 그라데이션 232~253
      final image = img.Image(width: 8, height: 8, numChannels: 4);
      for (var x = 0; x < 8; x++) {
        final gray = 232 + 3 * x;
        image.setPixelRgba(x, 0, gray, gray, gray, 255);
      }
      final bytes = Uint8List.fromList(img.encodePng(image));

      final out = img.decodePng(
        ColorBgRemover.removeBackground(
          bytes,
          backgroundColor: (r: 255, g: 255, b: 255),
          tolerance: 0.05,
          feather: 0.08,
        ),
      )!;

      // 배경색(255)과 거의 같은 253 → 완전 투명
      expect(out.getPixel(7, 0).a, 0);
      // 경계 픽셀 232 → 부분 투명 (둘 다 아님)
      final a0 = out.getPixel(0, 0).a;
      expect(a0, greaterThan(0));
      expect(a0, lessThan(255));
      // 부분 투명 픽셀이 최소 1개 이상 존재
      var partial = 0;
      for (var x = 0; x < 8; x++) {
        final a = out.getPixel(x, 0).a;
        if (a > 0 && a < 255) partial++;
      }
      expect(partial, greaterThan(0));
    });

    test('3채널(JPEG) 입력도 RGBA PNG로 출력되어 알파가 보존된다', () {
      // 3채널 이미지 생성 (JPEG와 동일한 채널 수)
      final image = img.Image(width: 8, height: 8, numChannels: 3);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          image.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final out = img.decodePng(
        ColorBgRemover.removeBackground(
          bytes,
          backgroundColor: (r: 255, g: 255, b: 255),
          tolerance: 0.1,
        ),
      )!;

      // RGB 3채널 입력이라도 배경 픽셀 알파가 0으로 출력됨
      expect(out.getPixel(0, 0).a, 0);
      expect(out.numChannels, 4);
    });

    test('감지 실패 시 null을 반환한다 (한 픽셀 이미지)', () {
      final image = img.Image(width: 1, height: 1, numChannels: 4);
      image.setPixelRgba(0, 0, 10, 20, 30, 255);

      expect(ColorBgRemover.detectBackgroundColor(image), isNull);
    });
  });
}
