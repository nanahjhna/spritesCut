// 플랫폼별 AI 배경 제거 구현.
//
// 브라우저(웹)에서는 ai_bg_remover_web.dart의 실제 WebAssembly/ONNX 구현을,
// 그 외 플랫폼(VM 테스트, 데스크톱 등)에서는 스텁을 사용한다.
export 'ai_bg_remover_stub.dart'
    if (dart.library.js_interop) 'ai_bg_remover_web.dart';