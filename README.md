# devcontainer-docker-outside-of-docker-exec-timeout

## Bug

When running `docker exec` from inside a devcontainer (using [`docker-outside-of-docker`](https://github.com/devcontainers/features/tree/main/src/docker-outside-of-docker)),
the CLI's attached stdio stream is dropped after ~530ms regardless of command duration.
The exec'd process continues running inside the target container — only the client-side
stream is severed.

The same API calls made with `curl` through the **same Unix socket** work correctly,
proving the socket transport is fine.

## Environment

- **Host:** macOS (Apple Silicon) with Docker Desktop 4.65.0
- **Devcontainer:** `mcr.microsoft.com/devcontainers/base:ubuntu` with `docker-outside-of-docker:1`
- **Docker CLI inside devcontainer:** 29.2.1-29.3 (currently pinned 29.2.1 as version installed in devcontainer to minimize differences)
- **Docker CLI on host:** 29.2.1 (API 1.53) — works correctly
- **Docker Server:** 29.2.1 (API 1.53)

## Reproduction

### Prerequisites

- Docker Desktop (macOS or Windows)
- VS Code with Dev Containers extension (or any devcontainer CLI)

### Steps

1. Open this project in a devcontainer:
   ```
   devcontainer open .
   ```

2. Inside the devcontainer terminal, run:
   ```bash
   chmod +x repro.sh
   ./repro.sh
   ```

3. Observe:
   - **Test 1** (`docker exec`): prints only 1 tick, returns in ~530ms ❌
   - **Test 2** (`curl` via same socket): prints all 3 ticks, takes ~3s ✅
   - **Test 3** (process survival): exec'd process completes inside container ✅

### Manual quick repro

```bash
# Inside the devcontainer — broken:
docker exec <container> sh -c 'for i in 1 2 3; do echo tick:$i; sleep 1; done'
# Returns after ~530ms with only "tick:1"

# On the host — works:
docker exec <container> sh -c 'for i in 1 2 3; do echo tick:$i; sleep 1; done'
# Returns after ~3s with all three ticks
```

## Analysis

The Docker CLI uses HTTP connection hijacking for `exec start` — it sends
`Connection: Upgrade`, receives `101 Switching Protocols`, then takes over the
raw TCP/Unix socket connection for bidirectional stdio streaming. Something in
this hijack path fails when the CLI runs as a Linux binary inside a container
communicating over a bind-mounted Docker socket.

`curl` uses a plain HTTP POST and reads the chunked/streaming response body
without connection hijacking, which is why it succeeds through the same socket.

### Ruled out

| Hypothesis | Evidence against |
|---|---|
| socat proxy (docker-outside-of-docker non-root shim) | Bypassing socat via `/var/run/docker-host.sock` still drops |
| Docker Desktop `com.docker.backend` proxy | Host CLI works; bind-mounted socket bypasses host proxy |
| TTY vs demuxed stream | `-t` flag makes no difference |
| Socket transport / bind mount | `curl` works through the same socket |
| API version mismatch | CLI negotiates down to matching 1.53 |

## Expected behavior

`docker exec` should stream stdout/stderr for the full duration of the
exec'd process, matching the behavior observed on the host and via `curl`.

## Workaround

Use the Docker Engine API directly (e.g., via `dockerode` in Node.js or
`curl`) instead of shelling out to the Docker CLI.
