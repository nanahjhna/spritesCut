import 'dart:convert';
import 'dart:math' as math;
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
    int tolerance = 50, // 기본 오차 범위를 50 이상으로 설정 추천
  }) {
    final image = decode(bytes);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        final rDiff = (r - targetRed).abs();
        final gDiff = (g - targetGreen).abs();
        final bDiff = (b - targetBlue).abs();

        // 오차 범위 내 색상을 투명으로 변경
        if (rDiff <= tolerance && gDiff <= tolerance && bDiff <= tolerance) {
          pixel.setRgba(r, g, b, 0); // Alpha = 0
        }
      }
    }

    // 반드시 PNG로 인코딩되어야 알파 채널(투명도)이 유지됩니다.
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
  ///
  /// [previewHtml]이 주어지면 `index.html` 이름으로 ZIP 루트에 함께 넣는다.
  /// [extraFiles]는 stage.jpg 같은 추가 파일을 ZIP 루트에 함께 넣는다.
  static Uint8List buildZip(
    List<({String name, Uint8List bytes})> files, {
    String? previewHtml,
    List<({String name, Uint8List bytes})>? extraFiles,
  }) {
    final archive = Archive();
    for (final file in files) {
      archive.addFile(ArchiveFile.bytes(file.name, file.bytes));
    }
    if (previewHtml != null) {
      archive.addFile(ArchiveFile.bytes('index.html', utf8.encode(previewHtml)));
    }
    if (extraFiles != null) {
      for (final extra in extraFiles) {
        archive.addFile(ArchiveFile.bytes(extra.name, extra.bytes));
      }
    }
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  /// 프레임들을 브라우저에서 순환 재생할 수 있는 미리보기 HTML을 생성한다.
  ///
  /// - [totalCount]: 잘라낸 스프라이트 전체 개수 (sprite_1.png ~ sprite_N.png)
  /// - 같은 폴더에 `stage.jpg`가 있으면 배경으로 사용하고,
  ///   없으면 투명 배경 확인용 체커보드가 표시된다.
  static String buildPreviewHtml({
    required int totalCount,
    required int spriteWidth,
    required int spriteHeight,
  }) {
    // 미리보기 박스 크기 (최대 400px, 스프라이트 비율 유지)
    const double maxBox = 400.0;
    double w = spriteWidth > 0 ? spriteWidth.toDouble() : 1.0;
    double h = spriteHeight > 0 ? spriteHeight.toDouble() : 1.0;
    final scale = math.min(maxBox / w, maxBox / h).clamp(0.0, 1.0);
    final boxW = (w * scale).round();
    final boxH = (h * scale).round();

    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sprite Animation Preview</title>
    <style>
        body {
            background-color: #1e1e1e;
            color: #ffffff;
            font-family: Arial, sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            padding: 16px;
        }

        .container {
            background-color: #2d2d2d;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5);
            text-align: center;
            max-width: 100%;
        }

        /* 체커보드 기본 배경 (누끼 투명도 확인용) */
        .preview-box {
            width: ${boxW}px;
            height: ${boxH}px;
            margin: 20px auto;
            border: 2px solid #444;
            border-radius: 8px;
            display: flex;
            align-items: center;
            justify-content: center;
            overflow: hidden;
            background-color: #c0c0c0;
            background-image:
                linear-gradient(45deg, #f2f2f2 25%, transparent 25%),
                linear-gradient(-45deg, #f2f2f2 25%, transparent 25%),
                linear-gradient(45deg, transparent 75%, #f2f2f2 75%),
                linear-gradient(-45deg, transparent 75%, #f2f2f2 75%);
            background-size: 20px 20px;
            background-position: 0 0, 0 10px, 10px -10px, -10px 0;
        }

        #sprite-view {
            max-width: 100%;
            max-height: 100%;
            /* 픽셀 아트일 경우 선명하게 보이기 위한 설정 */
            image-rendering: pixelated;
        }

        .info {
            color: #9d9d9d;
            font-size: 13px;
            margin: 0;
        }

        .controls {
            display: flex;
            flex-direction: column;
            gap: 15px;
            margin-top: 20px;
        }

        .button-group {
            display: flex;
            justify-content: center;
            gap: 10px;
        }

        button {
            background-color: #007acc;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 6px;
            cursor: pointer;
            font-weight: bold;
            transition: background 0.2s;
        }

        button:hover {
            background-color: #005999;
        }

        .speed-control {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 10px;
        }

        input[type="range"] {
            width: 150px;
        }
    </style>
</head>
<body>

<div class="container">
    <h2>스프라이트 애니메이션 미리보기</h2>
    <p class="info">총 $totalCount컷 ($spriteWidth × ${spriteHeight}px)</p>

    <div class="preview-box" id="preview-box">
        <img id="sprite-view" src="sprite_1.png" alt="Sprite Frame">
    </div>

    <div class="controls">
        <div class="button-group">
            <button id="play-btn" onclick="togglePlay()">일시정지</button>
        </div>

        <div class="speed-control">
            <label for="fps-slider">재생 속도 (FPS): <span id="fps-val">10</span></label>
            <input type="range" id="fps-slider" min="1" max="30" value="10" oninput="updateFPS(this.value)">
        </div>
    </div>
</div>

<script>
    // sprite_1.png ~ sprite_$totalCount.png 경로 배열
    const totalFrames = $totalCount;
    const frames = [];
    for (let i = 1; i <= totalFrames; i++) {
        frames.push('sprite_' + i + '.png');
    }

    let currentFrame = 0;
    let fps = 10;
    let isPlaying = true;
    let timer = null;

    const spriteImg = document.getElementById('sprite-view');
    const playBtn = document.getElementById('play-btn');
    const fpsVal = document.getElementById('fps-val');
    const previewBox = document.getElementById('preview-box');

    // 이미지 프리로드 (매끄러운 재생을 위해 미리 로드)
    frames.forEach(function (src) {
        const img = new Image();
        img.src = src;
    });

    // 같은 폴더의 stage.jpg를 배경으로 사용 (없으면 체커보드 유지)
    const bgTest = new Image();
    bgTest.onload = function () {
        previewBox.style.backgroundImage = "url('stage.jpg')";
        previewBox.style.backgroundSize = 'cover';
        previewBox.style.backgroundPosition = 'center';
        previewBox.style.backgroundColor = '#2d2d2d';
    };
    bgTest.onerror = function () {
        // stage.jpg가 없으면 기본 체커보드 배경 유지
    };
    bgTest.src = 'stage.jpg';

    function nextFrame() {
        currentFrame = (currentFrame + 1) % totalFrames;
        spriteImg.src = frames[currentFrame];
    }

    function startAnimation() {
        if (timer) clearInterval(timer);
        timer = setInterval(nextFrame, 1000 / fps);
    }

    function togglePlay() {
        isPlaying = !isPlaying;
        if (isPlaying) {
            playBtn.innerText = '일시정지';
            startAnimation();
        } else {
            playBtn.innerText = '재생';
            clearInterval(timer);
        }
    }

    function updateFPS(val) {
        fps = Number(val);
        fpsVal.innerText = val;
        if (isPlaying) {
            startAnimation();
        }
    }

    // 애니메이션 시작
    startAnimation();
</script>

</body>
</html>
''';
  }
}