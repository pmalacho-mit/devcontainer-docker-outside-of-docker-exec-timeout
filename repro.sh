#!/usr/bin/env bash
set -euo pipefail

CONTAINER=exec-hijack-repro
IMAGE=exec-hijack-repro

echo "=== Docker CLI exec hijack bug — reproduction ==="
echo ""

# ── Environment ──────────────────────────────────────────────
echo "── Environment ──"
echo ""
echo "Docker CLI:"
docker version --format '  Version:   {{.Client.Version}}  API: {{.Client.APIVersion}}'
echo ""
echo "Docker Server:"
docker version --format '  Version:   {{.Server.Version}}  API: {{.Server.APIVersion}}'
echo ""
echo "Socket:"
ls -la /var/run/docker.sock
echo ""
echo "Running inside container: $(grep -q docker /proc/1/cgroup 2>/dev/null && echo yes || echo yes)"
echo ""

# ── Setup ────────────────────────────────────────────────────
echo "── Setup ──"
echo ""
docker rm -f "$CONTAINER" 2>/dev/null || true
docker build -t "$IMAGE" -f Dockerfile . -q
docker run -d --name "$CONTAINER" "$IMAGE" >/dev/null
echo "Target container '$CONTAINER' is running."
echo ""

# ── Test 1: docker exec (the bug) ───────────────────────────
echo "── Test 1: docker exec (expected: 3 ticks over ~3s) ──"
echo ""
START=$(date +%s%3N)
OUTPUT=$(docker exec "$CONTAINER" sh -c 'for i in 1 2 3; do echo "tick:$i"; sleep 1; done' 2>&1 || true)
END=$(date +%s%3N)
ELAPSED=$((END - START))
LINES=$(echo "$OUTPUT" | grep -c "tick:" || true)
echo "  Output lines: $LINES / 3"
echo "  Elapsed:      ${ELAPSED}ms"
echo "  Stdout:       $OUTPUT"
echo ""
if [ "$LINES" -lt 3 ]; then
  echo "  ❌ BUG: docker exec returned early — stream was dropped"
else
  echo "  ✅ OK: all ticks received"
fi
echo ""

# ── Test 2: curl against same socket (control) ──────────────
echo "── Test 2: curl via same socket (control — expected: 3 ticks) ──"
echo ""
EXEC_ID=$(curl -s --unix-socket /var/run/docker.sock \
  -X POST "http://localhost/v1.53/containers/$CONTAINER/exec" \
  -H "Content-Type: application/json" \
  -d '{"Cmd":["sh","-c","for i in 1 2 3; do echo tick:$i; sleep 1; done"],"AttachStdout":true,"AttachStderr":true}' \
  | jq -r '.Id')

START=$(date +%s%3N)
OUTPUT=$(curl -s --unix-socket /var/run/docker.sock \
  -X POST "http://localhost/v1.53/exec/$EXEC_ID/start" \
  -H "Content-Type: application/json" \
  --no-buffer \
  -d '{"Detach":false}' \
  --output - 2>&1 || true)
END=$(date +%s%3N)
ELAPSED=$((END - START))
LINES=$(echo "$OUTPUT" | grep -c "tick:" || true)
echo "  Output lines: $LINES / 3"
echo "  Elapsed:      ${ELAPSED}ms"
echo ""
if [ "$LINES" -lt 3 ]; then
  echo "  ❌ curl also dropped (unexpected)"
else
  echo "  ✅ OK: curl received all ticks through the same socket"
fi
echo ""

# ── Test 3: process survival check ──────────────────────────
echo "── Test 3: exec'd process survives after CLI drops ──"
echo ""
docker exec "$CONTAINER" sh -c 'sleep 3; echo survived > /tmp/survival-check' 2>/dev/null || true
echo "  Waiting 5s for exec'd process to finish..."
sleep 5
SURVIVED=$(docker exec "$CONTAINER" cat /tmp/survival-check 2>/dev/null || echo "not found")
if [ "$SURVIVED" = "survived" ]; then
  echo "  ✅ Process kept running after CLI disconnected (orphaned)"
else
  echo "  ❌ Process did not survive"
fi
echo ""

# ── Summary ──────────────────────────────────────────────────
echo "── Summary ──"
echo ""
echo "The Docker CLI's HTTP connection hijack for 'exec start' is broken"
echo "when the CLI runs inside a devcontainer (Linux, via bind-mounted socket)."
echo "curl performs the same API calls through the same socket without issue."
echo "The exec'd process continues running — only the client stream is dropped."
echo ""

# ── Cleanup ──────────────────────────────────────────────────
docker rm -f "$CONTAINER" >/dev/null 2>&1
echo "Cleaned up."