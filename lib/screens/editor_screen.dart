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

  bool _busy = false;

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  // ── 이미지 업로드 ────────────────────────────────────
  Future<void> _pickImage() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: '스프라이트 시트 이미지 선택',
      );
      if (files.isEmpty) return;

      final file = files.first;
      final bytes = await file.readAsBytes();
      final decoded = SpriteCropper.decode(bytes);
      if (!mounted) return;

      setState(() {
        _sourceBytes = bytes;
        _decoded = decoded;
        _fileName = file.name;
        // 새 이미지를 올릴 때 상/하단 여백 초기화
        _settings = _settings.copyWith(
          topPadding: 0.0,
          bottomPadding: 0.0,
        );
      });
    } on FormatException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('이미지를 불러오지 못했습니다: $e');
    }
  }

  // ── 설정 변경 ────────────────────────────────────────
// ── 설정 변경 ────────────────────────────────────────
  void _updateSettings({
    CropSettings? settings,
    int? horizontalCount,
    int? verticalCount,
    double? topPadding,
    double? bottomPadding,
  }) {
    setState(() {
      if (settings != null) {
        _settings = settings;
      } else {
        _settings = _settings.copyWith(
          horizontalCount: horizontalCount,
          verticalCount: verticalCount,
          topPadding: topPadding,
          bottomPadding: bottomPadding,
        );
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
      if (mounted) setState(() => _busy = false);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 스프라이트 시트 분할 도구'),
        centerTitle: false,
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: Row(
        children: [
// lib/screens/editor_screen.dart

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
              onPickImage: _pickImage,
              // [수정] Named Parameter를 명시적으로 전달하거나 _updateSettings 연동
              onSettingsChanged: ({horizontalCount, verticalCount}) {
                _updateSettings(
                  horizontalCount: horizontalCount,
                  verticalCount: verticalCount,
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

    // 1컷 크기 계산
    final sprite = _settings.calcSpriteSize(
      imageWidth: decoded.width,
      imageHeight: decoded.height,
    );

    // 여백 제외 실제 가이드 영역 높이
    final activeHeight = (decoded.height - _settings.topPadding - _settings.bottomPadding).round();

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
              onSettingsChanged: (updatedSettings) {
                _updateSettings(settings: updatedSettings);
              },
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
                  '선택 영역: ${decoded.width} × $activeHeight px  •  '
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
          Text('스프라이트 시트를 업로드해 주세요', style: theme.textTheme.titleMedium?.copyWith(color: Colors.blue[700])),
          const SizedBox(height: 8),
          Text(
            '이미지 가이드 박스의 상/하단 경계선을 드래그하여 높이를 조절하고\n가로/세로 분할 수만큼 등분할 수 있습니다.',
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