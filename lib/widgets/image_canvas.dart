import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/crop_settings.dart';

/// 이미지 프리뷰 캔버스.
///
/// 업로드된 이미지를 화면에 100% 피팅해서 표시하고,
/// 상/하단 여백을 드래그로 조절할 수 있는 가이드 박스 및 격자선을 표시합니다.
class ImageCanvas extends StatefulWidget {
  const ImageCanvas({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.settings,
    required this.onSettingsChanged,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final CropSettings settings;
  final ValueChanged<CropSettings> onSettingsChanged;

  @override
  State<ImageCanvas> createState() => _ImageCanvasState();
}

class _ImageCanvasState extends State<ImageCanvas> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight;

        if (availW == 0 || availH == 0) {
          return const SizedBox.shrink();
        }

        // 화면에 꽉 차게 피팅 (100% 표시)
        final fitScale = math.min(
          availW / widget.imageWidth,
          availH / widget.imageHeight,
        );
        final dispW = widget.imageWidth * fitScale;
        final dispH = widget.imageHeight * fitScale;

        // 이미지 중앙 정렬 (화면 내 이미지 시작 위치)
        final imgX = (availW - dispW) / 2;
        final imgY = (availH - dispH) / 2;

        // 화면 스케일이 적용된 여백 높이 (px)
        final topPx = widget.settings.topPadding * fitScale;
        final bottomPx = widget.settings.bottomPadding * fitScale;

        // 가이드 박스 영역 (실제 자르기 영역)
        final boxRect = Rect.fromLTWH(
          imgX,
          imgY + topPx,
          dispW,
          dispH - topPx - bottomPx,
        );

        // 원본 전체 이미지 영역
        final imageRect = Rect.fromLTWH(imgX, imgY, dispW, dispH);

        const handleHeight = 12.0; // 드래그 터치 영역 높이

        return Stack(
          children: [
            // 1) 이미지 표시
            Positioned(
              left: imgX,
              top: imgY,
              width: dispW,
              height: dispH,
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),

            // 2) 오버레이: 영역 밖 디밍 + 격자선 + 번호
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _OverlayPainter(
                    imageRect: imageRect,
                    boxRect: boxRect,
                    settings: widget.settings,
                    imageWidth: widget.imageWidth,
                    imageHeight: widget.imageHeight,
                    scale: fitScale,
                    dimColor: Colors.black.withValues(alpha: 0.6),
                    borderColor: colorScheme.primary,
                  ),
                ),
              ),
            ),

            // 3) 상단 조절 핸들
            Positioned(
              left: imgX,
              top: boxRect.top - (handleHeight / 2),
              width: dispW,
              height: handleHeight,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    final deltaImg = details.delta.dy / fitScale;
                    final maxTop = widget.imageHeight - widget.settings.bottomPadding - 10.0;
                    final newTop = (widget.settings.topPadding + deltaImg)
                        .clamp(0.0, maxTop);

                    widget.onSettingsChanged(
                      widget.settings.copyWith(topPadding: newTop),
                    );
                  },
                  child: Center(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 2),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 4) 하단 조절 핸들
            Positioned(
              left: imgX,
              top: boxRect.bottom - (handleHeight / 2),
              width: dispW,
              height: handleHeight,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    final deltaImg = details.delta.dy / fitScale;
                    final maxBottom = widget.imageHeight - widget.settings.topPadding - 10.0;
                    final newBottom = (widget.settings.bottomPadding - deltaImg)
                        .clamp(0.0, maxBottom);

                    widget.onSettingsChanged(
                      widget.settings.copyWith(bottomPadding: newBottom),
                    );
                  },
                  child: Center(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 2),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 5) 안내 문구
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '상/하단 경계선을 드래그하여 높이를 조절하세요  •  가로 ${widget.settings.horizontalCount} × 세로 ${widget.settings.verticalCount} 분할',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 박스 외부 디밍, 격자선, 컷 번호, 테두리를 그리는 페인터.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.imageRect,
    required this.boxRect,
    required this.settings,
    required this.imageWidth,
    required this.imageHeight,
    required this.scale,
    required this.dimColor,
    required this.borderColor,
  });

  final Rect imageRect;
  final Rect boxRect;
  final CropSettings settings;
  final int imageWidth;
  final int imageHeight;
  final double scale;
  final Color dimColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 1) 전체 화면 기준 어둡게 처리 후, 가이드 박스 영역만 투명화
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = dimColor);
    // 가이드 박스 부분 뚫기
    canvas.drawRect(boxRect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // 2) 가이드 박스 테두리
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = borderColor;
    canvas.drawRect(boxRect, borderPaint);

    // 3) 격자선 (1컷 크기 기준)
    final sprite = settings.calcSpriteSize(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    final cellW = sprite.spriteWidth * scale;
    final cellH = sprite.spriteHeight * scale;

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.85);

    // 세로 격자선 (가로 분할)
    for (var i = 1; i < settings.horizontalCount; i++) {
      final gx = boxRect.left + i * cellW;
      canvas.drawLine(Offset(gx, boxRect.top), Offset(gx, boxRect.bottom), gridPaint);
    }
    // 가로 격자선 (세로 분할)
    for (var i = 1; i < settings.verticalCount; i++) {
      final gy = boxRect.top + i * cellH;
      canvas.drawLine(Offset(boxRect.left, gy), Offset(boxRect.right, gy), gridPaint);
    }

    // 4) 각 컷 번호
    for (var row = 0; row < settings.verticalCount; row++) {
      for (var col = 0; col < settings.horizontalCount; col++) {
        final index = row * settings.horizontalCount + col;
        final cell = Rect.fromLTWH(
          boxRect.left + col * cellW,
          boxRect.top + row * cellH,
          cellW,
          cellH,
        );
        _paintNumberChip(canvas, cell, index + 1);
      }
    }
  }

  void _paintNumberChip(Canvas canvas, Rect cell, int number) {
    if (cell.width < 14 || cell.height < 14) return;

    final painter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black87, blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padding = 4.0;
    final chipSize = Size(
      painter.width + padding * 2,
      painter.height + padding * 2,
    );
    final chipRect = Rect.fromLTWH(
      cell.left + 3,
      cell.top + 3,
      chipSize.width,
      chipSize.height,
    );

    final chipPaint = Paint()..color = Colors.black54;
    canvas.drawRRect(
      RRect.fromRectAndRadius(chipRect, const Radius.circular(4)),
      chipPaint,
    );
    painter.paint(canvas, chipRect.topLeft + const Offset(padding, padding));
  }

  @override
  bool shouldRepaint(_OverlayPainter oldDelegate) {
    return oldDelegate.boxRect != boxRect ||
        oldDelegate.settings != settings ||
        oldDelegate.scale != scale;
  }
}