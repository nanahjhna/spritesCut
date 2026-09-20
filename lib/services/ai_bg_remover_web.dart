import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('removeAiBg')
external JSPromise<JSAny> _removeAiBg(JSAny dataUrl);

/// 브라우저(웹) 환경용 AI 배경 제거 구현.
class AiBgRemover {
  /// 브라우저 내부 AI(WebAssembly/ONNX)를 실행하여 배경을 제거합니다.
  static Future<Uint8List> removeBackground(Uint8List imageBytes) async {
    try {
      // 0. index.html의 module 스크립트가 아직 로드되지 않은 경우 명확한 오류 표시
      if (!globalContext.has('removeAiBg')) {
        throw Exception(
          'AI 라이브러리(CDN)가 로드되지 않았습니다. 네트워크 연결을 확인한 후 다시 시도해 주세요.',
        );
      }

      // 1. Uint8List -> Base64 Data URL 변환
      final base64String = base64Encode(imageBytes);
      final dataUrl = 'data:image/png;base64,$base64String';

      // 2. index.html의 window.removeAiBg 호출
      final jsPromise = _removeAiBg(dataUrl.toJS);
      final resultAny = await jsPromise.toDart;

      // 3. 자바스크립트에서 넘어온 Uint8Array(JSAny)를 Uint8List로 변환
      final jsTypedArray = resultAny as JSUint8Array;
      return jsTypedArray.toDart;
    } catch (e) {
      throw Exception('AI 배경 제거 실패: $e');
    }
  }
}