import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 웹 사이트의 정적 안내 페이지로 이동하는 링크 모음.
///
/// 앱 화면 안에서 약관·가이드·문의 페이지로 갈 수 있게 만들어
/// 탐색 경로를 명확히 하고, 검색 엔진이 따라갈 수 있는 내부 링크를 제공한다.
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  /// 웹 배포 주소. 정적 페이지와 동일한 origin을 사용한다.
  static const String origin = 'https://spritescut.netlify.app';

  static const List<({String label, String path})> _links = [
    (label: '기능 가이드', path: '/guides/index.html'),
    (label: '자주 묻는 질문', path: '/faq.html'),
    (label: '서비스 소개', path: '/about.html'),
    (label: '문의하기', path: '/contact.html'),
    (label: '개인정보처리방침', path: '/privacy.html'),
    (label: '이용약관', path: '/terms.html'),
  ];

  Future<void> _open(BuildContext context, String path) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uri = Uri.parse('$origin$path');
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      launched = false;
    }
    if (!launched && context.mounted) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('페이지를 열 수 없습니다. 주소로 직접 접속해 주세요: $uri'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '안내',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 2,
            children: [
              for (final link in _links)
                TextButton(
                  onPressed: () => _open(context, link.path),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  child: Text(
                    link.label,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '모든 이미지 처리는 이용자의 기기 안에서만 수행됩니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}