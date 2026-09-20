import 'dart:typed_data';

/// 웹이 아닌 플랫폼(VM 테스트, 데스크톱 등)에서 사용되는 AI 배경 제거 스텁.
class AiBgRemover {
  static Future<Uint8List> removeBackground(Uint8List imageBytes) async {
    throw UnsupportedError('AI 배경 제거는 웹(브라우저)에서만 지원됩니다.');
  }
}