import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:spritescut/main.dart';

/// GIF를 미리 준비해 주는 픽커.
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

/// 3프레임 24×24 GIF.
Uint8List _fakeGifBytes() {
  final encoder = img.GifEncoder()..repeat = 0;
  for (final color in [
    img.ColorRgba8(255, 0, 0, 255),
    img.ColorRgba8(0, 255, 0, 255),
    img.ColorRgba8(0, 0, 255, 255),
  ]) {
    final image = img.Image(width: 24, height: 24, numChannels: 4);
    img.fill(image, color: color);
    encoder.addFrame(image, duration: 10);
  }
  return Uint8List.fromList(encoder.finish()!);
}

void main() {
  late FilePickerPlatform originalPlatform;

  setUp(() {
    originalPlatform = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _FakeFilePickerPlatform(
      _FakePlatformFile(name: 'anim.gif', fileBytes: _fakeGifBytes()),
    );
  });

  tearDown(() {
    FilePickerPlatform.instance = originalPlatform;
  });

  Future<void> openGifScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SpriteCutApp());
    await tester.tap(find.text('GIF 스프라이트 분할'));
    await tester.pumpAndSettle();
  }

  testWidgets('GIF를 선택하면 프레임 정보와 저장 버튼이 나타난다', (tester) async {
    await openGifScreen(tester);

    expect(find.text('GIF 파일을 선택해 주세요'), findsOneWidget);

    await tester.tap(find.text('GIF 선택'));
    await tester.pumpAndSettle();

    // 파일 정보
    expect(find.text('anim.gif'), findsOneWidget);
    expect(find.textContaining('3 프레임'), findsOneWidget);
    expect(find.textContaining('24×24 px'), findsOneWidget);

    // 저장 옵션 3종
    expect(find.text('스프라이트 시트 (PNG)'), findsOneWidget);
    expect(find.text('프레임 PNG 모음 (ZIP)'), findsOneWidget);
    expect(find.text('GIF 다시 저장'), findsOneWidget);

    // 레이아웃 선택 (가로/세로/격자)
    expect(find.text('가로 한 줄'), findsOneWidget);
    expect(find.text('세로 한 줄'), findsOneWidget);
    expect(find.text('격자'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('시트 레이아웃을 격자로 바꾸면 결과 미리보기가 갱신된다', (tester) async {
    await openGifScreen(tester);
    await tester.tap(find.text('GIF 선택'));
    await tester.pumpAndSettle();

    expect(find.textContaining('3×1 = 3컷'), findsOneWidget);

    await tester.tap(find.text('격자'));
    await tester.pumpAndSettle();

    // 3컷 → 2×2 격자
    expect(find.textContaining('2×2 = 3컷'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('세로 한 줄로 바꾸면 결과 미리보기가 갱신된다', (tester) async {
    await openGifScreen(tester);
    await tester.tap(find.text('GIF 선택'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('세로 한 줄'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1×3 = 3컷'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('단색 배경 제거를 켜고 끄해도 크래시하지 않는다', (tester) async {
    await openGifScreen(tester);
    await tester.tap(find.text('GIF 선택'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('단색 배경 제거'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('단색 배경 제거'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('뒤로 가기 버튼으로 메인 화면에 돌아온다', (tester) async {
    await openGifScreen(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('원하는 작업을 선택해 주세요'), findsOneWidget);
    expect(find.text('이미지 자르기'), findsOneWidget);
  });
}
