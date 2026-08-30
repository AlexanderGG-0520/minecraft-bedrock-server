# Minecraft Bedrock Server

![Status checks](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-bedrock-server/status-checks.yml?branch=main&label=status%20checks)
[![Docker Pulls](https://img.shields.io/docker/pulls/alecjp02/minecraft-bedrock-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-bedrock-server/)
[![Docker Stars](https://img.shields.io/docker/stars/alecjp02/minecraft-bedrock-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-bedrock-server/)
[![GitHub Issues](https://img.shields.io/github/issues-raw/alexandergg-0520/minecraft-bedrock-server.svg)](https://github.com/alexandergg-0520/minecraft-bedrock-server/issues)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Falexandergg--0520%2Fminecraft--bedrock--server-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Kubernetes](https://img.shields.io/badge/kubernetes-oriented-blue)

A Kubernetes-oriented container image for **Minecraft Bedrock Dedicated Server (BDS)**, designed around persistent `/data`, explicit startup behavior, S3-compatible asset delivery, non-root runtime, health checks, and RCON-aware shutdown.

```bash
docker pull ghcr.io/alexandergg-0520/minecraft-bedrock-server:latest
```

Published image locations:

```text
GHCR:
ghcr.io/alexandergg-0520/minecraft-bedrock-server

Docker Hub:
alecjp02/minecraft-bedrock-server
```

## Why does this project exist?

There are already mature Bedrock server images, especially [`itzg/docker-minecraft-bedrock-server`](https://github.com/itzg/docker-minecraft-bedrock-server). This project is not trying to win by having the largest environment-variable surface or by automating every possible Bedrock workflow.

It exists for a narrower operational model:

- a container or Kubernetes Pod should be replaceable;
- the world and server state in `/data` should survive that replacement;
- Bedrock server installation should happen predictably at startup without overwriting worlds or key configuration files;
- behavior packs, resource packs, and an initial world archive should be deliverable independently from the container image;
- Kubernetes termination should use Minecraft-aware RCON shutdown when possible instead of treating BDS as an arbitrary Unix process;
- the normal runtime should not require root;
- invalid required configuration should fail before the server is started.

The image therefore focuses on **container lifecycle, persistent state, external asset delivery, and orchestration behavior** rather than broad end-user automation.

## Relationship to Minecartainer

[`Minecartainer`](https://github.com/AlexanderGG-0520/minecartainer) is the Java Edition project built around the same general operational direction: long-lived Minecraft state, disposable compute, explicit lifecycle boundaries, Kubernetes, GitOps, object storage, and graceful shutdown.

The Bedrock image is currently **less architecturally mature than Minecartainer**. That distinction is intentional to document rather than hide.

Today, this repository already has:

- persistent `/data` handling;
- a conceptual install phase followed by runtime;
- preservation of worlds and key BDS configuration during server replacement;
- S3-compatible delivery for packs and initial world archives;
- RCON-aware graceful shutdown;
- health checks;
- non-root runtime by default;
- static shell checks and image-build CI.

It does **not yet** have several of the stronger lifecycle and state-safety mechanisms used by Minecartainer, such as:

- a first-class independently invokable install-only lifecycle;
- managed installation metadata comparable to Minecartainer's install markers;
- strong ownership/state tracking for every externally delivered asset;
- lifecycle hook directories;
- the same depth of runtime smoke/regression coverage;
- the same level of fail-fast protection against ambiguous persistent-volume state.

So this README describes the Bedrock image **as it behaves now**, not the architecture it may grow into later.

## Design goals

### 1. Treat `/data` as persistent state

BDS itself is downloaded into `/data`, and the same directory also contains worlds and configuration. Container replacement must therefore avoid casually replacing valuable state.

When a BDS version is installed or upgraded, the entrypoint preserves:

- `worlds/`
- `server.properties`
- `allowlist.json`
- `permissions.json`

The installed BDS version is recorded in `/data/.bds-version` so an already-installed matching version can be reused.

### 2. Keep mutable server content outside the image

Behavior packs, resource packs, and an initial world archive can come from S3-compatible object storage instead of being baked into the OCI image.

This is useful when the image lifecycle and content lifecycle are different. Updating a pack should not inherently require rebuilding the server image.

S3 support in this repository is currently **delivery/bootstrap oriented**. It is not a world-backup system and does not continuously upload `/data` back to object storage.

### 3. Prefer Minecraft-aware shutdown

With RCON enabled, termination attempts `stop` through `mcrcon` first. If that path is unavailable or times out, the entrypoint falls back to Unix signals and eventually a forced kill.

This matters on Kubernetes because world saving has to complete inside the Pod termination grace period.

### 4. Run BDS without root by default

The image defines a `minecraft` user and group with UID/GID `1000` and runs as that user by default.

The image can also be started as root when an operator deliberately needs the entrypoint to repair `/data` ownership and then drop privileges with `gosu`, but root is not the normal runtime model.

### 5. Make startup failures visible

The entrypoint validates required state before launch, including:

- writable `/data`;
- `EULA=true`;
- numeric runtime UID/GID values;
- a non-empty RCON password when RCON is enabled;
- valid configured port numbers.

A bad deployment should fail visibly instead of starting a partially configured server.

## Why these technologies and design choices?

### OCI / Docker images

The image packages the Linux runtime, entrypoint, RCON client, S3 client, and required native libraries separately from the host OS. This gives Docker, containerd, CRI-O, and Kubernetes the same server runtime contract.

BDS itself is intentionally downloaded at runtime instead of being permanently embedded into the image. That keeps the container image release cycle separate from Mojang/Microsoft's BDS release cycle.

### Debian slim

Bedrock Dedicated Server is a native Linux binary with system-library requirements. Debian slim provides a small conventional userspace while still making required libraries and operational tools straightforward to install and inspect.

### Multi-stage builds

`mcrcon`, MinIO `mc`, and `gosu` are built in dedicated stages and only their resulting binaries are copied into the runtime image.

The Go compiler, C compiler, Git checkout directories, and other build dependencies therefore do not remain in the final runtime image.

### Bash entrypoint

The current lifecycle is mostly filesystem mutation, process orchestration, environment validation, downloads, and signal handling. Bash keeps that path directly inspectable and avoids introducing another resident controller process.

The trade-off is that a large shell entrypoint becomes harder to reason about as lifecycle rules grow. Minecartainer has already shown where stronger separation and regression coverage are useful; the Bedrock implementation will need similar refinement as its behavior expands.

### `tini`

`tini` is PID 1. It forwards signals and reaps child processes while the entrypoint owns the Bedrock-specific startup and shutdown behavior.

### RCON + `mcrcon`

Stopping a Minecraft server is an application-level operation, not just a process-level operation. RCON gives the container a way to request BDS shutdown before falling back to `TERM`/`KILL`.

### S3-compatible storage + MinIO `mc`

The S3 API provides a useful boundary between the runtime image and deployable server content. MinIO `mc` supports both MinIO and other S3-compatible endpoints and provides mirror/copy operations suitable for pack delivery and world bootstrap.

### `rsync` and staged pack activation

Behavior and resource packs are copied into staging directories and then moved into their active locations. This reduces the time where the active pack directory is only partially updated.

## Lifecycle

A normal container start follows this sequence:

```text
container start
  |
  v
preflight validation
  |
  v
optional ownership repair (only when started as root)
  |
  v
install phase
  |- prepare /data directories
  |- write eula.txt
  |- resolve/download BDS when required
  |- preserve worlds + key configuration on BDS replacement
  |- verify native library dependencies
  |- optionally import an initial world ZIP from S3
  |- optionally sync behavior packs from S3
  |- activate behavior packs
  |- optionally sync resource packs from S3
  |- activate resource packs
  `- apply server.properties overrides
  |
  v
runtime phase
  |- create /data/.ready
  |- wait READY_DELAY
  `- start bedrock_server
  |
  v
SIGTERM / SIGINT / SIGQUIT
  |- try RCON stop
  |- wait for clean exit
  |- TERM fallback
  `- KILL fallback
```

The install/runtime boundary is currently an internal entrypoint structure. Unlike Minecartainer, it is not yet exposed as a complete install-only workflow.

## Quick start with Docker Compose

Create `compose.yml`:

```yaml
services:
  bedrock:
    image: ghcr.io/alexandergg-0520/minecraft-bedrock-server:latest
    restart: unless-stopped

    ports:
      - "19132:19132/udp"

    volumes:
      - bedrock_data:/data

    environment:
      EULA: "true"
      RCON_PASSWORD: "replace-this-password"
      SERVER_NAME: "Bedrock Server"
      GAMEMODE: "survival"
      DIFFICULTY: "normal"

    stop_grace_period: 120s

volumes:
  bedrock_data:
```

Start it:

```bash
docker compose up -d
docker compose logs -f bedrock
```

The default RCON policy is enabled, so `RCON_PASSWORD` is required unless you explicitly set:

```yaml
ENABLE_RCON: "false"
```

Do not publish the RCON port unless you have a specific reason to expose it.

## Minimal `docker run`

```bash
docker run -d \
  --name minecraft-bedrock \
  -e EULA=true \
  -e RCON_PASSWORD='replace-this-password' \
  -p 19132:19132/udp \
  -v minecraft-bedrock-data:/data \
  ghcr.io/alexandergg-0520/minecraft-bedrock-server:latest
```

## Kubernetes usage

The main Kubernetes assumptions are:

- one active BDS process should own a world volume;
- `/data` should be persistent;
- the Pod should run as non-root under normal operation;
- updates should not briefly run two Pods against the same world;
- termination must allow enough time for RCON shutdown and world saving.

A minimal Deployment pattern looks like this:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minecraft-bedrock
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: minecraft-bedrock
  template:
    metadata:
      labels:
        app: minecraft-bedrock
    spec:
      terminationGracePeriodSeconds: 120
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: bedrock
          image: ghcr.io/alexandergg-0520/minecraft-bedrock-server:latest
          env:
            - name: EULA
              value: "true"
            - name: RCON_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: minecraft-bedrock-rcon
                  key: password
          ports:
            - name: bedrock
              containerPort: 19132
              protocol: UDP
          volumeMounts:
            - name: data
              mountPath: /data
          startupProbe:
            exec:
              command:
                - /usr/local/bin/docker-entrypoint.sh
                - healthcheck
            periodSeconds: 5
            failureThreshold: 60
          readinessProbe:
            exec:
              command:
                - /usr/local/bin/docker-entrypoint.sh
                - healthcheck
            periodSeconds: 10
          livenessProbe:
            exec:
              command:
                - /usr/local/bin/docker-entrypoint.sh
                - healthcheck
            periodSeconds: 30
            failureThreshold: 3
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: minecraft-bedrock
```

The PVC, Secret, and network Service are deployment-specific and are intentionally not invented by the image.

For stricter GitOps deployments, prefer an explicit BDS version and pin the container image by digest instead of letting both layers float independently.

## BDS version selection

Resolution priority is:

1. `BDS_DOWNLOAD_URL` when explicitly set;
2. `BDS_CHANNEL=stable` + `BDS_STABLE_VERSION`;
3. explicit `VERSION`;
4. `VERSION=latest`, resolved from the official Bedrock server download page.

### Latest

```yaml
VERSION: "latest"
```

This is the default. On startup the entrypoint resolves the current Linux BDS download URL. If `/data/.bds-version` already matches the resolved version, installation is skipped.

### Explicit version

```yaml
VERSION: "1.21.130.4"
```

Use an explicit version when you do not want an ordinary restart to move to a newly released BDS version.

### Stable channel

```yaml
BDS_CHANNEL: "stable"
BDS_STABLE_VERSION: "1.21.130.4"
```

The published `stable` image target also carries the repository-configured stable BDS version at image build time.

### Direct download override

```yaml
BDS_DOWNLOAD_URL: "https://example.invalid/bedrock-server.zip"
```

This has the highest priority and is intended for deliberate overrides. The operator is responsible for the trust and compatibility of the supplied artifact.

## Persistent data model

`/data` is the main persistent boundary.

Important paths include:

```text
/data/
├── bedrock_server
├── .bds-version
├── .ready
├── server.properties
├── allowlist.json
├── permissions.json
├── worlds/
├── behavior_packs/
├── resource_packs/
└── logs/
```

The current design deliberately keeps the BDS installation and mutable world/config state in the same persistent tree. This is simple and practical, but it is also one of the areas where the design is less strongly separated than Minecartainer.

Back up `/data` independently. S3 asset delivery in this image is not a substitute for a world backup policy.

## `server.properties` configuration

Supported environment-variable mappings are applied only when the variable is non-empty.

| Environment variable | `server.properties` key |
| --- | --- |
| `SERVER_NAME` | `server-name` |
| `GAMEMODE` | `gamemode` |
| `FORCE_GAMEMODE` | `force-gamemode` |
| `DIFFICULTY` | `difficulty` |
| `ALLOW_CHEATS` | `allow-cheats` |
| `MAX_PLAYERS` | `max-players` |
| `ONLINE_MODE` | `online-mode` |
| `ALLOW_LIST` | `allow-list` |
| `SERVER_PORT` | `server-port` |
| `SERVER_PORTV6` | `server-portv6` |
| `LEVEL_NAME` | `level-name` |
| `LEVEL_SEED` | `level-seed` |
| `LEVEL_TYPE` | `level-type` |
| `DEFAULT_PLAYER_PERMISSION_LEVEL` | `default-player-permission-level` |
| `TEXTUREPACK_REQUIRED` | `texturepack-required` |
| `VIEW_DISTANCE` | `view-distance` |
| `TICK_DISTANCE` | `tick-distance` |
| `MAX_THREADS` | `max-threads` |
| `PLAYER_IDLE_TIMEOUT` | `player-idle-timeout` |
| `CHAT_RESTRICTION` | `chat-restriction` |
| `ENABLE_LAN_VISIBILITY` | `enable-lan-visibility` |
| `SERVER_PUBLIC_IP` | `server-public-ip` |

For additional properties, use comma-separated `key=value` entries:

```yaml
BDS_PROPERTIES: "compression-threshold=1,client-side-chunk-generation-enabled=true"
```

Existing `server.properties` is preserved across BDS replacement and then updated by the configured environment overrides.

## RCON and graceful shutdown

RCON defaults to enabled.

| Variable | Default | Purpose |
| --- | ---: | --- |
| `ENABLE_RCON` | `true` | Enable BDS RCON and shutdown integration |
| `RCON_HOST` | `127.0.0.1` | Address used by the local `mcrcon` client |
| `RCON_PORT` | `19134` | RCON port |
| `RCON_PASSWORD` | required when enabled | RCON credential |
| `RCON_RETRIES` | `5` | Command retry count |
| `RCON_RETRY_DELAY` | `1` | Delay between retries in seconds |
| `RCON_TIMEOUT` | `5` | Per-attempt timeout in seconds |
| `SHUTDOWN_WAIT_TIMEOUT` | `60` | Wait after RCON stop |
| `SHUTDOWN_TERM_WAIT` | `10` | Wait after TERM fallback |

The shutdown command is protected by a lock so duplicate stop paths, such as an orchestrator hook plus a signal trap, do not intentionally issue the RCON stop sequence twice.

## Health check

The image defines a Docker `HEALTHCHECK` that runs:

```bash
/usr/local/bin/docker-entrypoint.sh healthcheck
```

It requires both:

- `/data/.ready` to exist; and
- the `bedrock_server` process to be running.

The same command can be reused for Kubernetes startup, readiness, and liveness probes, with startup timing configured by the deployment.

## S3-compatible asset delivery

Set the common credentials only when an S3-backed feature is used:

```yaml
S3_ENDPOINT: "https://minio.example.com"
S3_ACCESS_KEY: "..."
S3_SECRET_KEY: "..."
```

### Behavior packs

```yaml
BEHAVIORPACKS_ENABLED: "true"
BEHAVIORPACKS_S3_BUCKET: "minecraft"
BEHAVIORPACKS_S3_PREFIX: "behavior_packs/latest"
```

Relevant controls:

- `BEHAVIORPACKS_SYNC_ONCE`
- `BEHAVIORPACKS_REMOVE_EXTRA`
- `INPUT_BEHAVIORPACKS_DIR`

`BEHAVIORPACKS_REMOVE_EXTRA=true` makes the mirrored source authoritative for files in the input directory, so verify the bucket and prefix before using destructive mirror semantics.

### Resource packs

```yaml
RESOURCEPACKS_ENABLED: "true"
RESOURCEPACKS_S3_BUCKET: "minecraft"
RESOURCEPACKS_S3_PREFIX: "resource_packs/latest"
```

Relevant controls:

- `RESOURCEPACKS_SYNC_ONCE`
- `RESOURCEPACKS_REMOVE_EXTRA`
- `INPUT_RESOURCEPACKS_DIR`

### Initial world ZIP

```yaml
WORLD_S3_BUCKET: "minecraft"
WORLD_S3_KEY: "worlds/worlds.zip"
WORLD_INSTALL_ONCE: "true"
```

With `WORLD_INSTALL_ONCE=true`, world import is skipped once `/data/worlds` already contains a world. The archive may either contain a top-level `worlds/` directory or contain world directories at its root.

This is intended for **bootstrap/import**, not continuous synchronization.

## Runtime identity and volume permissions

Defaults:

```text
RUN_UID=1000
RUN_GID=1000
```

The final image itself uses UID/GID `1000` by default.

If you mount a host directory, make sure UID/GID `1000` can write it, or deliberately choose another ownership strategy.

`RUN_UID` / `RUN_GID` are mainly useful when the container is deliberately started as root so the entrypoint can repair `/data` ownership and then use `gosu` to drop privileges. Merely setting those variables does not magically change filesystem ownership when the container is already running as a non-root user.

`FIX_OWNERSHIP=false` disables the recursive ownership repair path when starting as root.

## Image tags

The publish workflow currently builds two targets for both `linux/amd64` and `linux/arm64`:

| Tag | Meaning |
| --- | --- |
| `latest` | `bedrock-latest` target; resolves latest BDS unless runtime configuration overrides it |
| `stable` | `bedrock-stable` target; carries the repository-configured `BDS_STABLE_VERSION` |

Both tags are published to GHCR and Docker Hub.

For production/GitOps use, a floating image tag is convenient for testing but a digest pin gives a clearer container-runtime boundary.

## CI and supply-chain metadata

The repository currently checks:

- Bash syntax;
- ShellCheck warnings;
- Docker builds for both `bedrock-latest` and `bedrock-stable` targets.

Published multi-architecture images also request SBOM and provenance metadata from Docker Buildx.

This is useful baseline coverage, but it should not be confused with Minecartainer's broader runtime behavior regression suite. Expanding Bedrock runtime smoke coverage is an obvious future hardening step.

## Current limitations / future design work

The largest remaining architectural work is not adding more environment variables. It is making lifecycle and persistent-state rules more explicit.

Likely areas to refine include:

- separating installation from runtime more strongly;
- introducing explicit managed-install state instead of relying mainly on `.bds-version` plus filesystem presence;
- making destructive asset synchronization ownership-aware;
- adding install-only/pre-warm workflows for Kubernetes;
- expanding runtime smoke tests around upgrades, shutdown, S3 imports, and persistent-volume mismatch cases;
- reducing the amount of policy concentrated in one shell entrypoint;
- documenting stronger invariants for what the image may and may not mutate inside `/data`.

The goal is not to copy Minecartainer mechanically. Bedrock has a different server distribution and configuration model. The useful target is to bring the same level of **predictability, explicit state ownership, and failure boundaries** to a design that fits BDS.

## License

This repository is licensed under the [MIT License](LICENSE).

Minecraft and Minecraft Bedrock Dedicated Server are products of Microsoft/Mojang. This project is an independent containerization project and is not affiliated with or endorsed by Microsoft or Mojang.
