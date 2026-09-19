/// 스프라이트 시트 분할 설정 (이미지 분할 수 및 드래그 영역 설정 기반).
class CropSettings {
  const CropSettings({
    required this.horizontalCount,
    required this.verticalCount,
    this.topPadding = 0.0,
    this.bottomPadding = 0.0,
  });

  /// 가로 분할 수 (열 개수).
  final int horizontalCount;

  /// 세로 분할 수 (행 개수).
  final int verticalCount;

  /// 상단 여백 (픽셀 단위).
  final double topPadding;

  /// 하단 여백 (픽셀 단위).
  final double bottomPadding;

  /// 전체 컷 수.
  int get totalCount => horizontalCount * verticalCount;

  /// 설정 변경용 불변 객체 복사 메서드
  CropSettings copyWith({
    int? horizontalCount,
    int? verticalCount,
    double? topPadding,
    double? bottomPadding,
  }) {
    return CropSettings(
      horizontalCount: horizontalCount ?? this.horizontalCount,
      verticalCount: verticalCount ?? this.verticalCount,
      topPadding: topPadding ?? this.topPadding,
      bottomPadding: bottomPadding ?? this.bottomPadding,
    );
  }

  /// 박스 크기가 (imageWidth × imageHeight)일 때 1컷(스프라이트) 크기 계산.
  ({int spriteWidth, int spriteHeight}) calcSpriteSize({
    required int imageWidth,
    required int imageHeight,
  }) {
    // 상/하단 여백을 제외한 실제 분할 영역의 높이 계산
    final activeHeight = (imageHeight - topPadding - bottomPadding)
        .clamp(1.0, imageHeight.toDouble());

    return (
    spriteWidth: (imageWidth / horizontalCount).round(),
    spriteHeight: (activeHeight / verticalCount).round(),
    );
  }

  /// index번째 컷의 크롭 영역 반환 (이미지 픽셀 좌표).
  ({int x, int y, int width, int height}) cropRectFor(
      int index,
      int imageWidth,
      int imageHeight,
      ) {
    assert(index >= 0 && index < totalCount);
    final sprite = calcSpriteSize(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    final col = index % horizontalCount;
    final row = index ~/ horizontalCount;

    return (
    x: col * sprite.spriteWidth,
    // topPadding 만큼 y 시작 위치 이동
    y: topPadding.round() + (row * sprite.spriteHeight),
    width: sprite.spriteWidth,
    height: sprite.spriteHeight,
    );
  }

  @override
  String toString() =>
      'CropSettings($horizontalCount×$verticalCount = $totalCount컷, topPadding: $topPadding, bottomPadding: $bottomPadding)';
}