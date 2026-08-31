# Minecraft Bedrock Server

![Status checks](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-bedrock-server/status-checks.yml?branch=main&label=status%20checks)
[![Docker Pulls](https://img.shields.io/docker/pulls/alecjp02/minecraft-bedrock-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-bedrock-server/)
[![Docker Stars](https://img.shields.io/docker/stars/alecjp02/minecraft-bedrock-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-bedrock-server/)
[![GitHub Issues](https://img.shields.io/github/issues-raw/alexandergg-0520/minecraft-bedrock-server.svg)](https://github.com/alexandergg-0520/minecraft-bedrock-server/issues)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Falexandergg--0520%2Fminecraft--bedrock--server-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Kubernetes](https://img.shields.io/badge/kubernetes-oriented-blue)

A Kubernetes-oriented container image for **Minecraft Bedrock Dedicated Server (BDS)** built around persistent-state safety, explicit lifecycle phases, S3-compatible content delivery, non-root runtime, health checks, and RCON-aware control.

```bash
docker pull ghcr.io/alexandergg-0520/minecraft-bedrock-server:latest
```

Published as:

```text
ghcr.io/alexandergg-0520/minecraft-bedrock-server
alecjp02/minecraft-bedrock-server
```

## Why does this project exist?

There are already mature Bedrock server images, especially [`itzg/docker-minecraft-bedrock-server`](https://github.com/itzg/docker-minecraft-bedrock-server). This project is not trying to win by exposing the largest number of environment variables.

It exists for a specific operational model:

- Pods and containers are disposable;
- `/data` is long-lived state;
- a server update must not casually overwrite worlds or operator configuration;
- incompatible persistent state should fail visibly rather than be guessed;
- behavior packs, resource packs, and initial worlds can have a lifecycle independent from the OCI image;
- destructive synchronization must have an ownership boundary;
- installation should be invokable independently from runtime;
- Kubernetes termination should ask Minecraft to stop cleanly before falling back to process signals;
- normal runtime should not require root.

The image therefore focuses on **lifecycle, state ownership, orchestration, and failure boundaries** rather than broad one-click automation.

## Relationship to Minecartainer

[`Minecartainer`](https://github.com/AlexanderGG-0520/minecartainer) is the Java Edition project built around the same operational direction.

The Bedrock implementation does not copy Java-specific concepts such as JVM tuning, mod loaders, server JAR types, or modpack providers. It instead targets the same class of operational guarantees using Bedrock-native state.

The core lifecycle is now intentionally similar:

- a thin composition-root entrypoint;
- explicit install and runtime phases;
- first-class install-only mode;
- managed server-install metadata;
- lifecycle hooks;
- safe filesystem helpers;
- ownership-aware external content activation;
- guarded world replacement;
- RCON startup/shutdown control;
- module-level smoke tests and container lifecycle integration.

Remaining parity work is mostly **Bedrock-specific feature expansion**, such as explicit allowlist/permissions ownership and richer pack/world workflows, rather than another monolithic entrypoint rewrite.

See [`docs/architecture.md`](docs/architecture.md) for the responsibility and state model.

## Design model

### `/data` is state, not scratch space

The same PVC may survive many image upgrades and Pod replacements. The runtime therefore treats changes under `/data` as state transitions.

Important paths include:

```text
/data/
├── bedrock_server
├── .bds-install.json
├── .bds-version
├── .ready
├── .managed/
│   ├── content-assets/
│   │   ├── behavior_packs.json
│   │   └── resource_packs.json
│   └── world-source.json
├── server.properties
├── allowlist.json
├── permissions.json
├── worlds/
├── behavior_packs/
├── resource_packs/
└── logs/
```

Back up `/data` independently. S3 delivery in this image is **not** a world backup system.

### Managed BDS installation

`/data/.bds-install.json` is the primary managed-install marker. It records:

- installation mode;
- requested version;
- resolved version;
- artifact identity;
- source fingerprint.

`.bds-version` remains for compatibility and legacy adoption.

A pinned/custom installation is not silently replaced when requested state changes. An incompatible replacement requires:

```yaml
FORCE_REINSTALL: "true"
```

Use that only when replacement is intentional. Floating `latest` and `stable` modes may update within the same managed mode.

### Managed pack ownership

Behavior/resource pack activation tracks which **top-level active entries** were created or adopted by this runtime.

The default is:

```text
BEHAVIORPACKS_REMOVE_EXTRA=false
RESOURCEPACKS_REMOVE_EXTRA=false
```

With remove-extra disabled, new managed input is overlaid while existing active content is preserved.

With remove-extra enabled, stale entries are removed only when they were previously recorded as managed. Unowned operator entries are not deleted merely because they are absent from the current input.

This ownership rule applies to the active `/data/behavior_packs` and `/data/resource_packs` directories. When S3 mirroring itself uses `--remove`, the configured input directory is still treated as the mirror destination, so do not point an authoritative mirror at an input directory containing unrelated files.

### Guarded world replacement

World S3 delivery is a bootstrap/import mechanism.

Existing worlds are preserved by default:

```text
WORLD_INSTALL_ONCE=true
WORLD_REPLACE=false
```

Replacing an existing world requires both:

```yaml
WORLD_INSTALL_ONCE: "false"
WORLD_REPLACE: "true"
```

World archives are checked for ZIP integrity, absolute/traversal paths, and symbolic-link entries before extraction. A successful managed import records a source fingerprint and archive SHA-256 in `/data/.managed/world-source.json`.

## Why these technologies?

### OCI / Docker

The container packages the native runtime libraries, lifecycle implementation, RCON client, and S3 client into one reproducible runtime contract usable by Docker, containerd, CRI-O, and Kubernetes.

BDS itself is resolved at runtime so Mojang's BDS release lifecycle does not require rebuilding this image for every server release.

### Debian slim

BDS is a native Linux binary with ordinary shared-library requirements. Debian slim provides a small, inspectable runtime while keeping required native packages straightforward.

### Multi-stage builds

`mcrcon`, MinIO `mc`, and `gosu` are built in dedicated stages. Compilers and source trees do not remain in the final runtime image.

### Bash modules

The lifecycle is dominated by filesystem transitions, process management, downloads, environment validation, and signal handling. Bash keeps those operations directly inspectable.

The entrypoint itself is intentionally thin. Policy lives in modules under `scripts/lib/` so feature growth does not recreate the original monolith.

### `tini`

`tini` is PID 1, forwards signals, and reaps child processes. Bedrock-specific shutdown policy remains in the runtime modules.

### RCON + `mcrcon`

A Minecraft shutdown is an application-level operation. RCON is attempted before bounded process-signal fallbacks.

### S3-compatible storage + MinIO `mc`

The S3 API is the boundary between the server image and independently managed content such as packs and initial world archives.

### `rsync` + staged activation

Persistent directories are staged and switched rather than rewritten in place where practical. Managed content additionally carries an explicit ownership list so deletion policy is not equivalent to "delete everything missing from the source."

## Lifecycle

Normal startup:

```text
container start
  |
  v
preflight
  |
  v
optional /data ownership repair when started as root
  |
  v
drop privileges before lifecycle mutation/runtime
  |
  v
pre-install hooks
  |
  v
install phase
  |- prepare /data
  |- write eula.txt
  |- resolve/adopt/install managed BDS state
  |- verify native dependencies
  |- optionally import/replace a world archive
  |- obtain + activate behavior packs
  |- obtain + activate resource packs
  `- apply server.properties overrides
  |
  v
post-install hooks
  |
  v
pre-runtime hooks
  |
  v
launch bedrock_server
  |
  v
wait READY_DELAY and verify process still exists
  |
  v
optional RCON_CMDS_STARTUP
  |
  v
create /data/.ready
  |
  v
SIGTERM / SIGINT / SIGQUIT
  |- try serialized RCON stop
  |- wait for clean exit
  |- TERM fallback
  `- KILL fallback
```

Install-only stops after `post-install` hooks and exits successfully without creating runtime readiness state.

## Quick start with Docker Compose

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

```bash
docker compose up -d
docker compose logs -f bedrock
```

RCON defaults to enabled for normal runtime, so `RCON_PASSWORD` is required unless you explicitly set:

```yaml
ENABLE_RCON: "false"
```

Do not publish the RCON port unless you intentionally need remote RCON access.

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

## Command modes

The entrypoint supports lifecycle/control commands:

| Command | Purpose |
| --- | --- |
| `run` | Normal install-then-runtime lifecycle |
| `install-only` | Run installation lifecycle and exit without starting BDS |
| `rcon <command...>` | Execute one RCON command |
| `rcon-say <message...>` | Execute `say` through RCON |
| `rcon-stop` | Issue the serialized stop path; exits successfully for orchestrator compatibility |
| `healthcheck` | Validate readiness file + BDS process |

Example:

```bash
docker run --rm \
  -e EULA=true \
  -v minecraft-bedrock-data:/data \
  ghcr.io/alexandergg-0520/minecraft-bedrock-server:latest \
  install-only
```

Install-only does not require runtime-only RCON credentials.

## Kubernetes usage

The important assumptions are:

- one active BDS runtime should own a world volume;
- `/data` should be persistent;
- normal runtime should run as non-root;
- updates should not briefly run two BDS processes against the same world;
- termination must leave enough time for graceful shutdown.

A minimal Deployment pattern:

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
              command: ["/usr/local/bin/docker-entrypoint.sh", "healthcheck"]
            periodSeconds: 5
            failureThreshold: 60
          readinessProbe:
            exec:
              command: ["/usr/local/bin/docker-entrypoint.sh", "healthcheck"]
            periodSeconds: 10
          livenessProbe:
            exec:
              command: ["/usr/local/bin/docker-entrypoint.sh", "healthcheck"]
            periodSeconds: 30
            failureThreshold: 3
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: minecraft-bedrock
```

For GitOps/production, prefer an explicit BDS version when you need deterministic server upgrades and pin the container image by digest.

### Install-only Job

Install-only can pre-warm or validate a PVC without starting the BDS runtime:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: minecraft-bedrock-install
spec:
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: install
          image: ghcr.io/alexandergg-0520/minecraft-bedrock-server:latest
          args: ["install-only"]
          env:
            - name: EULA
              value: "true"
            - name: VERSION
              value: "1.21.130.4"
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: minecraft-bedrock
```

Do **not** run an install Job concurrently with an active server Pod writing the same PVC. Stop/scale down the runtime first and respect your storage access mode.

## BDS version selection

Resolution priority:

1. `BDS_DOWNLOAD_URL` when explicitly set;
2. `BDS_CHANNEL=stable` with `BDS_STABLE_VERSION`;
3. explicit `VERSION`;
4. `VERSION=latest`, resolved from the official Bedrock server download page.

### Latest

```yaml
VERSION: "latest"
```

`latest` is a managed floating mode. A newer resolved BDS version may replace the previous managed `latest` installation while preserving worlds and key configuration.

### Explicit version

```yaml
VERSION: "1.21.130.4"
```

Pinned version changes are treated as incompatible managed state and require `FORCE_REINSTALL=true`.

### Stable channel

```yaml
BDS_CHANNEL: "stable"
BDS_STABLE_VERSION: "1.21.130.4"
```

`stable` is also a managed floating mode within the same installation mode.

### Direct URL override

```yaml
BDS_DOWNLOAD_URL: "https://example.invalid/bedrock-server.zip"
```

A direct URL has highest priority. Its URL is fingerprinted for state comparison; the raw URL is not stored in the managed install marker.

## `server.properties` configuration

Non-empty environment values are mapped to existing/new properties.

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

Additional properties can be supplied as comma-separated `key=value` entries:

```yaml
BDS_PROPERTIES: "compression-threshold=1,client-side-chunk-generation-enabled=true"
```

Existing `server.properties` is preserved across BDS replacement and then updated by configured overrides.

## Lifecycle hooks

Hooks are disabled by default.

```yaml
HOOKS_ENABLED: "true"
HOOKS_DIR: "/hooks"
HOOKS_STRICT: "true"
HOOKS_TIMEOUT_SEC: "30"
```

Executable files are run from:

```text
/hooks/pre-install.d/
/hooks/post-install.d/
/hooks/pre-runtime.d/
```

Each hook receives:

```text
HOOK_PHASE=<phase-name>
```

`HOOKS_STRICT=true` makes a hook failure fatal. `HOOKS_TIMEOUT_SEC=0` disables the timeout.

Hooks run after the optional root ownership-repair path has dropped privileges, so lifecycle extensions do not silently regain root.

## RCON and graceful shutdown

RCON defaults to enabled for normal runtime.

| Variable | Default | Purpose |
| --- | ---: | --- |
| `ENABLE_RCON` | `true` | Enable RCON lifecycle integration |
| `RCON_HOST` | `127.0.0.1` | Local client target |
| `RCON_PORT` | `19134` | RCON port |
| `RCON_PASSWORD` | required at runtime when enabled | RCON credential |
| `RCON_CMDS_STARTUP` | empty | Newline-separated commands run before readiness |
| `RCON_RETRIES` | `5` | Positive command attempt budget |
| `RCON_RETRY_DELAY` | `1` | Delay between attempts |
| `RCON_TIMEOUT` | `5` | Positive per-attempt timeout |
| `SHUTDOWN_WAIT_TIMEOUT` | `60` | Positive clean-exit wait budget after RCON stop |
| `SHUTDOWN_TERM_WAIT` | `10` | TERM fallback wait budget |

Startup command example:

```yaml
RCON_CMDS_STARTUP: |-
  say Server startup checks complete
  gamerule showcoordinates true
```

If a configured startup command fails, the server is stopped and readiness is never published.

The RCON stop path is protected by an ephemeral lock outside `/data` so duplicate preStop/signal paths do not intentionally execute stop twice.

## Health check

The image defines:

```bash
/usr/local/bin/docker-entrypoint.sh healthcheck
```

Health requires:

- `/data/.ready` exists; and
- the `bedrock_server` process is running.

The readiness file is created only after the process survives `READY_DELAY` and startup RCON commands succeed. It is removed when the server exits or shutdown begins.

## S3-compatible delivery

Common settings:

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
BEHAVIORPACKS_SYNC_ONCE: "true"
BEHAVIORPACKS_REMOVE_EXTRA: "false"
```

Local/immutable input can also be supplied with `INPUT_BEHAVIORPACKS_DIR`.

### Resource packs

```yaml
RESOURCEPACKS_ENABLED: "true"
RESOURCEPACKS_S3_BUCKET: "minecraft"
RESOURCEPACKS_S3_PREFIX: "resource_packs/latest"
RESOURCEPACKS_SYNC_ONCE: "true"
RESOURCEPACKS_REMOVE_EXTRA: "false"
```

Local/immutable input can also be supplied with `INPUT_RESOURCEPACKS_DIR`.

### World archive

```yaml
WORLD_S3_BUCKET: "minecraft"
WORLD_S3_KEY: "worlds/worlds.zip"
WORLD_INSTALL_ONCE: "true"
WORLD_REPLACE: "false"
```

The archive may contain a top-level `worlds/` directory or world directories directly at archive root.

## Runtime identity and permissions

Defaults:

```text
RUN_UID=1000
RUN_GID=1000
```

The final image runs as UID/GID `1000` by default.

When deliberately started as root, `FIX_OWNERSHIP=true` allows `/data` ownership repair and the entrypoint then drops privileges with `gosu` **before** the install/runtime lifecycle executes.

```yaml
FIX_OWNERSHIP: "false"
```

disables recursive ownership repair.

## Image tags

The publish workflow builds both `linux/amd64` and `linux/arm64` targets:

| Tag | Meaning |
| --- | --- |
| `latest` | `bedrock-latest`; managed latest BDS resolution unless overridden |
| `stable` | `bedrock-stable`; carries the configured stable BDS version |

Both are published to GHCR and Docker Hub.

For production/GitOps, prefer digest-pinned container images.

## CI and regression coverage

The required `Status checks` workflow validates:

- Bash syntax across entrypoint, modules, and tests;
- composed ShellCheck;
- module loading;
- lifecycle ordering;
- `server.properties` behavior;
- install-state mismatch/adoption rules;
- safe filesystem operations;
- lifecycle hooks;
- pack ownership behavior;
- RCON startup behavior;
- world archive/path safety;
- world source metadata;
- Docker builds for both targets;
- an actual container lifecycle integration using a local fake BDS ELF fixture.

The container integration exercises install-only, managed installation, readiness, healthcheck, graceful signal termination, and readiness cleanup without depending on the live BDS download service.

## Remaining design work

The large monolithic-lifecycle problem has been removed. The next work should be Bedrock-specific capability growth on top of the state boundaries above.

Likely areas:

- explicit GitOps ownership for `allowlist.json` and `permissions.json`;
- Bedrock-native behavior/resource pack binding to individual worlds;
- richer S3 source/cache conflict diagnostics;
- broader persistent-volume upgrade/reinstall matrices;
- more Kubernetes lifecycle examples;
- additional RCON/shutdown integration scenarios.

The rule for future features is simple: **define ownership and destructive transitions before adding automation**.

## License

This repository is licensed under the [MIT License](LICENSE).

Minecraft and Minecraft Bedrock Dedicated Server are products of Microsoft/Mojang. This project is independent and is not affiliated with or endorsed by Microsoft or Mojang.
