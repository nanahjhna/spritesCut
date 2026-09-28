import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// `dart:ui` 엔진(스카이아/Impeller)을 이용한 빠른 이미지 처리.
///
/// 순수 Dart(`package:image`)로 JPEG를 디코딩·PNG를 인코딩하면 사진 한 장에
/// 수 초가 걸리지만, 엔진은 C++ 구현이라 훨씬 빠르며 웹(CanvasKit)에서도
/// 동일하게 동작한다.
///
/// 이 파일의 함수들이 만드는 [ui.Image] 리소스는 **호출자가 반드시
/// `dispose()` 해야 한다.** (일괄 처리 중 리소스 누수를 막기 위해 finally 에서
/// 정리하는 것을 권장한다.)
abstract final class ImageEngine {
  /// 바이트를 엔진으로 디코딩해 [ui.Image]로 돌려준다.
  ///
  /// [targetWidth]/[targetHeight]를 주면 디코딩과 동시에 리사이즈한다
  /// (썸네일용). 반환된 이미지는 호출자가 `dispose()` 한다.
  static Future<ui.Image> decodeImage(
    Uint8List bytes, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (image.width <= 0 || image.height <= 0) {
        image.dispose();
        throw const FormatException('이미지를 디코딩할 수 없습니다.');
      }
      return image;
    } finally {
      // 프레임 이미지는 코덱 dispose 이후에도 유효하고, 여기서는
      // buffer/descriptor/codec 만 정리한다.
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// [image]의 픽셀을 raw RGBA(straight alpha) 바이트로 돌려준다.
  ///
  /// 구형 환경에서 `rawStraightRgba`를 지원하지 않으면 자동으로
  /// `rawRgba`(premultiplied)로 폴백한다. 불투명한 사진은 차이가 없다.
  static Future<Uint8List> rgbaFrom(ui.Image image, {bool straight = true}) async {
    try {
      final data = await image.toByteData(
        format: straight
            ? ui.ImageByteFormat.rawStraightRgba
            : ui.ImageByteFormat.rawRgba,
      );
      if (data == null) {
        throw StateError('픽셀 데이터를 읽을 수 없습니다.');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw StateError('픽셀 데이터를 읽을 수 없습니다.');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
  }

  /// RGBA 바이트에서 [width]×[height] 사각형을 잘라 새 바이트를 만든다.
  ///
  /// 행 단위 memcpy라 전체 크롭이 아주 빠르다. [x]/[y]는 소스 왼쪽 위 기준.
  static Uint8List cropRgba(
    Uint8List rgba, {
    required int sourceWidth,
    required int sourceHeight,
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    final out = Uint8List(width * height * 4);
    if (rgba.lengthInBytes < sourceWidth * sourceHeight * 4) {
      throw StateError('RGBA 버퍼 크기가 이미지 크기와 일치하지 않습니다.');
    }
    var src = (y * sourceWidth + x) * 4;
    var dst = 0;
    for (var row = 0; row < height; row++) {
      out.setRange(dst, dst + width * 4, rgba, src);
      src += sourceWidth * 4;
      dst += width * 4;
    }
    return out;
  }

  /// RGBA 바이트를 [ui.Image]로 만든다.
  ///
  /// [targetWidth]/[targetHeight]를 주면 엔진이 그 크기로 리사이즈한다
  /// (확대 포함). 반환된 이미지는 호출자가 `dispose()` 한다.
  static Future<ui.Image> imageFromRgba(
    Uint8List rgba,
    int width,
    int height, {
    int? targetWidth,
    int? targetHeight,
  }) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    return completer.future;
  }

  /// [image]를 PNG 바이트로 인코딩한다 (엔진, C++ 구현).
  static Future<Uint8List> pngFrom(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('PNG 인코딩에 실패했습니다.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// 원본 바이트 → 크기 조절된 썸네일 PNG 바이트를 한 번에 만든다.
  ///
  /// 썸네일 목록에서 원본 전체(수 MB)를 매번 디코딩하는 대신 가로 기준
  /// [targetWidth] 이하로 줄인 PNG를 만들어 캐시용으로 돌려준다.
  static Future<Uint8List> thumbnailPng(
    Uint8List bytes, {
    int targetWidth = 360,
  }) async {
    final image = await decodeImage(bytes, targetWidth: targetWidth);
    try {
      return await pngFrom(image);
    } finally {
      image.dispose();
    }
  }
}