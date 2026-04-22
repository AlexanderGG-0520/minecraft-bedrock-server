# minecraft-bedrock-server

A Kubernetes-friendly container runtime for Minecraft Bedrock Dedicated Server.

## Recent updates (fixes + features)

### Fixes

- **Resolved conflict with Bash's reserved `UID` variable**
  - Using `UID` directly can be unreliable because Bash treats it as a readonly special variable.
  - Runtime identity is now configured via `RUN_UID` / `RUN_GID`, with compatibility fallback to `UID` / `GID` when needed.

- **Made `BDS_CHANNEL=stable` effective**
  - `entrypoint.sh` now interprets `BDS_CHANNEL` and `BDS_STABLE_VERSION`, so the `bedrock-stable` target can reliably install a pinned version.

### New feature

- **Container healthcheck support**
  - Added `docker-entrypoint.sh healthcheck`.
  - The check validates both the `.ready` file and the `bedrock_server` process.
  - Added Docker `HEALTHCHECK` for orchestrator-friendly liveness monitoring.

## Key environment variables

### Required

- `EULA=true`

### Runtime user

- `RUN_UID` (recommended: set explicitly, for example `1000`)
- `RUN_GID` (recommended: set explicitly, for example `1000`)

> Current behavior: when `RUN_UID` / `RUN_GID` are unset, the entrypoint falls back to `UID` / `GID` when available. In practice, this means the effective runtime user may match the current process user (for example `0` when the container starts as root), so set `RUN_UID` and `RUN_GID` explicitly if you require `1000:1000`.

### Bedrock version selection

- `VERSION` (default: `latest`)
  - `latest`: resolve the current Linux download URL from the official page
  - Explicit version is also supported (for example: `1.21.130.4`)
- `BDS_CHANNEL` (default: `latest`)
  - If set to `stable`, you must also set `BDS_STABLE_VERSION`
- `BDS_STABLE_VERSION`
- `BDS_DOWNLOAD_URL` (highest priority override when set)

## Usage examples

```bash
docker run --rm \
  -e EULA=true \
  -e RUN_UID=1000 \
  -e RUN_GID=1000 \
  -p 19132:19132/udp \
  -v "$(pwd)/data:/data" \
  <image>
```

Stable channel example:

```bash
docker run --rm \
  -e EULA=true \
  -e BDS_CHANNEL=stable \
  -e BDS_STABLE_VERSION=1.21.130.4 \
  -v "$(pwd)/data:/data" \
  <image>
```
