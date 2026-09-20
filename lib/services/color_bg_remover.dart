import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 8비트 RGB 색상 값 (각 채널 0~255).
typedef RgbColor = ({int r, int g, int b});

/// 단색 배경(크로마키) 배경 제거 서비스.
///
/// AI/신경망 없이 순수 Dart로 작동한다.
/// - [detectBackgroundColor]: 이미지 가장자리에서 배경색을 자동 감지
/// - [removeBackground]: 배경색과 가까운 픽셀만 투명 처리
///
/// 단색 배경의 스프라이트 시트에 적합하며, 픽셀 단위 색상 거리 판정이라
/// 캐릭터가 통째로 제거될 가능성이 없다.
abstract final class ColorBgRemover {
  /// 이미지에서 단색 배경색을 자동 감지한다.
  ///
  /// 가장자리(테두리·모서리) 픽셀만 샘플링해 가장 많이 등장하는 색을
  /// 양자화 히스토그램으로 찾아 반환한다. 감지에 실패하면 null을 반환한다.
  static RgbColor? detectBackgroundColor(
    img.Image image, {
    double borderRatio = 0.025,
  }) {
    final w = image.width;
    final h = image.height;
    if (w < 2 || h < 2) return null;
    final m = math.max(1, (math.min(w, h) * borderRatio).round());

    // 채널당 16단계 양자화 히스토그램 (16 × 16 × 16 = 4096 버킷)
    const q = 16;
    final bucket = 256 ~/ q;
    final counts = <int, int>{};

    void sample(int x, int y) {
      final p = image.getPixel(x, y);
      if (p.a == 0) return; // 이미 투명한 픽셀 제외
      final r = p.r.toInt() ~/ bucket;
      final g = p.g.toInt() ~/ bucket;
      final b = p.b.toInt() ~/ bucket;
      final key = (r << 8) | (g << 4) | b;
      counts[key] = (counts[key] ?? 0) + 1;
    }

    // 위/아래 테두리 스트립 (두께 m)
    for (var x = 0; x < w; x++) {
      sample(x, 0);
      sample(x, h - 1);
      for (var y = 1; y < m; y++) {
        sample(x, y);
        sample(x, h - 1 - y);
      }
    }
    // 좌/우 테두리 스트립 (위/아래에서 이미 샘플한 행 제외)
    for (var y = m; y < h - m; y++) {
      sample(0, y);
      sample(w - 1, y);
      for (var x = 1; x < m; x++) {
        sample(x, y);
        sample(w - 1 - x, y);
      }
    }

    if (counts.isEmpty) return null;

    var bestKey = 0;
    var bestCount = -1;
    counts.forEach((key, count) {
      if (count > bestCount) {
        bestCount = count;
        bestKey = key;
      }
    });

    // 양자화 버킷의 중심값으로 복원
    final half = bucket ~/ 2;
    return (
      r: ((bestKey >> 8) & 0xF) * bucket + half,
      g: ((bestKey >> 4) & 0xF) * bucket + half,
      b: (bestKey & 0xF) * bucket + half,
    );
  }

  /// [backgroundColor]와 가까운 픽셀만 투명 처리해 PNG 바이트로 반환한다.
  ///
  /// - [tolerance]: 0~1 색 거리 기준 (기본 0.1). 작을수록 배경색과 거의
  ///   같은 픽셀만 제거되고, 클수록 유사한 색까지 제거된다.
  /// - [feather]: tolerance 초과 ~ (+feather) 구간을 반투명 그라데이션으로
  ///   처리해 경계 계단 현상을 완화한다. 0이면 경계가 뚝 끊긴다.
  static Uint8List removeBackground(
    Uint8List imageBytes, {
    required RgbColor backgroundColor,
    double tolerance = 0.1,
    double feather = 0.05,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw const FormatException('이미지를 해석할 수 없습니다.');
    }

    final br = backgroundColor.r;
    final bg = backgroundColor.g;
    final bb = backgroundColor.b;

    // 거리 기준을 미리 계산해 픽셀 루프에서 sqrt 사용을 최소화한다.
    final maxD = math.sqrt(3.0) * 255.0;
    final inner = tolerance * maxD;
    final outer = (tolerance + feather) * maxD;
    final innerSq = inner * inner;
    final outerSq = outer * outer;
    final span = outer - inner;

    // 입력 형식(예: JPEG 3채널)과 무관하게 항상 RGBA로 출력한다.
    final output = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 4,
    );

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final a = p.a.toInt();
        var newA = a;

        if (a > 0) {
          final dr = r - br;
          final dg = g - bg;
          final db = b - bb;
          final dSq = dr * dr + dg * dg + db * db;
          if (dSq <= innerSq) {
            newA = 0;
          } else if (dSq < outerSq) {
            final d = math.sqrt(dSq.toDouble());
            final factor = (outer - d) / span;
            newA = (a * factor).round().clamp(0, 255);
          }
        }
        output.setPixelRgba(x, y, r, g, b, newA);
      }
    }

    return Uint8List.fromList(img.encodePng(output));
  }
}
