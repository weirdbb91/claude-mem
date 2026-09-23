// Fork-owned check (weirdbb91/claude-mem, see FORK.md). It only uses API that upstream exports too, so
// scripts/fork-sync.sh runs it against plain upstream: once it passes there, upstream has fixed the
// stale quota guard (#4068) and the fork stops carrying fork/patches.
import { describe, expect, it } from 'bun:test';
import { RateLimitStore, shouldAbortForQuota, type RateLimitInfo } from '../../src/services/worker/RateLimitStore';

const OAUTH = 'Claude Code OAuth token (read from system keychain at spawn) profile=default';
const NOW = Date.UTC(2026, 8, 23, 1, 55); // 2026-09-23 10:55 KST, the live repro
const H = 3_600_000;
const D = 24 * H;
const sec = (ms: number) => Math.floor(ms / 1000); // live rate_limit_event payloads carry epoch seconds

// A five_hour-typed event carrying every window's live reading, as Claude Code sends it.
const fiveHourEvent = (sevenDayUtilization: number) =>
  ({
    status: 'allowed',
    rateLimitType: 'five_hour',
    resetsAt: sec(NOW + 4 * H),
    unifiedWindows: {
      five_hour: { utilization: 0.05, resetsAt: sec(NOW + 4 * H) },
      seven_day: { utilization: sevenDayUtilization, resetsAt: sec(NOW + 6 * D) },
    },
  }) as RateLimitInfo;

describe('stale quota guard (#4068)', () => {
  it('ignores a seven_day snapshot whose window already reset', () => {
    const store = new RateLimitStore();
    store.set({ status: 'allowed_warning', rateLimitType: 'seven_day', utilization: 0.99, resetsAt: sec(NOW - 19 * H) });
    store.set(fiveHourEvent(0.04));
    expect(shouldAbortForQuota(OAUTH, store, NOW).abort).toBe(false);
  });

  it('takes the fresh unifiedWindows reading over an older in-window snapshot', () => {
    const store = new RateLimitStore();
    store.set({ status: 'allowed_warning', rateLimitType: 'seven_day', utilization: 0.98, resetsAt: sec(NOW + 4 * D) });
    store.set(fiveHourEvent(0.24));
    expect(shouldAbortForQuota(OAUTH, store, NOW).abort).toBe(false);
  });

  it('still stops on a real weekly exhaustion reported through unifiedWindows', () => {
    const store = new RateLimitStore();
    store.set(fiveHourEvent(0.95));
    const decision = shouldAbortForQuota(OAUTH, store, NOW);
    expect([decision.abort, decision.window]).toEqual([true, 'seven_day']);
  });
});
