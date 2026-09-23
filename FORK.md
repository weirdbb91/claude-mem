# weirdbb91/claude-mem — 포크 운영 메모

upstream(thedotmack/claude-mem)에 아직 병합되지 않은 한도 가드 수정을 쓰기 위한 **임시 다리**다.
upstream 이 같은 수정을 릴리스하면 포크를 접고 원본 마켓플레이스로 돌아간다(맨 아래 "접기").

## 왜 (운영자 결정 2026-09-23)

- 증상: 계정 주간 한도가 리셋된 뒤에도 claude-mem 이 리셋 전 스냅숏(7일 99%)을 계속 읽어 기억 기록을 멈췄다
  (upstream #4068·#4076). 실제 사용량은 4% 였다.
- 운영자: "아 그럼 folk를 따서 쓸 수는 없는건가요?" → "네, 포크로 진행해 주세요."
- 설치본 수작업 패치(13.25.1 번들 직접 수정)를 대신한다. 소스 수정과 upstream 테스트로 가고, 플러그인 업데이트로
  사라지지 않으며, 13.25.1 에 없던 보안 수정(#4166, HTTP 설정 쓰기로 실행 파일 경로 변경)을 함께 받는다.

## upstream 과의 차이

- PR #4072 `fix(worker): refresh all quota windows from unifiedWindows, drop reset snapshots` — cherry-pick, 원 저자 유지.
- 그 수정으로 다시 빌드한 `plugin/` 번들.
- 이 파일.

마켓플레이스 이름은 `thedotmack` 그대로 둔다. 훅이 `plugins/cache/thedotmack/claude-mem` 경로를 고정으로 찾고,
플러그인 ID `claude-mem@thedotmack` 과 사용자 설정(`enabledPlugins`)이 그대로 유지된다.

## 빌드 재현성

루트에 lockfile 이 없어서 `npm install` 이 범위 안의 최신 Agent SDK 를 받는다. upstream 번들에 박힌 SDK 버전으로
고정해야 upstream 과 같은 번들이 나온다(2026-09-23 확인: 13.25.3 은 SDK 0.3.278 로 고정했을 때 바이트 동일).

    npm install --no-audit --no-fund
    npm install --no-save --no-audit --no-fund @anthropic-ai/claude-agent-sdk@$(git show upstream/main:plugin/scripts/worker-service.cjs | grep -o 'CLAUDE_AGENT_SDK_VERSION="[^"]*"' | head -1 | cut -d'"' -f2)

빌드 뒤 생기는 `*.map` 은 upstream 도 커밋하지 않는다 — 지운다.

## upstream 따라가기

별도 worktree 에서:

1. `git fetch upstream && git merge upstream/main` — `plugin/` 번들 충돌은 upstream 쪽으로 받는다
   (`git checkout --theirs -- plugin/ && git add plugin/`).
2. 위 "빌드 재현성" 대로 SDK 를 고정하고, 먼저 `upstream/main` 을 그대로 빌드해 커밋된 번들과 같은지 본다.
   다르면 멈추고 원인부터 찾는다.
3. 수정 포함 상태로 `npm run build` → `bun test tests/worker/rate-limit-store.test.ts` → `bun test tests`
   (upstream 기준선과 같은 실패만 있어야 한다).
4. 커밋 → main 병합·푸시 → `claude plugin marketplace update thedotmack && claude plugin update claude-mem@thedotmack`.
5. 옛 버전 캐시(`~/.claude/plugins/cache/thedotmack/claude-mem/<옛 버전>`)를 치우고 워커를 재기동한다.
   열린 세션의 훅은 자기 `CLAUDE_PLUGIN_ROOT`(옛 버전)를 먼저 쓰고, 워커 버전이 다르면 워커를 죽여 자기 버전으로
   되돌린다. 옛 캐시가 없으면 캐시의 최신 버전으로 넘어가 싸움이 멈춘다.

## 설치·접기

포크로 바꾸기(설정의 마켓플레이스 출처 한 줄만 바뀐다):

    claude plugin marketplace remove thedotmack
    claude plugin marketplace add weirdbb91/claude-mem
    claude plugin install claude-mem@thedotmack

접기 — upstream 이 #4072 또는 같은 수정을 릴리스하면 `weirdbb91/claude-mem` 자리에 `thedotmack/claude-mem` 을 넣어
같은 세 줄을 실행하고, 위 5번처럼 옛 캐시를 치운 뒤 워커를 재기동한다.
