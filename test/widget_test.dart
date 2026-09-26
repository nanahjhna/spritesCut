import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spritescut/main.dart';

void main() {
  /// 메인 화면에서 '이미지 자르기' 카드를 눌러 편집기로 이동한다.
  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.text('이미지 자르기'));
    await tester.pumpAndSettle();
  }

  testWidgets('앱이 시작되면 메인 화면에서 작업을 선택할 수 있다', (tester) async {
    await tester.pumpWidget(const SpriteCutApp());

    expect(find.text('스프라이트 시트 도구'), findsOneWidget);
    expect(find.text('원하는 작업을 선택해 주세요'), findsOneWidget);
    expect(find.text('이미지 자르기'), findsOneWidget);
    expect(find.text('GIF 스프라이트 분할'), findsOneWidget);

    // 편집기 화면은 아직 showing되지 않는다.
    expect(find.text('이미지 업로드'), findsNothing);
  });

  testWidgets('이미지 자르기를 선택하면 편집기 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(const SpriteCutApp());
    await openEditor(tester);

    expect(find.text('AI 스프라이트 시트 분할 도구'), findsOneWidget);
    expect(find.text('이미지 업로드'), findsOneWidget);
    expect(find.text('스프라이트 시트를 업로드해 주세요'), findsOneWidget);

    // 설정 기본값이 가로 4, 세로 1로 표시된다.
    expect(find.text('4'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('GIF 스프라이트 분할을 선택하면 GIF 분할 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(const SpriteCutApp());

    await tester.tap(find.text('GIF 스프라이트 분할'));
    await tester.pumpAndSettle();

    expect(find.text('GIF 스프라이트 분할'), findsOneWidget);
    expect(find.text('GIF 파일을 선택해 주세요'), findsOneWidget);
    expect(find.text('GIF 선택'), findsOneWidget);
  });

  testWidgets('이미지가 없으면 저장 버튼이 비활성화된다', (tester) async {
    await tester.pumpWidget(const SpriteCutApp());
    await openEditor(tester);

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '저장 및 다운로드 (ZIP)'),
    );
    expect(saveButton.onPressed, isNull);
  });
}
