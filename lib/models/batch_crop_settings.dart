/// 다중 이미지 일괄 자르기에서 사용하는 고정 크롭 영역 설정.
///
/// 모든 사진에 **동일한 크기**로 자른다. 위치는 기본적으로 가운데 정렬이며,
/// [offsetX]/[offsetY] 로 사각형 중심을 상대(비율)로 이동할 수 있다.
/// 오프셋은 -1.0 ~ 1.0 범위로, 이미지 크기가 달라도 항상 이미지 안에
/// 같은 비율의 위치가 적용된다.
class BatchCropSettings {
  const BatchCropSettings({
    required this.width,
    required this.height,
    this.offsetX = 0,
    this.offsetY = 0,
  })  : assert(width >= minSize, 'crop width is out of range'),
        assert(width <= maxSize, 'crop width is out of range'),
        assert(height >= minSize, 'crop height is out of range'),
        assert(height <= maxSize, 'crop height is out of range'),
        assert(offsetX >= -1 && offsetX <= 1, 'offsetX is out of range'),
        assert(offsetY >= -1 && offsetY <= 1, 'offsetY is out of range');

  /// 화면을 처음 열었을 때 사용하는 기본 크기 (Full HD, 가운데 정렬).
  static const BatchCropSettings defaultSize =
      BatchCropSettings(width: 1920, height: 1080);

  /// 자를 수 있는 최소 픽셀 수.
  static const int minSize = 8;

  /// 자를 수 있는 최대 픽셀 수.
  static const int maxSize = 20000;

  /// 결과 이미지의 가로 픽셀 수.
  final int width;

  /// 결과 이미지의 세로 픽셀 수.
  final int height;

  /// 가운데 대비 가로 방향 이동 비율 (-1.0 ~ 1.0).
  ///
  /// 0 = 가운데, -1 = 사각형 왼쪽이 이미지 왼쪽에 붙음, +1 = 오른쪽에 붙음.
  final double offsetX;

  /// 가운데 대비 세로 방향 이동 비율 (-1.0 ~ 1.0).
  ///
  /// 0 = 가운데, -1 = 사각형 위쪽이 이미지 위에 붙음, +1 = 아래쪽에 붙음.
  final double offsetY;

  /// '1920 × 1080' 형태의 표시용 문자열.
  String get label => '$width × $height';

  /// '1920x1080' 형태의 파일명·라벨용 문자열.
  String get fileToken => '${width}x$height';

  /// 가로/세로 비율.
  double get aspectRatio => height == 0 ? 0 : width / height;

  /// 오프셋이 0(가운데 정렬)인지 여부.
  bool get isCentered => offsetX == 0 && offsetY == 0;

  /// 캔버스/라벨용 위치 표시 문자열 ('가로 0% · 세로 0%').
  String get positionLabel =>
      '가로 ${(offsetX * 100).round()}% · 세로 ${(offsetY * 100).round()}%';

  /// 입력값을 허용 범위 안으로 보정해 새 설정을 만든다. (오프셋 유지)
  BatchCropSettings withSize(int width, int height) => copyWith(
        width: width.clamp(minSize, maxSize),
        height: height.clamp(minSize, maxSize),
      );

  /// 입력값을 허용 범위 안으로 보정해 만드는 정적 팩토리 (기본 가운데 정렬).
  static BatchCropSettings clamped(int width, int height) => BatchCropSettings(
        width: width.clamp(minSize, maxSize),
        height: height.clamp(minSize, maxSize),
      );

  /// 가운데 정렬 위치로 되돌린 설정.
  BatchCropSettings withCentered() => copyWith(offsetX: 0, offsetY: 0);

  /// 불변 객체 복사 (기존 코드베이스의 [CopyWith] 관례를 따름).
  BatchCropSettings copyWith({
    int? width,
    int? height,
    double? offsetX,
    double? offsetY,
  }) =>
      BatchCropSettings(
        width: width ?? this.width,
        height: height ?? this.height,
        offsetX: offsetX ?? this.offsetX,
        offsetY: offsetY ?? this.offsetY,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchCropSettings &&
          other.width == width &&
          other.height == height &&
          other.offsetX == offsetX &&
          other.offsetY == offsetY;

  @override
  int get hashCode => Object.hash(width, height, offsetX, offsetY);

  @override
  String toString() => 'BatchCropSettings($label)';
}