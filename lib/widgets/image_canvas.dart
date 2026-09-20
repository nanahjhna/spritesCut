import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/crop_settings.dart';

/// 이미지 프리뷰 캔버스.
///
/// 업로드된 이미지를 화면에 100% 피팅해서 표시하고,
/// 투명 배경(체커보드) 및 상/하/좌/우 여백 조절 가이드 라인을 제공합니다.
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

        // 화면 스케일이 적용된 여백 길이 (px)
        final topPx = widget.settings.topPadding * fitScale;
        final bottomPx = widget.settings.bottomPadding * fitScale;
        final leftPx = widget.settings.leftPadding * fitScale;
        final rightPx = widget.settings.rightPadding * fitScale;

        // 수동 조절 모드 여부 (경계선 기반으로 자르기)
        final useManual = widget.settings.useManualBoundaries;

        // 가이드 박스 영역 (실제 자르기 영역).
        // 수동 모드에서는 여백을 무시하고 이미지 전체를 기준으로 삼는다.
        final boxRect = useManual
            ? Rect.fromLTWH(imgX, imgY, dispW, dispH)
            : Rect.fromLTWH(
          imgX + leftPx,
          imgY + topPx,
          dispW - leftPx - rightPx,
          dispH - topPx - bottomPx,
        );

        // 원본 전체 이미지 영역
        final imageRect = Rect.fromLTWH(imgX, imgY, dispW, dispH);

        const handleLength = 12.0; // 드래그 터치 영역 두께 (높이/폭)

        return Stack(
          children: [
            // 0) 전체 캔버스 영역 투명 체커보드 배경 (추가됨)
            const Positioned.fill(
              child: CustomPaint(
                painter: CheckerboardPainter(squareSize: 12),
              ),
            ),

            // 1) 이미지 영역 직하단 체커보드 + 이미지 표시
            Positioned(
              left: imgX,
              top: imgY,
              width: dispW,
              height: dispH,
              child: ClipRect(
                child: Stack(
                  children: [
                    // 이미지 바로 뒤 체커보드
                    const Positioned.fill(
                      child: CustomPaint(
                        painter: CheckerboardPainter(squareSize: 10),
                      ),
                    ),
                    // 실제 이미지
                    Positioned.fill(
                      child: Image.memory(
                        widget.imageBytes,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                  ],
                ),
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

            // 3) 핸들: 수동 조절 모드 → 경계선 핸들 / 균등 모드 → 여백 핸들
            ..._buildHandles(
              useManual: useManual,
              colorScheme: colorScheme,
              fitScale: fitScale,
              handleLength: handleLength,
              imgX: imgX,
              imgY: imgY,
              dispW: dispW,
              dispH: dispH,
              imageRect: imageRect,
              boxRect: boxRect,
            ),

            // 7) 안내 문구
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
                  useManual
                      ? '각 경계선을 드래그하거나 좌측 패널에서 위치(px)를 조절하세요  •  수동 조절 모드'
                      : '상/하/좌/우 경계선을 드래그하여 영역을 조절하세요  •  '
                      '가로 ${widget.settings.effectiveHorizontalCount} × 세로 ${widget.settings.effectiveVerticalCount} 분할',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 수동 모드일 땐 모든 경계선에 핸들을, 균등 모드일 땐 상/하/좌/우 여백 핸들을 만든다.
  List<Widget> _buildHandles({
    required bool useManual,
    required ColorScheme colorScheme,
    required double fitScale,
    required double handleLength,
    required double imgX,
    required double imgY,
    required double dispW,
    required double dispH,
    required Rect imageRect,
    required Rect boxRect,
  }) {
    if (!useManual) {
      final primary = colorScheme.primary;
      return [
        // 상단
        Positioned(
          left: imgX,
          top: boxRect.top - (handleLength / 2),
          width: dispW,
          height: handleLength,
          child: _buildPaddingBar(
            cursor: SystemMouseCursors.resizeUpDown,
            color: primary,
            horizontal: true,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            onDrag: (delta) {
              final deltaImg = delta / fitScale;
              final maxTop = widget.imageHeight -
                  widget.settings.bottomPadding -
                  10.0;
              final newTop =
                  (widget.settings.topPadding + deltaImg).clamp(0.0, maxTop);
              widget.onSettingsChanged(
                widget.settings.copyWith(topPadding: newTop),
              );
            },
          ),
        ),
        // 하단
        Positioned(
          left: imgX,
          top: boxRect.bottom - (handleLength / 2),
          width: dispW,
          height: handleLength,
          child: _buildPaddingBar(
            cursor: SystemMouseCursors.resizeUpDown,
            color: primary,
            horizontal: true,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            onDrag: (delta) {
              final deltaImg = delta / fitScale;
              final maxBottom = widget.imageHeight -
                  widget.settings.topPadding -
                  10.0;
              final newBottom =
                  (widget.settings.bottomPadding - deltaImg).clamp(0.0, maxBottom);
              widget.onSettingsChanged(
                widget.settings.copyWith(bottomPadding: newBottom),
              );
            },
          ),
        ),
        // 좌측
        Positioned(
          left: boxRect.left - (handleLength / 2),
          top: imgY,
          width: handleLength,
          height: dispH,
          child: _buildPaddingBar(
            cursor: SystemMouseCursors.resizeLeftRight,
            color: primary,
            horizontal: false,
            margin: const EdgeInsets.symmetric(vertical: 16),
            onDrag: (delta) {
              final deltaImg = delta / fitScale;
              final maxLeft = widget.imageWidth -
                  widget.settings.rightPadding -
                  10.0;
              final newLeft =
                  (widget.settings.leftPadding + deltaImg).clamp(0.0, maxLeft);
              widget.onSettingsChanged(
                widget.settings.copyWith(leftPadding: newLeft),
              );
            },
          ),
        ),
        // 우측
        Positioned(
          left: boxRect.right - (handleLength / 2),
          top: imgY,
          width: handleLength,
          height: dispH,
          child: _buildPaddingBar(
            cursor: SystemMouseCursors.resizeLeftRight,
            color: primary,
            horizontal: false,
            margin: const EdgeInsets.symmetric(vertical: 16),
            onDrag: (delta) {
              final deltaImg = delta / fitScale;
              final maxRight = widget.imageWidth -
                  widget.settings.leftPadding -
                  10.0;
              final newRight =
                  (widget.settings.rightPadding - deltaImg).clamp(0.0, maxRight);
              widget.onSettingsChanged(
                widget.settings.copyWith(rightPadding: newRight),
              );
            },
          ),
        ),
      ];
    }

    // ── 수동 조절: 모든 경계선에 핸들 생성 ──
    final colB = widget.settings.columnBoundaries;
    final rowB = widget.settings.rowBoundaries;
    if (colB.length < 2 || rowB.length < 2) {
      return const [];
    }

    final primary = colorScheme.primary;
    final handles = <Widget>[];

    // 세로 경계선 핸들 (좌우 드래그)
    for (var i = 0; i < colB.length; i++) {
      final index = i;
      handles.add(
        Positioned(
          left: imageRect.left + colB[index] * fitScale - (handleLength / 2),
          top: imgY,
          width: handleLength,
          height: dispH,
          child: _buildPaddingBar(
            cursor: SystemMouseCursors.resizeLeftRight,
            color: primary,
            horizontal: false,
            margin: const EdgeInsets.symmetric(vertical: 16),
            onDrag: (delta) {
              final newVal = (colB[index] + delta / fitScale).round();
              widget.onSettingsChanged(
                widget.settings.withUpdatedColumnBoundary(
                  index,
                  newVal,
                  imageWidth: widget.imageWidth,
                ),
              );
            },
          ),
        ),
      );
    }

    // 가로 경계선 핸들 (상하 드래그)
    for (var i = 0; i < rowB.length; i++) {
      final index = i;
      handles.add(
        Positioned(
          left: imgX,
          top: imageRect.top + rowB[index] * fitScale - (handleLength / 2),
          width: dispW,
          height: handleLength,
          child: _buildPaddingBar(
            cursor: SystemMouseCursors.resizeUpDown,
            color: primary,
            horizontal: true,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            onDrag: (delta) {
              final newVal = (rowB[index] + delta / fitScale).round();
              widget.onSettingsChanged(
                widget.settings.withUpdatedRowBoundary(
                  index,
                  newVal,
                  imageHeight: widget.imageHeight,
                ),
              );
            },
          ),
        ),
      );
    }

    return handles;
  }

  /// 여백/경계선 핸들의 드래그 바 한 개를 만든다.
  Widget _buildPaddingBar({
    required MouseCursor cursor,
    required Color color,
    required bool horizontal,
    required EdgeInsets margin,
    required ValueChanged<double> onDrag,
  }) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: horizontal
            ? null
            : (details) => onDrag(details.delta.dx),
        onVerticalDragUpdate: !horizontal
            ? null
            : (details) => onDrag(details.delta.dy),
        child: Center(
          child: Container(
            width: horizontal ? null : 4,
            height: horizontal ? 4 : null,
            margin: margin,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 2),
              ],
            ),
          ),
        ),
      ),
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

    // 3) 격자선
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.85);

    final useManual = settings.useManualBoundaries;
    final colB = settings.columnBoundaries;
    final rowB = settings.rowBoundaries;
    final colCount = settings.effectiveHorizontalCount;
    final rowCount = settings.effectiveVerticalCount;

    if (useManual && colB.length >= 2 && rowB.length >= 2) {
      // 수동 모드: 경계선 위치대로 격자와 번호 표시
      for (var i = 1; i < colB.length - 1; i++) {
        final gx = boxRect.left + colB[i] * scale;
        canvas.drawLine(Offset(gx, boxRect.top), Offset(gx, boxRect.bottom), gridPaint);
      }
      for (var i = 1; i < rowB.length - 1; i++) {
        final gy = boxRect.top + rowB[i] * scale;
        canvas.drawLine(Offset(boxRect.left, gy), Offset(boxRect.right, gy), gridPaint);
      }
      for (var row = 0; row < rowCount; row++) {
        for (var col = 0; col < colCount; col++) {
          final index = row * colCount + col;
          final cell = Rect.fromLTWH(
            boxRect.left + colB[col] * scale,
            boxRect.top + rowB[row] * scale,
            (colB[col + 1] - colB[col]) * scale,
            (rowB[row + 1] - rowB[row]) * scale,
          );
          _paintNumberChip(canvas, cell, index + 1);
        }
      }
    } else {
      // 균등 모드: 1컷 크기 기준 균등 격자
      final sprite = settings.calcSpriteSize(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      final cellW = sprite.spriteWidth * scale;
      final cellH = sprite.spriteHeight * scale;

      // 세로 격자선 (가로 분할)
      for (var i = 1; i < colCount; i++) {
        final gx = boxRect.left + i * cellW;
        canvas.drawLine(Offset(gx, boxRect.top), Offset(gx, boxRect.bottom), gridPaint);
      }
      // 가로 격자선 (세로 분할)
      for (var i = 1; i < rowCount; i++) {
        final gy = boxRect.top + i * cellH;
        canvas.drawLine(Offset(boxRect.left, gy), Offset(boxRect.right, gy), gridPaint);
      }

      // 각 컷 번호
      for (var row = 0; row < rowCount; row++) {
        for (var col = 0; col < colCount; col++) {
          final index = row * colCount + col;
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
        oldDelegate.imageRect != imageRect ||
        oldDelegate.settings != settings ||
        oldDelegate.scale != scale ||
        oldDelegate.settings.columnBoundaries != settings.columnBoundaries ||
        oldDelegate.settings.rowBoundaries != settings.rowBoundaries;
  }
}

/// 투명 배경을 시각적으로 나타내기 위한 체커보드(격자 무늬) 커스텀 페인터
class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter({
    this.squareSize = 12.0,
    this.color1 = const Color(0xFFE0E0E0),
    this.color2 = const Color(0xFFFFFFFF),
  });

  final double squareSize;
  final Color color1;
  final Color color2;

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()..color = color1;
    final paint2 = Paint()..color = color2;

    for (double y = 0; y < size.height; y += squareSize) {
      for (double x = 0; x < size.width; x += squareSize) {
        final isEven = ((x / squareSize).floor() + (y / squareSize).floor()) % 2 == 0;
        final rect = Rect.fromLTWH(
          x,
          y,
          x + squareSize > size.width ? size.width - x : squareSize,
          y + squareSize > size.height ? size.height - y : squareSize,
        );
        canvas.drawRect(rect, isEven ? paint1 : paint2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}