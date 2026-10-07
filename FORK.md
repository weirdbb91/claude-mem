# weirdbb91/claude-mem — upstream 을 자동으로 따라가는 포크

upstream(thedotmack/claude-mem)에 `fork/patches/` 의 패치를 얹은 포크다. 평소엔 사람이 할 일이 없다. 단, upstream 이
패치가 닿는 코드를 바꾸면 패치가 충돌해 동기화가 멈춘다 — 실패 메일 말고는 드러나지 않고 설치본은 옛 버전에 머문다.
그때는 패치를 다시 쓴다: upstream 릴리스 커밋에서 `git apply --3way` 로 얹어 충돌을 의도대로 풀고(upstream 이 새로 낸
경로도 패치가 막아야 하는지 본다), 머리말은 두고 본문을 `git diff` 로 다시 만든다.

| 패치 | 내용 | 확인 |
|---|---|---|
| `0001-quota-guard-4072` | 한도 가드 버그(#4068 — 다른 창의 옛 주간 한도 값이 남아 기억 기록이 멈춤). v13.28.0 이 만료·초 단위 처리를 고쳐 `unifiedWindows` 팬아웃만 남음 | `tests/fork/0001-quota-guard-4072.test.ts` |
| `0002-client-only` | `CLAUDE_MEM_CLIENT_ONLY` — 다른 머신이 띄운 워커를 SSH 터널로 쓰는 클라이언트. 로컬 워커를 띄우지 않고, 버전이 달라도 워커를 죽이지 않고, 원격 워커를 멈추지 못한다. 워커에 닿지 않으면 훅 실패 카운터·`start` 훅 오류로 드러난다 | `tests/fork/0002-client-only.test.ts` |

패치마다 머리말에 `Marker:` 줄(그 패치가 빌드에 들어갔을 때만 번들에 나타나는 글자)을 둔다.

- **매일 자동 동기화(05:23 KST)** — `.github/workflows/fork-sync.yml` 이 `scripts/fork-sync.sh` 를 돌린다. upstream 최신
  릴리스(플러그인 버전을 올린 커밋)를 병합하고 `fork/patches/` 를 얹은 뒤, 릴리스 시점의 의존성(`npm --before` +
  upstream 번들에 박힌 Agent SDK 버전)으로 빌드한다. 타입 검사와 전체 테스트를 통과해야만 main 에 푸시한다.
  실패하면 아무것도 푸시하지 않고 GitHub 가 실패 메일을 보낸다 — 설치본은 마지막 정상 버전 그대로다.
  upstream 릴리스가 없어도 포크 자신의 파일(패치·스크립트·`tests/fork`·FORK.md·`.github/workflows`)이 마지막 동기화 뒤
  바뀌었으면 다시 빌드한다. `.github/workflows` 는 포크 것을 그대로 둔다(upstream 워크플로는 여기서 꺼져 있고, Actions 토큰은
  워크플로 파일을 푸시할 수 없다 — v13.28.0 이 `ci.yml` 을 바꿔 9/26~10/1 동기화가 모두 거부됐다).
- **자동 졸업** — 패치별로, upstream 그대로 `tests/fork/<패치 이름>.test.ts` 가 통과하면 그 패치만 빼고 따라간다.
- **자동 설치** — Claude Code 는 이 저장소를 마켓플레이스 `thedotmack`(플러그인 `claude-mem@thedotmack`)으로
  `autoUpdate: true` 로 받는다. 새 버전은 세션 시작 뒤 자동 설치되고, claude-mem 훅이 워커를 새 버전으로 바꾼다.
- 옛 버전 캐시(`~/.claude/plugins/cache/thedotmack/claude-mem/<옛 버전>`)는 지우지 않는다 — 먼저 열린 세션의 훅이 끊긴다.

지금 바로 동기화: `gh workflow run fork-sync.yml -R weirdbb91/claude-mem`

## 기록

- 2026-09-23 운영자: "아 그럼 folk를 따서 쓸 수는 없는건가요?" → "네, 포크로 진행해 주세요."
- 2026-09-23 운영자: "아니 업데이트 발생해도 편리하게 반영할 수 있게 해주셔야죠. 뭐 이런저런 절차들 너무 많으면 […]"
  → 수동 절차를 모두 없애고 위 자동화로 바꿨다.
- 2026-10-01 운영자: claude-mem 중앙 워커(baekmini) 방식 → "A로 진행할건데 우선 머신을 재시작 한번 하려고 합니다."
  (A = 포크 패치 + SSH 터널) → `0002-client-only` 추가. 9/26 부터 실패하던 동기화(패치 충돌·워크플로 푸시 거부)도 함께 고침.
- 2026-10-07 10/3~10/7 동기화가 0002 패치 충돌로 실패 → 패치를 v13.34.2 에 맞춰 다시 씀(새 경로 `ensureWorkerReadyWithin`·`holdSpawnLock` 도 막음).
