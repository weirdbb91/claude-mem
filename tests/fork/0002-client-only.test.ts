// Fork-owned check (weirdbb91/claude-mem, see FORK.md) for fork/patches/0002-client-only.patch:
// a client-only machine must never spawn, recycle or stop the worker it reaches over a tunnel.
import { afterAll, afterEach, describe, expect, it, mock, spyOn } from 'bun:test';
import { existsSync } from 'fs';
import { join } from 'path';
import * as realInfrastructure from '../../src/services/infrastructure/index.js';
import * as realSupervisor from '../../src/supervisor/index.js';
import * as realSpawn from '../../src/shared/spawn.js';
import { acquireSpawnLock, isClientOnly, releaseSpawnLock } from '../../src/shared/worker-spawn-gate';
import { httpShutdown } from '../../src/services/infrastructure/HealthMonitor';
import { shutdownWorkerAndWait } from '../../src/services/install/shutdown-helper';
import { resolveDataDir } from '../../src/shared/paths';

const setClientOnly = (value: string | undefined) => {
  if (value === undefined) delete process.env.CLAUDE_MEM_CLIENT_ONLY;
  else process.env.CLAUDE_MEM_CLIENT_ONLY = value;
};

describe('CLAUDE_MEM_CLIENT_ONLY', () => {
  afterEach(() => setClientOnly(undefined));

  it('defaults to off, so an ordinary machine still spawns its own worker', () => {
    expect(isClientOnly()).toBe(false);
    expect(acquireSpawnLock()).toBe(true);
    releaseSpawnLock();
  });

  it('refuses the spawn lock, so no launcher can start a local worker', () => {
    setClientOnly('true');
    expect(acquireSpawnLock()).toBe(false);
    expect(existsSync(join(resolveDataDir(), 'spawn.lock'))).toBe(false);
  });

  it('refuses to stop the remote worker', async () => {
    setClientOnly('true');
    await expect(httpShutdown(1)).rejects.toThrow('CLAUDE_MEM_CLIENT_ONLY');
    await expect(shutdownWorkerAndWait(1)).rejects.toThrow('CLAUDE_MEM_CLIENT_ONLY');
  });

  it('rejects anything but true/false', () => {
    setClientOnly('yes');
    expect(() => isClientOnly()).toThrow('must be "true" or "false"');
  });
});

// The worker on the far side of the tunnel runs another plugin version and has no PID file here.
const realInfrastructureSnapshot = { ...realInfrastructure };
const realSupervisorSnapshot = { ...realSupervisor };
const realSpawnSnapshot = { ...realSpawn };
const spawnCalls: string[][] = [];
mock.module('../../src/services/infrastructure/index.js', () => ({
  checkVersionMatch: () => Promise.resolve({ matches: false, pluginVersion: '13.28.0', workerVersion: '13.27.1' }),
  isPortInUse: () => Promise.resolve(true),
}));
mock.module('../../src/supervisor/index.js', () => ({
  validateWorkerPidFile: () => 'missing',
  readOwnedWorkerPidInfo: () => null,
}));
mock.module('../../src/shared/spawn.js', () => ({
  spawnHidden: (_command: string, args: string[]) => {
    spawnCalls.push(args);
    return { pid: 5151, unref: () => {}, on: () => {} };
  },
}));

describe('CLAUDE_MEM_CLIENT_ONLY — remote worker on another version', () => {
  const originalFetch = global.fetch;
  afterEach(() => {
    global.fetch = originalFetch;
    setClientOnly(undefined);
  });
  afterAll(() => {
    mock.module('../../src/services/infrastructure/index.js', () => realInfrastructureSnapshot);
    mock.module('../../src/supervisor/index.js', () => realSupervisorSnapshot);
    mock.module('../../src/shared/spawn.js', () => realSpawnSnapshot);
  });

  it('keeps using it instead of killing it and spawning a local one', async () => {
    setClientOnly('true');
    const calls: string[] = [];
    global.fetch = mock((url: string | URL | Request, init?: RequestInit) => {
      calls.push(`${(init?.method ?? 'GET').toUpperCase()} ${url.toString()}`);
      const body = { version: '13.27.1', uptime: 3600 };
      return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(body), text: () => Promise.resolve(JSON.stringify(body)) } as unknown as Response);
    }) as unknown as typeof fetch;
    const killSpy = spyOn(process, 'kill');
    const workerUtils = await import(`../../src/shared/worker-utils.js?client-only=${Date.now()}`);

    expect(await workerUtils.ensureWorkerRunning()).toBe(true);
    expect(killSpy).not.toHaveBeenCalled();
    expect(spawnCalls).toEqual([]);
    expect(calls.filter((c) => c.startsWith('POST'))).toEqual([]);
    killSpy.mockRestore();
  });
});
