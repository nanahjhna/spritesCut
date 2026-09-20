/// 프레임(컷) 하나의 크롭 영역 (이미지 픽셀 좌표).
typedef CropRect = ({int x, int y, int width, int height});

/// 스프라이트 시트 분할 설정 (균등 분할 또는 수동 경계선 기반).
class CropSettings {
  const CropSettings({
    required this.horizontalCount,
    required this.verticalCount,
    this.topPadding = 0.0,
    this.bottomPadding = 0.0,
    this.leftPadding = 0.0,
    this.rightPadding = 0.0,
    this.useManualBoundaries = false,
    this.columnBoundaries = const [],
    this.rowBoundaries = const [],
    this.frameRects = const [],
  });

  /// 가로 분할 수 (열 개수, 균등 분할 모드 기준).
  final int horizontalCount;

  /// 세로 분할 수 (행 개수, 균등 분할 모드 기준).
  final int verticalCount;

  /// 상단 여백 (픽셀 단위, 균등 분할 모드에서 사용).
  final double topPadding;

  /// 하단 여백 (픽셀 단위, 균등 분할 모드에서 사용).
  final double bottomPadding;

  /// 좌측 여백 (픽셀 단위, 균등 분할 모드에서 사용).
  final double leftPadding;

  /// 우측 여백 (픽셀 단위, 균등 분할 모드에서 사용).
  final double rightPadding;

  /// true이면 [columnBoundaries] / [rowBoundaries] 위치대로 자른다.
  final bool useManualBoundaries;

  /// 세로 경계선들의 절대 x 좌표 (px, 오름차순, 길이 = 열 수 + 1).
  final List<int> columnBoundaries;

  /// 가로 경계선들의 절대 y 좌표 (px, 오름차순, 길이 = 행 수 + 1).
  final List<int> rowBoundaries;

  /// 프레임별 개별 크롭 오버라이드.
  ///
  /// 인덱스 = 프레임 번호(0부터), `null`이면 전역 그리드 계산값을 사용한다.
  /// 길이가 `totalCount`보다 짧아도 안전 (없는 인덱스는 기본값).
  final List<CropRect?> frameRects;

  /// 안전한 가로 분할 수 (0 이하 입력 방지)
  int get safeHorizontalCount => horizontalCount <= 0 ? 1 : horizontalCount;

  /// 안전한 세로 분할 수 (0 이하 입력 방지)
  int get safeVerticalCount => verticalCount <= 0 ? 1 : verticalCount;

  /// 실제 사용하는 열 수 (수동 모드면 경계 개수 기반).
  int get effectiveHorizontalCount {
    if (useManualBoundaries && columnBoundaries.length >= 2) {
      return columnBoundaries.length - 1;
    }
    return safeHorizontalCount;
  }

  /// 실제 사용하는 행 수 (수동 모드면 경계 개수 기반).
  int get effectiveVerticalCount {
    if (useManualBoundaries && rowBoundaries.length >= 2) {
      return rowBoundaries.length - 1;
    }
    return safeVerticalCount;
  }

  /// 전체 컷 수.
  int get totalCount => effectiveHorizontalCount * effectiveVerticalCount;

  /// 설정 변경용 불변 객체 복사 메서드
  CropSettings copyWith({
    int? horizontalCount,
    int? verticalCount,
    double? topPadding,
    double? bottomPadding,
    double? leftPadding,
    double? rightPadding,
    bool? useManualBoundaries,
    List<int>? columnBoundaries,
    List<int>? rowBoundaries,
    List<CropRect?>? frameRects,
  }) {
    return CropSettings(
      horizontalCount: horizontalCount ?? this.horizontalCount,
      verticalCount: verticalCount ?? this.verticalCount,
      topPadding: topPadding ?? this.topPadding,
      bottomPadding: bottomPadding ?? this.bottomPadding,
      leftPadding: leftPadding ?? this.leftPadding,
      rightPadding: rightPadding ?? this.rightPadding,
      useManualBoundaries: useManualBoundaries ?? this.useManualBoundaries,
      columnBoundaries: columnBoundaries ?? this.columnBoundaries,
      rowBoundaries: rowBoundaries ?? this.rowBoundaries,
      frameRects: frameRects ?? this.frameRects,
    );
  }

  /// 수동 모드로 전환하면서 균등 간격의 경계선을 초기화한다.
  ///
  /// 상/하/좌/우 여백을 반영한 균등 분할 위치로 [columnBoundaries],
  /// [rowBoundaries]를 생성한다.
  CropSettings withEqualBoundaries({
    required int imageWidth,
    required int imageHeight,
  }) {
    final cols = safeHorizontalCount;
    final rows = safeVerticalCount;
    final left = leftPadding.round();
    final right = rightPadding.round();
    final top = topPadding.round();
    final bottom = bottomPadding.round();

    final activeW = (imageWidth - left - right).clamp(1, imageWidth);
    final activeH = (imageHeight - top - bottom).clamp(1, imageHeight);

    final colB = List<int>.generate(
      cols + 1,
      (i) => left + (activeW * i / cols).round(),
    );
    colB[cols] = left + activeW; // 우측 여백 보정

    final rowB = List<int>.generate(
      rows + 1,
      (i) => top + (activeH * i / rows).round(),
    );
    rowB[rows] = top + activeH; // 하단 여백 보정

    return copyWith(
      useManualBoundaries: true,
      columnBoundaries: colB,
      rowBoundaries: rowB,
    );
  }

  /// columnBoundaries의 [index]번째 경계를 [value]로 갱신한다.
  ///
  /// 인접 경계 사이로만 움직이도록 clamp된다 (최소 간격 [minGap] px).
  CropSettings withUpdatedColumnBoundary(
    int index,
    int value, {
    required int imageWidth,
    int minGap = 10,
  }) {
    final bounds = List<int>.from(columnBoundaries);
    if (bounds.length < 2) return this;
    final safeIndex = index.clamp(0, bounds.length - 1);
    final lo = safeIndex == 0 ? 0 : bounds[safeIndex - 1] + minGap;
    final hi = safeIndex == bounds.length - 1
        ? imageWidth
        : bounds[safeIndex + 1] - minGap;
    if (lo > hi) {
      // 인접 경계가 최소 간격보다 가까울 때: 중간값으로 고정 (예외 방지)
      bounds[safeIndex] = ((lo + hi) / 2).round();
    } else {
      bounds[safeIndex] = value.clamp(lo, hi);
    }
    return copyWith(columnBoundaries: bounds);
  }

  /// rowBoundaries의 [index]번째 경계를 [value]로 갱신한다.
  ///
  /// 인접 경계 사이로만 움직이도록 clamp된다 (최소 간격 [minGap] px).
  CropSettings withUpdatedRowBoundary(
    int index,
    int value, {
    required int imageHeight,
    int minGap = 10,
  }) {
    final bounds = List<int>.from(rowBoundaries);
    if (bounds.length < 2) return this;
    final safeIndex = index.clamp(0, bounds.length - 1);
    final lo = safeIndex == 0 ? 0 : bounds[safeIndex - 1] + minGap;
    final hi = safeIndex == bounds.length - 1
        ? imageHeight
        : bounds[safeIndex + 1] - minGap;
    if (lo > hi) {
      // 인접 경계가 최소 간격보다 가까울 때: 중간값으로 고정 (예외 방지)
      bounds[safeIndex] = ((lo + hi) / 2).round();
    } else {
      bounds[safeIndex] = value.clamp(lo, hi);
    }
    return copyWith(rowBoundaries: bounds);
  }

  /// 전체 프레임의 최소/최대 크기 범위를 계산한다.
  ({int minWidth, int minHeight, int maxWidth, int maxHeight}) frameSizeRange({
    required int imageWidth,
    required int imageHeight,
  }) {
    var minW = imageWidth, minH = imageHeight, maxW = 0, maxH = 0;
    for (var i = 0; i < totalCount; i++) {
      final r = cropRectFor(i, imageWidth, imageHeight);
      if (r.width < minW) minW = r.width;
      if (r.height < minH) minH = r.height;
      if (r.width > maxW) maxW = r.width;
      if (r.height > maxH) maxH = r.height;
    }
    return (
      minWidth: minW,
      minHeight: minH,
      maxWidth: maxW,
      maxHeight: maxH,
    );
  }

  /// 1번째(0번 인덱스) 컷 크기 계산 (기존 균등 분할과 동일 동작).
  ({int spriteWidth, int spriteHeight}) calcSpriteSize({
    required int imageWidth,
    required int imageHeight,
  }) {
    final r = cropRectFor(0, imageWidth, imageHeight);
    return (spriteWidth: r.width, spriteHeight: r.height);
  }

  /// index번째 컷의 크롭 영역 반환 (이미지 픽셀 좌표).
  ///
  /// 해당 프레임에 개별 오버라이드([frameRects])가 있으면 그것을 우선 사용한다.
  ({int x, int y, int width, int height}) cropRectFor(
      int index,
      int imageWidth,
      int imageHeight,
      ) {
    final hCount = effectiveHorizontalCount;
    final vCount = effectiveVerticalCount;
    final total = totalCount;

    // 인덱스 범위 초과 예외 방지 (clamp 적용)
    final safeIndex = index.clamp(0, total > 0 ? total - 1 : 0);

    // 프레임별 개별 크롭 오버라이드 우선 적용
    final override = _frameRectAt(safeIndex);
    if (override != null) return override;

    final col = safeIndex % hCount;
    final row = safeIndex ~/ hCount;

    if (useManualBoundaries) {
      final x = columnBoundaries[col];
      final y = rowBoundaries[row];
      return (
        x: x,
        y: y,
        width: columnBoundaries[col + 1] - x,
        height: rowBoundaries[row + 1] - y,
      );
    }

    // 균등 분할: 여백을 제외한 활성 영역 기준
    final activeW = (imageWidth - leftPadding - rightPadding)
        .clamp(1.0, imageWidth.toDouble());
    final activeH = (imageHeight - topPadding - bottomPadding)
        .clamp(1.0, imageHeight.toDouble());

    final cellW = (activeW / hCount).round();
    final cellH = (activeH / vCount).round();

    return (
      x: leftPadding.round() + (col * cellW),
      y: topPadding.round() + (row * cellH),
      width: cellW,
      height: cellH,
    );
  }

  /// [index]번째 프레임의 최종 크롭 영역.
  ///
  /// 오버라이드가 있으면 그것을, 없으면 전역 그리드 계산값을 반환한다.
  CropRect frameRectFor(int index, int imageWidth, int imageHeight) {
    final override = _frameRectAt(index);
    if (override != null) return override;
    return cropRectFor(index, imageWidth, imageHeight);
  }

  /// [index]번째 프레임의 크롭 영역을 [rect]로 교체한다.
  ///
  /// [rect]가 `null`이면 해당 프레임을 전역 그리드 기본값으로 되돌린다.
  CropSettings withFrameRect(int index, {required CropRect? rect}) {
    final count = totalCount;
    if (count <= 0) return this;
    final safe = index.clamp(0, count - 1);

    final list = List<CropRect?>.filled(count, null);
    for (var i = 0; i < frameRects.length && i < count; i++) {
      list[i] = frameRects[i];
    }
    list[safe] = rect;
    return copyWith(frameRects: list);
  }

  /// 모든 프레임별 오버라이드를 제거한다.
  CropSettings clearFrameRects() => copyWith(frameRects: const []);

  /// 이미지 경계 안 + 최소 크기([minSize])를 보장하도록 크롭 rect를 보정한다.
  static CropRect clampFrameRect({
    required int x,
    required int y,
    required int width,
    required int height,
    required int imageWidth,
    required int imageHeight,
    int minSize = 8,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0) {
      return (x: 0, y: 0, width: 0, height: 0);
    }
    final minW = minSize < imageWidth ? minSize : imageWidth;
    final minH = minSize < imageHeight ? minSize : imageHeight;

    var w = width < minW ? minW : (width > imageWidth ? imageWidth : width);
    var h = height < minH ? minH : (height > imageHeight ? imageHeight : height);
    var cx = x < 0 ? 0 : (x > imageWidth - w ? imageWidth - w : x);
    var cy = y < 0 ? 0 : (y > imageHeight - h ? imageHeight - h : y);
    return (x: cx, y: cy, width: w, height: h);
  }

  CropRect? _frameRectAt(int index) {
    if (index < 0 || index >= frameRects.length) return null;
    return frameRects[index];
  }

  @override
  String toString() =>
      'CropSettings($effectiveHorizontalCount×$effectiveVerticalCount = $totalCount컷'
      '${useManualBoundaries ? ', manual' : ', top: $topPadding, bottom: $bottomPadding, left: $leftPadding, right: $rightPadding'})';
}