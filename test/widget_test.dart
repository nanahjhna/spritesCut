import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spritescut/main.dart';

void main() {
  testWidgets('앱이 시작되면 업로드 버튼과 빈 상태 안내를 표시한다', (tester) async {
    await tester.pumpWidget(const SpriteCutApp());

    expect(find.text('AI 스프라이트 시트 분할 도구'), findsOneWidget);
    expect(find.text('이미지 업로드'), findsOneWidget);
    expect(find.text('스프라이트 시트를 업로드해 주세요'), findsOneWidget);

    // 설정 기본값이 가로 4, 세로 1로 표시된다.
    expect(find.text('4'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('이미지가 없으면 저장 버튼이 비활성화된다', (tester) async {
    await tester.pumpWidget(const SpriteCutApp());

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '저장 및 다운로드 (ZIP)'),
    );
    expect(saveButton.onPressed, isNull);
  });
}