import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import '../models/crop_settings.dart';

/// 스프라이트 시트를 프레임 단위로 잘라내고 ZIP으로 묶는 서비스.
abstract final class SpriteCropper {
  /// 원본 바이트를 이미지로 디코딩한다.
  static img.Image decode(Uint8List bytes) {
    img.Image? image;
    try {
      image = img.decodeImage(bytes);
    } catch (_) {
      image = null;
    }
    if (image == null) {
      throw const FormatException('지원하지 않는 이미지 형식입니다. (PNG/JPG 등)');
    }
    return image;
  }

  /// 특정 색상(기본값: 흰색)을 투명하게 변환한다.
  ///
  /// [targetRed], [targetGreen], [targetBlue]: 제거할 배경 색상 (RGB 0~255)
  /// [tolerance]: 오차 허용 범위 (0~255). 값이 크면 유사한 색상까지 투명화됨.
  static Uint8List removeBackgroundColor({
    required Uint8List bytes,
    int targetRed = 255,
    int targetGreen = 255,
    int targetBlue = 255,
    int tolerance = 30,
  }) {
    final image = decode(bytes);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // 목표 색상과의 차이 계산
        final rDiff = (r - targetRed).abs();
        final gDiff = (g - targetGreen).abs();
        final bDiff = (b - targetBlue).abs();

        // 허용 범위(tolerance) 이내의 색상이면 Alpha를 0(투명)으로 설정
        if (rDiff <= tolerance && gDiff <= tolerance && bDiff <= tolerance) {
          pixel.setRgba(r, g, b, 0);
        }
      }
    }

    // 투명 채널이 적용된 PNG 바이트로 인코딩하여 반환
    return Uint8List.fromList(img.encodePng(image));
  }

  /// [settings]에 따라 전체 이미지를 분할해 프레임을 잘라낸다.
  static List<({String name, Uint8List bytes})> cropFrames({
    required Uint8List sourceBytes,
    required CropSettings settings,
  }) {
    final image = decode(sourceBytes);

    final frames = <({String name, Uint8List bytes})>[];
    for (var i = 0; i < settings.totalCount; i++) {
      final r = settings.cropRectFor(i, image.width, image.height);
      final frame = img.copyCrop(
        image,
        x: r.x,
        y: r.y,
        width: r.width,
        height: r.height,
      );
      final png = img.encodePng(frame);
      frames.add((name: 'sprite_${i + 1}.png', bytes: Uint8List.fromList(png)));
    }
    return frames;
  }

  /// 잘라낸 프레임들을 하나의 ZIP 아카이브로 압축해 바이트로 돌려준다.
  static Uint8List buildZip(List<({String name, Uint8List bytes})> files) {
    final archive = Archive();
    for (final file in files) {
      archive.addFile(ArchiveFile.bytes(file.name, file.bytes));
    }
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }
}