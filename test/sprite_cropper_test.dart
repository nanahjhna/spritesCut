import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:spritescut/models/crop_settings.dart';
import 'package:spritescut/services/sprite_cropper.dart';

void main() {
  group('CropSettings (이미지 전체 = 박스, 가로/세로 분할 수)', () {
    test('가로 4, 세로 1 분할 시 totalCount = 4', () {
      const s = CropSettings(horizontalCount: 4, verticalCount: 1);
      expect(s.totalCount, 4);
    });

    test('가로 3, 세로 2 분할 시 totalCount = 6', () {
      const s = CropSettings(horizontalCount: 3, verticalCount: 2);
      expect(s.totalCount, 6);
    });

    test('calcSpriteSize: 256×64 이미지를 4×1 분할 시 1컷 = 64×64', () {
      const s = CropSettings(horizontalCount: 4, verticalCount: 1);
      final sprite = s.calcSpriteSize(imageWidth: 256, imageHeight: 64);
      expect((sprite.spriteWidth, sprite.spriteHeight), (64, 64));
    });

    test('calcSpriteSize: 128×256 이미지를 2×4 분할 시 1컷 = 64×64', () {
      const s = CropSettings(horizontalCount: 2, verticalCount: 4);
      final sprite = s.calcSpriteSize(imageWidth: 128, imageHeight: 256);
      expect((sprite.spriteWidth, sprite.spriteHeight), (64, 64));
    });

    test('cropRectFor: 가로 분할 시 index에 따라 x가 증가', () {
      const s = CropSettings(horizontalCount: 4, verticalCount: 1);
      final r0 = s.cropRectFor(0, 256, 64);
      final r2 = s.cropRectFor(2, 256, 64);
      expect((r0.x, r0.y, r0.width, r0.height), (0, 0, 64, 64));
      expect((r2.x, r2.y, r2.width, r2.height), (128, 0, 64, 64));
    });

    test('cropRectFor: 세로 분할 시 index에 따라 y가 증가', () {
      const s = CropSettings(horizontalCount: 1, verticalCount: 4);
      final r0 = s.cropRectFor(0, 64, 256);
      final r2 = s.cropRectFor(2, 64, 256);
      expect((r0.x, r0.y, r0.width, r0.height), (0, 0, 64, 64));
      expect((r2.x, r2.y, r2.width, r2.height), (0, 128, 64, 64));
    });

    test('cropRectFor: 2×2 분할 시 인덱스 순서 확인', () {
      const s = CropSettings(horizontalCount: 2, verticalCount: 2);
      final r0 = s.cropRectFor(0, 128, 128); // (0,0)
      final r1 = s.cropRectFor(1, 128, 128); // (64,0)
      final r2 = s.cropRectFor(2, 128, 128); // (0,64)
      final r3 = s.cropRectFor(3, 128, 128); // (64,64)
      expect((r0.x, r0.y), (0, 0));
      expect((r1.x, r1.y), (64, 0));
      expect((r2.x, r2.y), (0, 64));
      expect((r3.x, r3.y), (64, 64));
    });
  });

  group('SpriteCropper', () {
    /// (x, y)에 따라 고유한 색을 가진 테스트 이미지를 만든다.
    img.Image makeSheet(int w, int h) {
      final image = img.Image(width: w, height: h, numChannels: 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          image.setPixelRgba(x, y, (x * 13) % 256, (y * 7 + x) % 256, (x + y) % 256, 255);
        }
      }
      return image;
    }

    Uint8List encodePng(img.Image image) => Uint8List.fromList(img.encodePng(image));

    test('256×64 이미지를 4×1 분할해 4컷(64×64) 잘라낸다', () {
      final sheet = makeSheet(256, 64);
      final frames = SpriteCropper.cropFrames(
        sourceBytes: encodePng(sheet),
        settings: const CropSettings(horizontalCount: 4, verticalCount: 1),
      );

      expect(frames.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(frames[i].name, 'sprite_${i + 1}.png');

        final frame = img.decodePng(frames[i].bytes);
        expect(frame, isNotNull);
        expect(frame!.width, 64);
        expect(frame.height, 64);

        // 프레임 좌상단 픽셀이 원본의 해당 위치 픽셀과 일치해야 한다.
        final src = sheet.getPixel(i * 64, 0);
        final dst = frame.getPixel(0, 0);
        expect(dst.r, src.r);
        expect(dst.g, src.g);
        expect(dst.b, src.b);
        expect(dst.a, src.a);
      }
    });

    test('64×256 이미지를 1×4 분할해 4컷(64×64) 잘라낸다', () {
      final sheet = makeSheet(64, 256);
      final frames = SpriteCropper.cropFrames(
        sourceBytes: encodePng(sheet),
        settings: const CropSettings(horizontalCount: 1, verticalCount: 4),
      );

      expect(frames.length, 4);
      final frame = img.decodePng(frames[3].bytes)!;
      expect(frame.width, 64);
      expect(frame.height, 64);
      final src = sheet.getPixel(0, 3 * 64);
      final dst = frame.getPixel(0, 0);
      expect(dst.r, src.r);
      expect(dst.g, src.g);
      expect(dst.b, src.b);
    });

    test('128×128 이미지를 2×2 분할해 4컷(64×64) 잘라낸다', () {
      final sheet = makeSheet(128, 128);
      final frames = SpriteCropper.cropFrames(
        sourceBytes: encodePng(sheet),
        settings: const CropSettings(horizontalCount: 2, verticalCount: 2),
      );

      expect(frames.length, 4);
      for (var i = 0; i < 4; i++) {
        final frame = img.decodePng(frames[i].bytes)!;
        expect(frame.width, 64);
        expect(frame.height, 64);
      }
    });

    test('지원하지 않는 형식이면 FormatException', () {
      expect(
        () => SpriteCropper.decode(Uint8List.fromList(const [1, 2, 3, 4, 5])),
        throwsFormatException,
      );
    });

    test('buildZip은 모든 프레임을 sprite_N.png 이름으로 압축한다', () {
      final sheet = makeSheet(128, 128);
      final frames = SpriteCropper.cropFrames(
        sourceBytes: encodePng(sheet),
        settings: const CropSettings(horizontalCount: 2, verticalCount: 2),
      );

      final zip = SpriteCropper.buildZip(frames);

      final archive = ZipDecoder().decodeBytes(zip);
      expect(archive.length, 4);

      final names = archive.files.map((f) => f.name).toList();
      expect(names, ['sprite_1.png', 'sprite_2.png', 'sprite_3.png', 'sprite_4.png']);

      for (var i = 0; i < frames.length; i++) {
        expect(archive.files[i].content, frames[i].bytes);
      }
    });

    test('buildZip은 previewHtml이 주어지면 index.html을 포함한다', () {
      final sheet = makeSheet(128, 128);
      final frames = SpriteCropper.cropFrames(
        sourceBytes: encodePng(sheet),
        settings: const CropSettings(horizontalCount: 2, verticalCount: 2),
      );

      final zip = SpriteCropper.buildZip(
        frames,
        previewHtml: SpriteCropper.buildPreviewHtml(
          totalCount: 4,
          spriteWidth: 64,
          spriteHeight: 64,
        ),
      );

      final archive = ZipDecoder().decodeBytes(zip);
      expect(archive.length, 5);

      final names = archive.files.map((f) => f.name).toList();
      expect(names, [
        'sprite_1.png',
        'sprite_2.png',
        'sprite_3.png',
        'sprite_4.png',
        'index.html',
      ]);

      final html = utf8.decode(archive.files.last.content as List<int>);
      expect(html, contains('const totalFrames = 4;'));
      expect(html, contains('sprite_1.png'));
      expect(html, contains('체커보드'));
    });
  });
}