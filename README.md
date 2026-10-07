# 스프라이트 시트 분할 도구 (spritesCut)

브라우저에서만 동작하는 이미지 처리 도구입니다. Flutter Web으로 만들어졌으며, 모든 이미지 디코딩·분할·압축이 이용자의 기기 안에서 끝나므로 **이미지가 서버로 업로드되지 않습니다.**

- 라이브 사이트: https://sprite-cut-zip.netlify.app/

## 제공 기능

| 도구 | 설명 |
| --- | --- |
| 이미지 자르기 | 스프라이트 시트 이미지를 가로×세로 격자로 잘라 프레임 PNG로 저장합니다. 균등 분할, 여백 지정, 수동 경계선, 단색 배경 제거, 프레임별 개별 편집, 실행 취소/다시 실행을 지원합니다. |
| GIF 스프라이트 분할 | GIF 애니메이션의 모든 프레임을 개별 PNG 모음 또는 하나의 스프라이트 시트로 변환합니다. 투명 영역 자동 제거와 단색 배경 제거를 함께 쓸 수 있습니다. |
| 다중 이미지 일괄 자르기 | 여러 사진을 고정한 크기로 가운데 정렬 자르고 PNG를 ZIP으로 묶습니다. 기준 사진 한 장으로 크기와 위치를 정하면 나머지에 같은 규칙이 적용됩니다. |

이미지 자르기와 GIF 분할이 만드는 ZIP 안에는 프레임 PNG 외에 애니메이션 미리보기용 `index.html`과 배경 이미지(`stage.jpg`)가 함께 들어 있습니다. 일괄 자르기의 ZIP에는 PNG만 들어갑니다.

## 웹 콘텐츠 구조

검색 엔진과 방문자가 바로 읽을 수 있도록 `web/` 아래에 정적 HTML 문서를 함께 둡니다. `flutter build web` 시 `build/web/`으로 그대로 복사되어 배포됩니다.

```
web/
├─ index.html                     # 앱 진입점 + SEO 메타 태그 + noscript 안내
├─ about.html / -en               # 서비스 소개, 운영 정보
├─ contact.html / -en             # 문의처
├─ privacy.html / -en             # 개인정보처리방침
├─ terms.html / -en               # 이용약관
├─ faq.html / -en                 # 자주 묻는 질문 (FAQPage 구조화 데이터)
├─ guides/                        # 사용 가이드 9종 (한국어·영어 각)
├─ 404.html
├─ robots.txt  sitemap.xml  ads.txt
└─ assets/site.css  assets/og.png
```

- 정적 페이지는 빌드 의존성이 없는 순수 HTML과 `assets/site.css` 한 장으로 이루어져 있습니다.
- 한국어(`/`)와 영어(`-en`) 페이지를 `hreflang`으로 서로 연결했습니다.
- 앱 화면 하단의 안내 링크(`lib/widgets/site_footer.dart`)에서 위 문서로 이동할 수 있습니다.
- 도메인을 바꿀 때는 `web/` 안의 `https://sprite-cut-zip.netlify.app` 문자열과 `lib/widgets/site_footer.dart`의 `SiteFooter.origin`을 함께 바꿔 주세요.

## 의존성

| 패키지 | 용도 |
| --- | --- |
| `file_picker` | 파일 선택 |
| `image` | 이미지 디코딩·크롭·GIF 인코딩 (순수 Dart) |
| `archive` | ZIP 생성 |
| `file_saver` | 파일 저장 |
| `url_launcher` | 안내 페이지 외부 링크 |

## 개발

```bash
flutter pub get
flutter run -d chrome      # 웹으로 실행
flutter test               # 단위·위젯 테스트
flutter analyze
flutter build web --release
```

`build/web`을 정적 호스팅에 올리면 됩니다. SPA 특성상 알 수 없는 경로 요청에는 `404.html`이 응답하도록 호스팅을 설정하고, 정적 HTML 문서가 `index.html`로 리다이렉트되지 않도록 rewrites 설정을 확인해 주세요.