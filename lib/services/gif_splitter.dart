import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'sprite_cropper.dart';

/// GIF의 개별 프레임 하나를 담는 모델.
class GifFrame {
  const GifFrame({required this.image, required this.durationMs});

  /// 합성(overlay/disposal 반영)된 전체 캔버스 이미지.
  final img.Image image;

  /// 프레임 표시 시간(밀리초).
  final int durationMs;

  int get width => image.width;
  int get height => image.height;

  /// 프레임을 PNG 바이트로 인코딩한다.
  Uint8List toPngBytes() => Uint8List.fromList(img.encodePng(image));
}

/// 스프라이트 시트 합성 방식.
enum SheetLayout {
  /// 가로로 일렬 (1줄 N컷)
  horizontal('가로 한 줄'),

  /// 세로로 일렬 (N줄 1컷)
  vertical('세로 한 줄'),

  /// 정사각형에 가까운 격자
  grid('격자');

  const SheetLayout(this.label);
  final String label;
}

/// GIF 애니메이션을 프레임별 스프라이트로 분할하는 서비스.
abstract final class GifSplitter {
  /// GIF 바이트를 프레임 목록으로 디코딩한다.
  ///
  /// GIF가 아니거나 단일 이미지면 예외를 던진다.
  static List<GifFrame> decode(Uint8List bytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      throw const FormatException('GIF 파일을 해석할 수 없습니다.');
    }

    // frames 비어 있으면(정적 이미지) 첫 프레임 하나만 있는 것으로 취급한다.
    final frames = decoded.frames.isEmpty ? <img.Image>[decoded] : decoded.frames;

    return [
      for (final frame in frames)
        GifFrame(
          image: frame,
          // frameDuration는 GIF centiseconds → ms로 변환된 값이다.
          durationMs: frame.frameDuration > 0 ? frame.frameDuration : 100,
        ),
    ];
  }

  /// 전체 프레임 중 불투명 픽셀의 최소/최대 경계 상자를 구한다.
  ///
  /// [alphaThreshold]보다 큰 알파 값을 가진 픽셀만 대상으로 한다.
  /// 모든 픽셀이 투명이면 null을 반환한다.
  static ({int x, int y, int width, int height})? contentBounds(
    List<img.Image> images, {
    int alphaThreshold = 0,
  }) {
    var minX = 1 << 30;
    var minY = 1 << 30;
    var maxX = -1;
    var maxY = -1;

    for (final image in images) {
      final w = image.width;
      final h = image.height;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (image.getPixel(x, y).a > alphaThreshold) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
    }

    if (maxX < minX || maxY < minY) return null;
    return (x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
  }

  /// 프레임들의 투명 영역을 잘라낸다.
  ///
  /// [bounds]가 null이면 원본 프레임을 그대로 반환한다.
  /// 잘라낸 뒤에도 셀(cell) 크기는 유지되도록 [padTo]을 지정할 수 있다.
  static List<img.Image> cropFrames(
    List<img.Image> images, {
    ({int x, int y, int width, int height})? bounds,
    ({int width, int height})? padTo,
  }) {
    if (bounds == null) return images;

    final maxW = padTo?.width ?? bounds.width;
    final maxH = padTo?.height ?? bounds.height;
    // 셀 크기는 원본 경계를 넘지 않도록 제한한다.
    final cellW = math.max(1, math.min(maxW, bounds.width));
    final cellH = math.max(1, math.min(maxH, bounds.height));

    return [
      for (final image in images)
        img.copyCrop(
          _toRgba(image),
          x: bounds.x,
          y: bounds.y,
          width: cellW,
          height: cellH,
        ),
    ];
  }

  /// 프레임들을 가로/세로/격자 형태의 스프라이트 시트 하나로 합친다.
  static img.Image composeSheet(
    List<img.Image> images, {
    required SheetLayout layout,
  }) {
    if (images.isEmpty) {
      throw const FormatException('합칠 프레임이 없습니다.');
    }

    final cellW = images.map((e) => e.width).reduce(math.max);
    final cellH = images.map((e) => e.height).reduce(math.max);

    final columns = switch (layout) {
      SheetLayout.horizontal => images.length,
      SheetLayout.vertical => 1,
      SheetLayout.grid => math.max(1, math.sqrt(images.length).ceil()),
    };
    final rows = (images.length / columns).ceil();

    final sheet = img.Image(width: cellW * columns, height: cellH * rows, numChannels: 4);

    for (var i = 0; i < images.length; i++) {
      final src = _toRgba(images[i]);
      final col = i % columns;
      final row = i ~/ columns;
      // 셀 내 중앙 정렬 (크기가 다른 프레임을 자연스럽게 맞춘다)
      final offsetX = col * cellW + ((cellW - src.width) ~/ 2);
      final offsetY = row * cellH + ((cellH - src.height) ~/ 2);
      img.compositeImage(sheet, src, dstX: offsetX, dstY: offsetY);
    }

    return sheet;
  }

  /// PNG 시트 시트를 Uint8List로 인코딩한다.
  static Uint8List encodeSheet(
    List<img.Image> images, {
    required SheetLayout layout,
  }) => Uint8List.fromList(img.encodePng(composeSheet(images, layout: layout)));

  /// 프레임 PNG 파일명 목록을 만든다. (번호는 1부터)
  static List<String> frameFileNames({
    required String namePrefix,
    required int count,
    int digits = 4,
  }) {
    final base = SpriteCropper.sanitizeName(namePrefix);
    final pad = count > 9999 ? 5 : digits;
    return [
      for (var i = 0; i < count; i++)
        '$base${i.toString().padLeft(pad, '0')}.png',
    ];
  }

  /// 팔레트 이미지를 RGBA로 변환한다 (이미 RGBA면 그대로 반환).
  static img.Image _toRgba(img.Image image) {
    if (image.numChannels == 4) return image;
    return image.convert(numChannels: 4);
  }
}
