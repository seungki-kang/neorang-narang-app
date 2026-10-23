# neorang_narang_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## 개발 운영

너랑나랑은 `main → 작업 브랜치 → PR → CI 통과 → 병합`으로 개발합니다.
[CONTRIBUTING.md](CONTRIBUTING.md)에 브랜치·검증·병합 및 보호 규칙 설정 기준을 정리했습니다.
기존 CI는 `.github/workflows/nn-ci.yml`, 로컬 검사는 `tool/Invoke-NN-CI.ps1`을 사용합니다.
