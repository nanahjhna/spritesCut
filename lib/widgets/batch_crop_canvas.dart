import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/batch_crop_settings.dart';
import '../services/batch_cropper.dart';

/// 고정 크기 크롭 영역을 시각화하는 캔버스.
///
/// 이미지를 화면에 100% 피팅해 표시하고, 크롭 사각형 바깥을 어둡게 덮는다.
/// 사각형 **안을 드래그**하면 위치가 바뀌고(오프셋), **모서리·변을 드래그**하면
/// 크기만 바뀐다(가운데 고정 안 됨). 상호작용 시작/종료는 [onInteractionStart]/
/// [onInteractionEnd] 로 알린다.
class BatchCropCanvas extends StatefulWidget {
  const BatchCropCanvas({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.settings,
    required this.onCropSizeChanged,
    this.onInteractionStart,
    this.onInteractionEnd,
    this.interactive = true,
    this.accent = Colors.deepOrange,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;

  /// 현재 크롭 크기·위치.
  final BatchCropSettings settings;

  /// 사각형 크기/위치가 바뀌었을 때 호출된다.
  final ValueChanged<BatchCropSettings> onCropSizeChanged;

  /// 핸들/이동 드래그가 시작됐을 때 호출된다. (결과 미리보기 중지 등)
  final VoidCallback? onInteractionStart;

  /// 핸들/이동 드래그가 끝났을 때 호출된다. (결과 미리보기 재계산 등)
  final VoidCallback? onInteractionEnd;

  /// false면 핸들·이동 조작을 막는다.
  final bool interactive;

  /// 테두리·라벨 색.
  final Color accent;

  @override
  State<BatchCropCanvas> createState() => _BatchCropCanvasState();
}

class _BatchCropCanvasState extends State<BatchCropCanvas> {
  /// 마지막 빌드에서 계산한 표시 배율 (화면 px → 이미지 px 변환에 사용).
  double _fitScale = 1;

  /// 크기(리사이즈) 드래그 시작 시 손의 위치와 크기 기준값.
  Offset? _dragOrigin;
  ({int width, int height})? _dragBase;

  /// 위치(이동) 드래그 시작 시 손의 위치와 오프셋 기준값.
  Offset? _moveOrigin;
  ({double x, double y})? _moveBaseOffset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight;
        if (availW <= 0 ||
            availH <= 0 ||
            widget.imageWidth <= 0 ||
            widget.imageHeight <= 0) {
          return const SizedBox.shrink();
        }

        // 화면에 꽉 차게 피팅 (100% 표시)
        final fitScale = math.min(
          availW / widget.imageWidth,
          availH / widget.imageHeight,
        );
        _fitScale = fitScale;

        final dispW = widget.imageWidth * fitScale;
        final dispH = widget.imageHeight * fitScale;
        final imageRect = Rect.fromLTWH(
          (availW - dispW) / 2,
          (availH - dispH) / 2,
          dispW,
          dispH,
        );

        // 엔진이 실제로 자르는 위치와 동일하게 표시 (오프셋 반영, 원본 안으로 클램프)
        final cropPx = BatchCropper.visibleRect(
          imageWidth: widget.imageWidth,
          imageHeight: widget.imageHeight,
          settings: widget.settings,
        );
        final cropRect = Rect.fromLTWH(
          imageRect.left + cropPx.x * fitScale,
          imageRect.top + cropPx.y * fitScale,
          cropPx.width * fitScale,
          cropPx.height * fitScale,
        );

        final upscaling = widget.settings.width > widget.imageWidth ||
            widget.settings.height > widget.imageHeight;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: imageRect.left,
              top: imageRect.top,
              width: dispW,
              height: dispH,
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _BatchCropPainter(
                    imageRect: imageRect,
                    cropRect: cropRect,
                    accent: widget.accent,
                    sizeLabel: widget.settings.label,
                    positionLabel: widget.settings.positionLabel,
                    upscaling: upscaling,
                  ),
                ),
              ),
            ),
            if (widget.interactive) ...[
              // 사각형 내부 드래그 = 위치 이동
              Positioned(
                left: cropRect.left,
                top: cropRect.top,
                width: cropRect.width,
                height: cropRect.height,
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _onMovePanStart,
                    onPanUpdate: _onMovePanUpdate,
                    onPanEnd: (_) => _onMovePanEnd(),
                    onPanCancel: _onMovePanEnd,
                  ),
                ),
              ),
              ..._buildHandles(cropRect),
            ],
          ],
        );
      },
    );
  }

  /// 모서리 4개 + 변 4개 핸들을 배치한다.
  List<Widget> _buildHandles(Rect rect) {
    return [
      _handle(rect.topLeft, SystemMouseCursors.resizeUpLeftDownRight,
          affectsWidth: true, affectsHeight: true),
      _handle(rect.topRight, SystemMouseCursors.resizeUpRightDownLeft,
          affectsWidth: true, affectsHeight: true),
      _handle(rect.bottomLeft, SystemMouseCursors.resizeUpRightDownLeft,
          affectsWidth: true, affectsHeight: true),
      _handle(rect.bottomRight, SystemMouseCursors.resizeUpLeftDownRight,
          affectsWidth: true, affectsHeight: true),
      _handle(Offset(rect.center.dx, rect.top),
          SystemMouseCursors.resizeUpDown,
          affectsWidth: true, affectsHeight: false),
      _handle(Offset(rect.center.dx, rect.bottom),
          SystemMouseCursors.resizeUpDown,
          affectsWidth: true, affectsHeight: false),
      _handle(Offset(rect.left, rect.center.dy),
          SystemMouseCursors.resizeLeftRight,
          affectsWidth: false, affectsHeight: true),
      _handle(Offset(rect.right, rect.center.dy),
          SystemMouseCursors.resizeLeftRight,
          affectsWidth: false, affectsHeight: true),
    ];
  }

  Widget _handle(
    Offset anchor,
    MouseCursor cursor, {
    required bool affectsWidth,
    required bool affectsHeight,
  }) {
    const hit = 26.0;
    return Positioned(
      left: anchor.dx - hit / 2,
      top: anchor.dy - hit / 2,
      width: hit,
      height: hit,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onHandlePanStart,
          onPanUpdate: (details) => _onHandlePanUpdate(
            details,
            affectsWidth: affectsWidth,
            affectsHeight: affectsHeight,
          ),
          onPanEnd: (_) => _onHandlePanEnd(),
          onPanCancel: _onHandlePanEnd,
        ),
      ),
    );
  }

  void _onHandlePanStart(DragStartDetails details) {
    _dragOrigin = details.globalPosition;
    _dragBase = (width: widget.settings.width, height: widget.settings.height);
    widget.onInteractionStart?.call();
  }

  void _onHandlePanUpdate(
    DragUpdateDetails details, {
    required bool affectsWidth,
    required bool affectsHeight,
  }) {
    final origin = _dragOrigin;
    final base = _dragBase;
    final scale = _fitScale;
    if (origin == null || base == null || scale <= 0) return;

    final delta = details.globalPosition - origin;
    // 사각형은 가운데 고정이라 한쪽으로 d 만큼 끌면 크기가 2d 만큼 변한다.
    final width = affectsWidth
        ? ((base.width + delta.dx * 2) / scale).round()
        : base.width;
    final height = affectsHeight
        ? ((base.height + delta.dy * 2) / scale).round()
        : base.height;

    final next = widget.settings.withSize(width, height);
    if (next != widget.settings) {
      widget.onCropSizeChanged(next);
    }
  }

  void _onHandlePanEnd() {
    _dragOrigin = null;
    _dragBase = null;
    widget.onInteractionEnd?.call();
  }

  void _onMovePanStart(DragStartDetails details) {
    _moveOrigin = details.globalPosition;
    _moveBaseOffset = (
      x: widget.settings.offsetX,
      y: widget.settings.offsetY,
    );
    widget.onInteractionStart?.call();
  }

  void _onMovePanUpdate(DragUpdateDetails details) {
    final origin = _moveOrigin;
    final base = _moveBaseOffset;
    final scale = _fitScale;
    if (origin == null || base == null || scale <= 0) return;

    final delta = details.globalPosition - origin;
    final drawW = math.min(widget.settings.width, widget.imageWidth).toDouble();
    final drawH = math.min(widget.settings.height, widget.imageHeight).toDouble();

    var offsetX = base.x;
    var offsetY = base.y;
    final slackX = widget.imageWidth - drawW;
    final slackY = widget.imageHeight - drawH;
    if (slackX > 1) {
      offsetX = (base.x + delta.dx / scale / (slackX / 2)).clamp(-1.0, 1.0);
    }
    if (slackY > 1) {
      offsetY = (base.y + delta.dy / scale / (slackY / 2)).clamp(-1.0, 1.0);
    }

    final next = widget.settings.copyWith(offsetX: offsetX, offsetY: offsetY);
    if (next != widget.settings) {
      widget.onCropSizeChanged(next);
    }
  }

  void _onMovePanEnd() {
    _moveOrigin = null;
    _moveBaseOffset = null;
    widget.onInteractionEnd?.call();
  }
}

/// 이미지 + 어두운 마스크 + 크롭 테두리/가이드/라벨을 그리는 페인터.
class _BatchCropPainter extends CustomPainter {
  _BatchCropPainter({
    required this.imageRect,
    required this.cropRect,
    required this.accent,
    required this.sizeLabel,
    required this.positionLabel,
    required this.upscaling,
  });

  final Rect imageRect;
  final Rect cropRect;
  final Color accent;

  /// 사각형 위에 표시할 '1920 × 1080' 문자열.
  final String sizeLabel;

  /// 사각형 아래에 표시할 위치 문자열 ('가로 0% · 세로 0%').
  final String positionLabel;

  /// 지정 크기가 원본보다 큰지 여부.
  final bool upscaling;

  @override
  void paint(Canvas canvas, Size size) {
    // 크롭 영역 바깥을 어둡게 덮는다 (even-odd).
    canvas.drawPath(
      Path()
        ..addRect(Offset.zero & size)
        ..addRect(cropRect)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // 원본 이미지 테두리
    canvas.drawRect(
      imageRect,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 크롭 영역 테두리
    canvas.drawRect(
      cropRect,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawRect(
      cropRect.deflate(1.5),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 3분할 가이드선
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = cropRect.left + cropRect.width * i / 3;
      final y = cropRect.top + cropRect.height * i / 3;
      canvas.drawLine(Offset(x, cropRect.top), Offset(x, cropRect.bottom), guide);
      canvas.drawLine(Offset(cropRect.left, y), Offset(cropRect.right, y), guide);
    }

    // 모서리 L자 표시
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;
    const len = 16.0;
    final l = cropRect.left;
    final t = cropRect.top;
    final r = cropRect.right;
    final b = cropRect.bottom;
    // 좌상
    canvas.drawLine(Offset(l, t + len), Offset(l, t), corner);
    canvas.drawLine(Offset(l, t), Offset(l + len, t), corner);
    // 우상
    canvas.drawLine(Offset(r - len, t), Offset(r, t), corner);
    canvas.drawLine(Offset(r, t), Offset(r, t + len), corner);
    // 좌하
    canvas.drawLine(Offset(l, b - len), Offset(l, b), corner);
    canvas.drawLine(Offset(l, b), Offset(l + len, b), corner);
    // 우하
    canvas.drawLine(Offset(r - len, b), Offset(r, b), corner);
    canvas.drawLine(Offset(r, b), Offset(r, b - len), corner);

    // 상단: 크기 라벨, 하단: 위치 라벨
    _paintChip(canvas, '$sizeLabel px', Offset(l, t + 6));
    _paintChip(canvas, positionLabel, Offset(l, b - 26));

    if (upscaling) {
      _paintChip(
        canvas,
        '원본보다 큰 크기 · 확대 후 자르기',
        Offset(l, b + 4),
      );
    }
  }

  /// 작게 말풍선 모양 라벨을 그린다.
  void _paintChip(Canvas canvas, String text, Offset anchor) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = Rect.fromLTWH(
      anchor.dx,
      anchor.dy,
      painter.width + 12,
      painter.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    painter.paint(canvas, rect.topLeft + const Offset(6, 3));
  }

  @override
  bool shouldRepaint(covariant _BatchCropPainter oldDelegate) =>
      oldDelegate.imageRect != imageRect ||
      oldDelegate.cropRect != cropRect ||
      oldDelegate.accent != accent ||
      oldDelegate.sizeLabel != sizeLabel ||
      oldDelegate.positionLabel != positionLabel ||
      oldDelegate.upscaling != upscaling;
}