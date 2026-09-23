# weirdbb91/claude-mem — upstream 을 자동으로 따라가는 포크

upstream(thedotmack/claude-mem)의 한도 가드 버그(#4068 — 주간 한도가 리셋된 뒤에도 기억 기록이 멈춘 채로 남음)를
고친 PR #4072 를 얹은 포크다. **사람이 할 일은 없다.**

- **매일 자동 동기화(05:23 KST)** — `.github/workflows/fork-sync.yml` 이 `scripts/fork-sync.sh` 를 돌린다. upstream 최신
  릴리스(플러그인 버전을 올린 커밋)를 병합하고 `fork/patches/` 를 얹은 뒤, 릴리스 시점의 의존성(`npm --before` +
  upstream 번들에 박힌 Agent SDK 버전)으로 빌드한다. 타입 검사와 전체 테스트를 통과해야만 main 에 푸시한다.
  실패하면 아무것도 푸시하지 않고 GitHub 가 실패 메일을 보낸다 — 설치본은 마지막 정상 버전 그대로다.
- **자동 졸업** — upstream 이 버그를 고쳐 `tests/fork` 가 upstream 그대로 통과하면, 패치를 빼고 upstream 을 그대로 따라간다.
- **자동 설치** — Claude Code 는 이 저장소를 마켓플레이스 `thedotmack`(플러그인 `claude-mem@thedotmack`)으로
  `autoUpdate: true` 로 받는다. 새 버전은 세션 시작 뒤 자동 설치되고, claude-mem 훅이 워커를 새 버전으로 바꾼다.
- 옛 버전 캐시(`~/.claude/plugins/cache/thedotmack/claude-mem/<옛 버전>`)는 지우지 않는다 — 먼저 열린 세션의 훅이 끊긴다.

지금 바로 동기화: `gh workflow run fork-sync.yml -R weirdbb91/claude-mem`

## 기록

- 2026-09-23 운영자: "아 그럼 folk를 따서 쓸 수는 없는건가요?" → "네, 포크로 진행해 주세요."
- 2026-09-23 운영자: "아니 업데이트 발생해도 편리하게 반영할 수 있게 해주셔야죠. 뭐 이런저런 절차들 너무 많으면 […]"
  → 수동 절차를 모두 없애고 위 자동화로 바꿨다.
