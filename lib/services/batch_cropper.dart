import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:image/image.dart' as img;

import '../models/batch_crop_settings.dart';
import '../models/crop_settings.dart' show CropRect;
import 'image_engine.dart';
import 'sprite_cropper.dart';

/// 일괄 자르기 대상 사진 한 장.
///
/// [bytes] 는 원본 파일 그대로 보관하고, [width]/[height] 는 목록 표시용으로
/// 미리 읽어둔 원본 크기다.
typedef BatchSourceFile = ({
  String name,
  Uint8List bytes,
  int width,
  int height,
});

/// 일괄 자르기 결과 한 건.
///
/// 자르기에 실패한 사진은 [bytes] 가 null 이고 [error] 에 사유가 담긴다.
typedef BatchCropResult = ({
  String name,
  Uint8List? bytes,
  String? error,
});

/// isolate 워커에 넘길 작업 한 건 (전송 가능한 값만 담는다).
typedef _CropTask = ({BatchSourceFile file, BatchCropSettings settings});

/// isolate 워커의 결과 한 건 (전송 가능한 값만 담는다).
typedef _CropOutcome = ({String name, Uint8List? bytes, String? error});

/// 여러 장의 사진에 같은 크기·가운데 정렬 크롭을 일괄 적용하는 서비스.
///
/// 크롭 파이프라인은 `dart:ui` 엔진 기반([ImageEngine])이라 순수 Dart보다
/// 5~10배 빠르며, 실패 시 `package:image` 경로로 자동 폴백한다.
abstract final class BatchCropper {
  /// 확대 크롭 시 허용하는 최대 픽셀 수.
  ///
  /// 20000×20000 같은 요청으로 수억 픽셀짜리 이미지를 만드는 것을 막는다.
  static const int maxUpscaledPixels = 40000000;

  /// 원본 바이트의 픽셀 크기를 읽는다.
  ///
  /// 엔진 쪽 헤더 디코더(`dart:ui`)를 우선 사용해 픽셀을 풀지 않고 크기만
  /// 가져온다. 지원하지 않는 환경(웹의 raw 이외 포맷)에서는 `package:image`
  /// 로 폴백한다. 디코딩 자체가 불가능하면 [FormatException] 을 던진다.
  static Future<({int width, int height})> readImageSize(
    Uint8List bytes,
  ) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width > 0 && height > 0) {
        return (width: width, height: height);
      }
    } catch (_) {
      // 아래 폴백으로 처리한다.
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
    return decodeImageSize(bytes);
  }

  /// [readImageSize] 의 동기 폴백 (픽셀을 전부 디코딩한다).
  static ({int width, int height}) decodeImageSize(Uint8List bytes) {
    final image = SpriteCropper.decode(bytes);
    return (width: image.width, height: image.height);
  }

  /// [total] 안에서 [crop] 크기의 사각형을 [offset](-1..1) 위치에 놓는다.
  ///
  /// `offset = 0`이면 가운데, `±1`이면 이동 가능한 끝까지 이동한다.
  /// [crop]이 [total]보다 크면 항상 0을 돌려준다.
  static int offsetPosition({
    required int total,
    required int crop,
    required double offset,
  }) {
    final slack = (total - crop).clamp(0, total);
    final half = slack / 2;
    return (half + offset * half).round().clamp(0, slack);
  }

  /// 화면(캔버스)에서 그릴 사각형을 구한다.
  ///
  /// 대상 크기가 원본보다 클(확대) 경우 원본 크기로 잘라서 그리고, 위치는
  /// 오프셋을 반영한다. 이미지 픽셀 좌표를 돌려준다.
  static CropRect visibleRect({
    required int imageWidth,
    required int imageHeight,
    required BatchCropSettings settings,
  }) {
    final w = math.min(settings.width, imageWidth);
    final h = math.min(settings.height, imageHeight);
    return (
      x: offsetPosition(total: imageWidth, crop: w, offset: settings.offsetX),
      y: offsetPosition(total: imageHeight, crop: h, offset: settings.offsetY),
      width: w,
      height: h,
    );
  }

  /// [settings]로 자르면 실제로 잘릴 영역과 최종 목표 크기를 계획한다.
  ///
  /// - 원본이 목표 크기 이상: 정확히 목표 크기의 사각형만 오프셋 위치에서 크롭
  ///   (스케일 없음).
  /// - 원본이 목표보다 작음: 커버 배율로 필요한 원본 영역만 고른 뒤, 그 영역을
  ///   목표 크기로 스케일한다. 전체 이미지를 확대하지 않아 더 빠르다.
  static ({CropRect rect, int targetWidth, int targetHeight}) planCrop({
    required int imageWidth,
    required int imageHeight,
    required BatchCropSettings settings,
  }) {
    final tw = settings.width;
    final th = settings.height;

    if (imageWidth >= tw && imageHeight >= th) {
      return (
        rect: (
          x: offsetPosition(total: imageWidth, crop: tw, offset: settings.offsetX),
          y: offsetPosition(total: imageHeight, crop: th, offset: settings.offsetY),
          width: tw,
          height: th,
        ),
        targetWidth: tw,
        targetHeight: th,
      );
    }

    // 커버: 작은 원본에서 목표를 채우는 데 필요한 최소 영역.
    final scale = math.max(tw / imageWidth, th / imageHeight);
    final regionW = (tw / scale).round();
    final regionH = (th / scale).round();
    return (
      rect: (
        x: offsetPosition(total: imageWidth, crop: regionW, offset: settings.offsetX),
        y: offsetPosition(total: imageHeight, crop: regionH, offset: settings.offsetY),
        width: regionW,
        height: regionH,
      ),
      targetWidth: tw,
      targetHeight: th,
    );
  }

  /// [image] 를 [settings] 크기·위치로 자른다 (`package:image` 경로의 폴백용).
  static img.Image cropOne(img.Image image, BatchCropSettings settings) {
    if (settings.width * settings.height > maxUpscaledPixels) {
      throw const FormatException(
        '지정한 크기가 원본보다 너무 큽니다. 더 작은 크기를 지정해 주세요.',
      );
    }
    final plan = planCrop(
      imageWidth: image.width,
      imageHeight: image.height,
      settings: settings,
    );
    var out = img.copyCrop(
      image,
      x: plan.rect.x,
      y: plan.rect.y,
      width: plan.rect.width,
      height: plan.rect.height,
    );
    if (out.width != plan.targetWidth || out.height != plan.targetHeight) {
      final upscaling =
          plan.targetWidth * plan.targetHeight > plan.rect.width * plan.rect.height;
      out = img.copyResize(
        out,
        width: plan.targetWidth,
        height: plan.targetHeight,
        interpolation: upscaling
            ? img.Interpolation.cubic
            : img.Interpolation.average,
      );
    }
    return out;
  }

  /// [sourceBytes] 한 장을 [settings] 크기·위치로 잘라 PNG 바이트로 돌려준다.
  ///
  /// 엔진([ImageEngine]) 경로를 우선 시도하고, 실패하면 `package:image` 순수
  /// Dart 경로로 폴백한다.
  static Future<Uint8List> cropToPng(
    Uint8List sourceBytes,
    BatchCropSettings settings,
  ) async {
    if (settings.width * settings.height > maxUpscaledPixels) {
      throw const FormatException(
        '지정한 크기가 원본보다 너무 큽니다. 더 작은 크기를 지정해 주세요.',
      );
    }
    try {
      return await cropToPngViaEngine(sourceBytes, settings);
    } catch (_) {
      // dart:ui 경로 실패 시 순수 Dart 폴백 (포맷 호환성·이식성).
      final cropped = cropOne(SpriteCropper.decode(sourceBytes), settings);
      return Uint8List.fromList(img.encodePng(cropped));
    }
  }

  /// 엔진 기반 크롭 파이프라인.
  ///
  /// 디코딩 → RGBA 추출 → 행 단위 memcpy 크롭 → (필요 시) 엔진 리사이즈 →
  /// 엔진 PNG 인코딩. 생성되는 모든 [ui.Image]는 finally 에서 dispose 한다.
  static Future<Uint8List> cropToPngViaEngine(
    Uint8List sourceBytes,
    BatchCropSettings settings,
  ) async {
    final image = await ImageEngine.decodeImage(sourceBytes);
    try {
      final plan = planCrop(
        imageWidth: image.width,
        imageHeight: image.height,
        settings: settings,
      );
      final rect = plan.rect;
      final rgba = await ImageEngine.rgbaFrom(image);
      final cropped = ImageEngine.cropRgba(
        rgba,
        sourceWidth: image.width,
        sourceHeight: image.height,
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
      );
      if (rect.width == plan.targetWidth && rect.height == plan.targetHeight) {
        final out = await ImageEngine.imageFromRgba(cropped, rect.width, rect.height);
        try {
          return await ImageEngine.pngFrom(out);
        } finally {
          out.dispose();
        }
      }
      final resized = await ImageEngine.imageFromRgba(
        cropped,
        rect.width,
        rect.height,
        targetWidth: plan.targetWidth,
        targetHeight: plan.targetHeight,
      );
      try {
        return await ImageEngine.pngFrom(resized);
      } finally {
        resized.dispose();
      }
    } finally {
      image.dispose();
    }
  }

  /// [files] 를 모두 [settings] 크기·위치로 자른다.
  ///
  /// 데스크톱에서는 워커 isolate 로 병렬 처리해 훨씬 빠르고, 웹(Isolate 가
  /// 없는 환경)이나 파일이 1장일 때는 순차 처리한다. 개별 실패는 전체
  /// 작업을 중단하지 않고 [BatchCropResult.error] 로 남긴다.
  static Future<List<BatchCropResult>> cropAll(
    List<BatchSourceFile> files,
    BatchCropSettings settings, {
    void Function(int done, int total, String name)? onProgress,
  }) async {
    if (kIsWeb || files.length < 2) {
      return cropAllSequential(files, settings, onProgress: onProgress);
    }
    return cropAllParallel(files, settings, onProgress: onProgress);
  }

  /// 순차 처리 (progress 오버레이 갱신을 위해 파일 사이를 잠깐 쉰다).
  static Future<List<BatchCropResult>> cropAllSequential(
    List<BatchSourceFile> files,
    BatchCropSettings settings, {
    void Function(int done, int total, String name)? onProgress,
  }) async {
    final results = <BatchCropResult>[];
    final taken = <String>{};

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      onProgress?.call(i, files.length, file.name);
      try {
        final name = uniqueResultName(file.name, taken);
        final bytes = await cropToPng(file.bytes, settings);
        results.add((name: name, bytes: bytes, error: null));
      } catch (e) {
        results.add((name: file.name, bytes: null, error: '$e'));
      }
      // 다음 사진 전에 이벤트 루프를 한 번 돌려 진행 표시가 갱신되게 한다.
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    onProgress?.call(files.length, files.length, '');
    return results;
  }

  /// 데스크톱 병렬 처리.
  ///
  /// [concurrency] 개의 워커로 나눠 한 장씩 isolate 에서 자른다. 결과의
  /// 파일명(중복 시 `_2`)은 원본 순서대로 정해진다.
  static Future<List<BatchCropResult>> cropAllParallel(
    List<BatchSourceFile> files,
    BatchCropSettings settings, {
    void Function(int done, int total, String name)? onProgress,
    int concurrency = 4,
  }) async {
    final raw = List<BatchCropResult?>.filled(files.length, null);
    var next = 0;
    var done = 0;

    onProgress?.call(0, files.length, '');

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= files.length) break;
        final file = files[i];
        final outcome = await compute(
          _cropOneIsolate,
          (file: file, settings: settings),
        );
        raw[i] = outcome;
        done++;
        onProgress?.call(done, files.length, file.name);
      }
    }

    await Future.wait([
      for (var w = 0; w < concurrency && w < files.length; w++) worker(),
    ]);

    // 파일명(중복 _2)은 원본 순서대로, 실패는 그대로 남긴다.
    final results = <BatchCropResult>[];
    final taken = <String>{};
    for (var i = 0; i < files.length; i++) {
      final r = raw[i]!;
      if (r.bytes == null) {
        results.add(r);
      } else {
        results.add((
          name: uniqueResultName(files[i].name, taken),
          bytes: r.bytes,
          error: null,
        ));
      }
    }

    onProgress?.call(files.length, files.length, '');
    return results;
  }

  /// 결과 파일명: 원본 파일명에서 확장자만 png 로 교체한다.
  static String resultFileName(String sourceName) {
    final stem = sourceName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final base = SpriteCropper.sanitizeName(stem);
    return '${base.isEmpty ? 'image' : base}.png';
  }

  /// [resultFileName] 이 이미 쓰였으면 뒤에 `_2`, `_3` … 을 붙여 유일하게 만든다.
  static String uniqueResultName(String sourceName, Set<String> taken) {
    final base = resultFileName(sourceName);
    if (taken.add(base)) return base;

    final stem = base.substring(0, base.length - '.png'.length);
    var suffix = 2;
    while (!taken.add('${stem}_$suffix.png')) {
      suffix++;
    }
    return '${stem}_$suffix.png';
  }

  /// ZIP 파일명(확장자 제외).
  static String zipBaseName(BatchCropSettings settings, int count) =>
      'crop_${settings.fileToken}_$count';
}

/// isolate 워커 진입점: 한 장을 자르고 전송 가능한 결과를 돌려준다.
///
/// `compute` 에 넘길 수 있도록 최상위 함수로 두며, 캡처하는 값이 없다.
Future<_CropOutcome> _cropOneIsolate(_CropTask task) async {
  final file = task.file;
  try {
    final bytes = await BatchCropper.cropToPng(file.bytes, task.settings);
    return (name: file.name, bytes: bytes, error: null);
  } catch (e) {
    return (name: file.name, bytes: null, error: '$e');
  }
}