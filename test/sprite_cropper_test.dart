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

    test('calcSpriteSize: 좌우 여백을 제외한 활성 폭으로 1컷 너비 계산', () {
      const s = CropSettings(
        horizontalCount: 4,
        verticalCount: 1,
        leftPadding: 16,
        rightPadding: 16,
      );
      final sprite = s.calcSpriteSize(imageWidth: 256, imageHeight: 64);
      // (256 - 16 - 16) / 4 = 56
      expect((sprite.spriteWidth, sprite.spriteHeight), (56, 64));
    });

    test('cropRectFor: 좌측 여백만큼 자르기 시작 위치가 이동한다', () {
      const s = CropSettings(horizontalCount: 4, verticalCount: 1, leftPadding: 16);
      final r0 = s.cropRectFor(0, 256, 64);
      final r1 = s.cropRectFor(1, 256, 64);
      // spriteWidth = (256 - 16) / 4 = 60
      expect((r0.x, r0.y), (16, 0));
      expect((r1.x, r1.y), (76, 0));
    });

    test('cropRectFor: 좌우 여백만큼 마지막 컷이 이미지 경계 안에 들어온다', () {
      const s = CropSettings(
        horizontalCount: 4,
        verticalCount: 1,
        leftPadding: 10,
        rightPadding: 10,
      );
      final last = s.cropRectFor(3, 256, 64);
      // spriteWidth = (256 - 20) / 4 = 59
      expect(last.x + last.width, 10 + 4 * 59);
    });

    test('withEqualBoundaries: 256×64 이미지 4×1 분할 시 경계 = [0,64,128,192,256]', () {
      const s = CropSettings(horizontalCount: 4, verticalCount: 1);
      final manual = s.withEqualBoundaries(imageWidth: 256, imageHeight: 64);
      expect(manual.useManualBoundaries, isTrue);
      expect(manual.columnBoundaries, [0, 64, 128, 192, 256]);
      expect(manual.rowBoundaries, [0, 64]);
      expect(manual.totalCount, 4);
    });

    test('withEqualBoundaries: 여백을 반영한 균등 경계 생성', () {
      const s = CropSettings(
        horizontalCount: 4,
        verticalCount: 2,
        leftPadding: 10,
        rightPadding: 10,
        topPadding: 8,
        bottomPadding: 8,
      );
      final manual = s.withEqualBoundaries(imageWidth: 256, imageHeight: 64);
      expect(manual.columnBoundaries, [10, 69, 128, 187, 246]);
      expect(manual.rowBoundaries, [8, 32, 56]);
    });

    test('수동 경계 totalCount/effectiveCount는 경계 개수에서 파생된다', () {
      const s = CropSettings(
        horizontalCount: 4,
        verticalCount: 2,
        useManualBoundaries: true,
        columnBoundaries: [0, 40, 100, 190],
        rowBoundaries: [0, 30, 50],
      );
      expect(s.effectiveHorizontalCount, 3);
      expect(s.effectiveVerticalCount, 2);
      expect(s.totalCount, 6);
    });

    test('cropRectFor: 수동 경계 위치대로 잘라낸다', () {
      const s = CropSettings(
        horizontalCount: 4,
        verticalCount: 2,
        useManualBoundaries: true,
        columnBoundaries: [0, 40, 100, 190],
        rowBoundaries: [0, 30, 50],
      );
      final r0 = s.cropRectFor(0, 256, 64);
      expect((r0.x, r0.y, r0.width, r0.height), (0, 0, 40, 30));
      final r1 = s.cropRectFor(1, 256, 64);
      expect((r1.x, r1.y, r1.width, r1.height), (40, 0, 60, 30));
      final r4 = s.cropRectFor(4, 256, 64);
      expect((r4.x, r4.y, r4.width, r4.height), (40, 30, 60, 20));
      final r5 = s.cropRectFor(5, 256, 64);
      expect((r5.x, r5.y, r5.width, r5.height), (100, 30, 90, 20));
    });

    test('withUpdatedColumnBoundary: 인접 경계 사이로만 clamp된다', () {
      const s = CropSettings(
        horizontalCount: 4,
        verticalCount: 1,
        useManualBoundaries: true,
        columnBoundaries: [0, 64, 128, 192, 256],
        rowBoundaries: [0, 64],
      );
      // 중간 경계를 인접 경계 밖으로 밀어도 clamp
      final a = s.withUpdatedColumnBoundary(2, 500, imageWidth: 256);
      expect(a.columnBoundaries[2], 192 - 10); // 오른쪽(192) - 최소간격(10)
      final b = s.withUpdatedColumnBoundary(2, -50, imageWidth: 256);
      expect(b.columnBoundaries[2], 64 + 10); // 왼쪽(64) + 최소간격(10)
      // 외곽 경계 0번은 0 ~ (다음-10)
      final c = s.withUpdatedColumnBoundary(0, -100, imageWidth: 256);
      expect(c.columnBoundaries[0], 0);
      // 외곽 경계 마지막은 (이전+10) ~ imageWidth
      final d = s.withUpdatedColumnBoundary(4, 999, imageWidth: 256);
      expect(d.columnBoundaries[4], 256);
    });

    test('frameSizeRange: 수동 모드에서 프레임별 최소/최대 크기를 반환한다', () {
      const s = CropSettings(
        horizontalCount: 4,
        verticalCount: 2,
        useManualBoundaries: true,
        columnBoundaries: [0, 40, 100, 190],
        rowBoundaries: [0, 30, 50],
      );
      final range = s.frameSizeRange(imageWidth: 256, imageHeight: 64);
      expect(range.minWidth, 40);
      expect(range.maxWidth, 90);
      expect(range.minHeight, 20);
      expect(range.maxHeight, 30);
    });
  });

  group('프레임별 크롭 오버라이드', () {
    test('withFrameRect는 해당 프레임의 크롭 영역만 변경한다', () {
      const s = CropSettings(horizontalCount: 4, verticalCount: 1);
      final s2 = s.withFrameRect(1, rect: (x: 50, y: 0, width: 40, height: 64));

      expect(s2.cropRectFor(0, 256, 64), (x: 0, y: 0, width: 64, height: 64));
      expect(s2.cropRectFor(1, 256, 64), (x: 50, y: 0, width: 40, height: 64));
      expect(s2.cropRectFor(2, 256, 64), (x: 128, y: 0, width: 64, height: 64));
      expect(s2.cropRectFor(3, 256, 64), (x: 192, y: 0, width: 64, height: 64));
    });

    test('withFrameRect(null)은 해당 프레임을 기본값으로 되돌린다', () {
      const s = CropSettings(horizontalCount: 2, verticalCount: 1);
      final overridden = s.withFrameRect(0, rect: (x: 0, y: 0, width: 30, height: 64));
      expect(overridden.cropRectFor(0, 128, 64), (x: 0, y: 0, width: 30, height: 64));

      final restored = overridden.withFrameRect(0, rect: null);
      expect(restored.cropRectFor(0, 128, 64), (x: 0, y: 0, width: 64, height: 64));
    });

    test('clearFrameRects는 모든 오버라이드를 제거한다', () {
      const s = CropSettings(horizontalCount: 2, verticalCount: 1);
      final overridden = s.withFrameRect(1, rect: (x: 70, y: 0, width: 50, height: 64));
      expect(overridden.frameRects.where((r) => r != null).length, 1);

      final cleared = overridden.clearFrameRects();
      expect(cleared.frameRects, isEmpty);
      expect(cleared.cropRectFor(1, 128, 64), (x: 64, y: 0, width: 64, height: 64));
    });

    test('frameRectFor는 오버라이드가 없으면 계산된 기본 rect를 반환한다', () {
      const s = CropSettings(horizontalCount: 2, verticalCount: 2);
      expect(s.frameRectFor(1, 128, 128), (x: 64, y: 0, width: 64, height: 64));

      final overridden = s.withFrameRect(1, rect: (x: 60, y: 0, width: 40, height: 80));
      expect(overridden.frameRectFor(1, 128, 128), (x: 60, y: 0, width: 40, height: 80));
    });

    test('clampFrameRect는 이미지 경계와 최소 크기를 보장한다', () {
      final r = CropSettings.clampFrameRect(
        x: 300,
        y: 300,
        width: 500,
        height: 80,
        imageWidth: 256,
        imageHeight: 64,
      );
      expect(r.width, 256);
      expect(r.height, 64);
      expect(r.x, 0);
      expect(r.y, 0);
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

    test('cropFrames는 프레임별 오버라이드 크롭 크기를 반영한다', () {
      final sheet = makeSheet(128, 64);
      var settings = const CropSettings(horizontalCount: 2, verticalCount: 1);
      settings = settings.withFrameRect(1, rect: (x: 64, y: 8, width: 64, height: 48));

      final frames = SpriteCropper.cropFrames(sourceBytes: encodePng(sheet), settings: settings);
      expect(frames.length, 2);

      final f0 = img.decodePng(frames[0].bytes)!;
      expect((f0.width, f0.height), (64, 64));

      final f1 = img.decodePng(frames[1].bytes)!;
      expect((f1.width, f1.height), (64, 48));

      // 1번(0-index) 프레임 좌상단 픽셀이 원본 (64, 8) 위치와 일치해야 한다.
      final src = sheet.getPixel(64, 8);
      final dst = f1.getPixel(0, 0);
      expect(dst.r, src.r);
      expect(dst.g, src.g);
      expect(dst.b, src.b);
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

    test('buildZip은 extraFiles(stage.jpg)를 ZIP 루트에 포함한다', () {
      final sheet = makeSheet(128, 128);
      final frames = SpriteCropper.cropFrames(
        sourceBytes: encodePng(sheet),
        settings: const CropSettings(horizontalCount: 2, verticalCount: 1),
      );
      final stageBytes = Uint8List.fromList([1, 2, 3, 4]);

      final zip = SpriteCropper.buildZip(
        frames,
        previewHtml: 'preview',
        extraFiles: [(name: 'stage.jpg', bytes: stageBytes)],
      );

      final archive = ZipDecoder().decodeBytes(zip);
      final names = archive.files.map((f) => f.name).toList();
      expect(names, [
        'sprite_1.png',
        'sprite_2.png',
        'index.html',
        'stage.jpg',
      ]);
      expect(archive.files.last.content, stageBytes);
    });
  });
}