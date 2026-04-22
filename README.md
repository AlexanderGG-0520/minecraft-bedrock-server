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

- `RUN_UID` (default: `1000`)
- `RUN_GID` (default: `1000`)

> For backward compatibility, `RUN_UID` falls back to `UID`, and `RUN_GID` falls back to `GID` when unset.

### Bedrock version selection

- `VERSION` (default: `latest`)
  - `latest`: resolve the current Linux download URL from the official page
  - Explicit version is also supported (for example: `1.21.130.4`)
- `BDS_CHANNEL` (default: `latest`)
  - If set to `stable`, you must also set `BDS_STABLE_VERSION`
- `BDS_STABLE_VERSION`
- `BDS_DOWNLOAD_URL` (highest priority override when set)

### S3 integration

- `S3_ENDPOINT`
- `S3_ACCESS_KEY`
- `S3_SECRET_KEY`

> This image uses the MinIO `mc` client for S3-compatible object storage operations.

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
