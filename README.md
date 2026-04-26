# devcontainer-docker-outside-of-docker-exec-timeout

## Bug

When running `docker exec` from inside a devcontainer (using [`docker-outside-of-docker`](https://github.com/devcontainers/features/tree/main/src/docker-outside-of-docker)),
the CLI's attached stdio stream is dropped after ~550ms regardless of command duration.
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

1. Open this project in a [devcontainer](https://code.visualstudio.com/docs/devcontainers/containers)

2. Inside the devcontainer terminal, run:
   ```bash
   ./repro.sh
   ```

3. Observe:
   - **Test 1** (`docker exec`): prints only 1 tick, returns in ~550ms ❌
   - **Test 2** (`curl` via same socket): prints all 3 ticks, takes ~3s ✅
   - **Test 3** (process survival): exec'd process completes inside container ✅

### Manual quick repro

```bash
# Inside the devcontainer — broken:
docker exec <container> sh -c 'for i in 1 2 3; do echo tick:$i; sleep 1; done'
# Returns after ~550ms with only "tick:1"

# On the host — works:
docker exec <container> sh -c 'for i in 1 2 3; do echo tick:$i; sleep 1; done'
# Returns after ~3s with all three ticks
```

## Expected behavior

`docker exec` should stream stdout/stderr for the full duration of the
exec'd process, matching the behavior observed on the host and via `curl`.

## Workaround

Use the Docker Engine API directly (e.g., via `dockerode` in Node.js or
`curl`) instead of shelling out to the Docker CLI.
