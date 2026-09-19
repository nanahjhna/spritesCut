import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/crop_settings.dart';
import '../services/sprite_cropper.dart';
import '../widgets/control_panel.dart';
import '../widgets/image_canvas.dart';

/// 스프라이트 시트 분할 메인 화면.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  Uint8List? _sourceBytes;
  img.Image? _decoded;
  String? _fileName;

  CropSettings _settings = const CropSettings(
    horizontalCount: 4,
    verticalCount: 1,
  );

  late final TextEditingController _horizontalController =
  TextEditingController(text: '${_settings.horizontalCount}');
  late final TextEditingController _verticalController =
  TextEditingController(text: '${_settings.verticalCount}');

  // 상/하단 여백 조절용 Controllers
  late final TextEditingController _topPaddingController =
  TextEditingController(text: '${_settings.topPadding.round()}');
  late final TextEditingController _bottomPaddingController =
  TextEditingController(text: '${_settings.bottomPadding.round()}');

  bool _busy = false;

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    _topPaddingController.dispose();
    _bottomPaddingController.dispose();
    super.dispose();
  }

  // ── 이미지 업로드 ────────────────────────────────────
  Future<void> _pickImage() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: '스프라이트 시트 이미지 선택',
      );

      if (files == null || files.isEmpty) return;

      final file = files.first;

      // PlatformFile에서 readAsBytes()를 직접 호출합니다.
      final bytes = await file.readAsBytes();
      final decoded = SpriteCropper.decode(bytes);

      if (!mounted) return;

      setState(() {
        _sourceBytes = bytes;
        _decoded = decoded;
        _fileName = file.name;

        _settings = _settings.copyWith(
          topPadding: 0.0,
          bottomPadding: 0.0,
        );
        _topPaddingController.text = '0';
        _bottomPaddingController.text = '0';
      });
    } on FormatException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('이미지를 불러오지 못했습니다: $e');
    }
  }

  // ── 설정 변경 (드래그 및 텍스트 입력 시 동기화) ────────
  void _updateSettings(CropSettings nextSettings) {
    setState(() {
      _settings = nextSettings;

      // 텍스트 필드 값이 현재 입력 중인 상태와 다를 때만 동기화 (포커스/커서 튀김 방지)
      final topText = '${nextSettings.topPadding.round()}';
      if (_topPaddingController.text != topText) {
        _topPaddingController.text = topText;
      }

      final bottomText = '${nextSettings.bottomPadding.round()}';
      if (_bottomPaddingController.text != bottomText) {
        _bottomPaddingController.text = bottomText;
      }

      final hText = '${nextSettings.horizontalCount}';
      if (_horizontalController.text != hText) {
        _horizontalController.text = hText;
      }

      final vText = '${nextSettings.verticalCount}';
      if (_verticalController.text != vText) {
        _verticalController.text = vText;
      }
    });
  }

  // ── ZIP 저장 ─────────────────────────────────────────
  Future<void> _saveZip() async {
    final bytes = _sourceBytes;
    if (bytes == null) {
      _showSnack('이미지를 먼저 업로드해 주세요.');
      return;
    }

    setState(() => _busy = true);
    try {
      final frames = SpriteCropper.cropFrames(
        sourceBytes: bytes,
        settings: _settings,
      );
      final zip = SpriteCropper.buildZip(frames);

      // ext: 'zip' -> fileExtension: 'zip' 으로 수정
      await FileSaver.instance.saveFile(
        name: 'sprites',
        bytes: zip,
        fileExtension: 'zip',
        mimeType: MimeType.zip,
      );

      if (!mounted) return;
      _showSnack('${frames.length}개의 스프라이트를 sprites.zip으로 저장했습니다.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('저장에 실패했습니다: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── 레이아웃 ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.blue[700]!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 스프라이트 시트 분할 도구'),
        centerTitle: false,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: ControlPanel(
              fileName: _fileName,
              imageWidth: _decoded?.width,
              imageHeight: _decoded?.height,
              settings: _settings,
              busy: _busy,
              horizontalController: _horizontalController,
              verticalController: _verticalController,
              topPaddingController: _topPaddingController,
              bottomPaddingController: _bottomPaddingController,
              onPickImage: _pickImage,
              onSettingsChanged: ({
                int? horizontalCount,
                int? verticalCount,
                double? topPadding,
                double? bottomPadding,
              }) {
                _updateSettings(
                  _settings.copyWith(
                    horizontalCount: horizontalCount ?? _settings.horizontalCount,
                    verticalCount: verticalCount ?? _settings.verticalCount,
                    topPadding: topPadding ?? _settings.topPadding,
                    bottomPadding: bottomPadding ?? _settings.bottomPadding,
                  ),
                );
              },
              onSave: _saveZip,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildPreview()),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final bytes = _sourceBytes;
    final decoded = _decoded;
    if (bytes == null || decoded == null) {
      return const _EmptyState();
    }

    final sprite = _settings.calcSpriteSize(
      imageWidth: decoded.width,
      imageHeight: decoded.height,
    );

    final activeHeight =
    (decoded.height - _settings.topPadding - _settings.bottomPadding)
        .round()
        .clamp(0, decoded.height);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ImageCanvas(
              key: ValueKey(bytes),
              imageBytes: bytes,
              imageWidth: decoded.width,
              imageHeight: decoded.height,
              settings: _settings,
              onSettingsChanged: _updateSettings,
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border(
                top: BorderSide(color: Colors.blue[200]!),
              ),
            ),
            child: Text(
              '전체: ${decoded.width} × ${decoded.height} px  •  '
                  '영역 높이: $activeHeight px (상단: ${_settings.topPadding.round()}px, 하단: ${_settings.bottomPadding.round()}px)  •  '
                  '1컷: ${sprite.spriteWidth} × ${sprite.spriteHeight} px  •  '
                  '총 ${_settings.totalCount}개 (${_settings.horizontalCount}×${_settings.verticalCount})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.blue[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 이미지가 아직 없을 때 표시하는 빈 상태 화면.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.crop,
            size: 96,
            color: Colors.blue[200],
          ),
          const SizedBox(height: 16),
          Text(
            '스프라이트 시트를 업로드해 주세요',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '가이드 박스의 핸들을 드래그하거나\n좌측 컨트롤 패널에서 세로 높이/여백 수치를 직접 수정할 수 있습니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.blue[400],
            ),
          ),
        ],
      ),
    );
  }
}