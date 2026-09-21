import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:spritescut/main.dart';

/// 실제 파일 선택 대화상자를 띄우지 않고 미리 준비된 바이트를 반환하는 픽커.
class _FakeFilePickerPlatform extends FilePickerPlatform {
  _FakeFilePickerPlatform(this._file);

  final PlatformFile _file;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    return [_file];
  }
}

/// 메모리에 들어 있는 스프라이트 시트 이미지를 흉내 내는 PlatformFile.
final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile({required this.name, required this.fileBytes});

  @override
  final String name;

  final Uint8List fileBytes;

  @override
  Uri get uri => Uri.dataFromBytes(fileBytes);

  @override
  XFile get xFile => XFile.fromData(fileBytes);

  @override
  int? lengthSync() => fileBytes.length;

  @override
  Future<int?> length() async => fileBytes.length;

  @override
  Future<Uint8List> readAsBytes() async => fileBytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(fileBytes);
}

/// 256×64 PNG (기본 4×1 분할에 적합한 크기).
Uint8List _fakePngBytes() {
  final image = img.Image(width: 256, height: 64);
  img.fill(image, color: img.ColorRgb8(120, 140, 200));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late FilePickerPlatform originalPlatform;

  setUp(() {
    originalPlatform = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _FakeFilePickerPlatform(
      _FakePlatformFile(name: 'sheet.png', fileBytes: _fakePngBytes()),
    );
  });

  tearDown(() {
    FilePickerPlatform.instance = originalPlatform;
  });

  Future<void> loadImage(WidgetTester tester) async {
    await tester.pumpWidget(const SpriteCutApp());
    await tester.tap(find.text('이미지 업로드'));
    await tester.pumpAndSettle();
  }

  Future<void> enterManualMode(WidgetTester tester) async {
    await tester.tap(find.text('수동 조절'));
    await tester.pumpAndSettle();
  }

  testWidgets('수동 조절 상태에서 가로 분할 수를 줄여도 크래시하지 않는다', (tester) async {
    await loadImage(tester);

    // 처음엔 균등 분할이므로 경계선 입력 필드가 없다.
    expect(find.byKey(const ValueKey('col-boundary-0')), findsNothing);

    await enterManualMode(tester);

    // 4×1 → 가로 경계 5개(0~4), 세로 경계 2개(0~1).
    expect(find.byKey(const ValueKey('col-boundary-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('row-boundary-1')), findsOneWidget);

    // 가로 분할 4 → 3: 경계 5개→4개로 축소 (컨트롤러 dispose 경로).
    await tester.enterText(find.widgetWithText(TextField, '가로 분할'), '3');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('col-boundary-4')), findsNothing);
    expect(find.byKey(const ValueKey('col-boundary-3')), findsOneWidget);
  });

  testWidgets('수동 조절 상태에서 경계 개수를 반복해서 바꿔도 크래시하지 않는다', (tester) async {
    await loadImage(tester);
    await enterManualMode(tester);

    // 4×1 → 3열: 경계 5개→4개로 축소 (컨트롤러 dispose 경로).
    await tester.enterText(find.widgetWithText(TextField, '가로 분할'), '3');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('col-boundary-4')), findsNothing);
    expect(find.byKey(const ValueKey('col-boundary-3')), findsOneWidget);

    // 3열 → 5열: 경계 4개→6개로 확대 (컨트롤러 추가 경로).
    await tester.enterText(find.widgetWithText(TextField, '가로 분할'), '5');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('col-boundary-5')), findsOneWidget);

    // 5열 → 2열: 경계 6개→3개로 재축소.
    await tester.enterText(find.widgetWithText(TextField, '가로 분할'), '2');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('col-boundary-4')), findsNothing);
    expect(find.byKey(const ValueKey('col-boundary-2')), findsOneWidget);

    // 2열 → 4열: 재확대.
    await tester.enterText(find.widgetWithText(TextField, '가로 분할'), '4');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('col-boundary-4')), findsOneWidget);
  });
}