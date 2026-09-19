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