# Minecraft Bedrock Server

![Status checks](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-bedrock-server/status-checks.yml?branch=main&label=status%20checks)
[![Docker Pulls](https://img.shields.io/docker/pulls/alecjp02/minecraft-bedrock-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-bedrock-server/)
[![Docker Stars](https://img.shields.io/docker/stars/alecjp02/minecraft-bedrock-server.svg)](https://hub.docker.com/r/alecjp02/minecraft-bedrock-server/)
[![GitHub Issues](https://img.shields.io/github/issues-raw/alexandergg-0520/minecraft-bedrock-server.svg)](https://github.com/alexandergg-0520/minecraft-bedrock-server/issues)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Falexandergg--0520%2Fminecraft--bedrock--server-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Kubernetes](https://img.shields.io/badge/kubernetes-oriented-blue)

A Kubernetes-oriented container image for **Minecraft Bedrock Dedicated Server (BDS)** built around persistent-state safety, explicit lifecycle phases, ownership-aware configuration, S3-compatible content delivery, non-root runtime, health checks, and RCON-aware shutdown.

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
- a BDS update must not casually overwrite worlds or operator configuration;
- incompatible persistent state should fail visibly rather than be guessed;
- behavior packs, resource packs, player access, and world bindings need explicit ownership boundaries;
- destructive synchronization must remove only state the runtime actually owns;
- installation should be invokable independently from runtime;
- Kubernetes termination should ask Minecraft to stop cleanly before falling back to process signals;
- normal runtime should not require root.

The image therefore focuses on **lifecycle, state ownership, orchestration, and failure boundaries** rather than broad one-click automation.

## Relationship to Minecartainer

[`Minecartainer`](https://github.com/AlexanderGG-0520/minecartainer) is the Java Edition project built around the same operational direction.

The Bedrock implementation does not copy Java-specific concepts such as JVM tuning, mod loaders, server JAR types, or modpack providers. It instead targets the same class of operational guarantees using Bedrock-native state.

The core lifecycle now has the same broad design characteristics:

- a thin composition-root entrypoint;
- explicit install and runtime phases;
- first-class install-only mode;
- managed server-install metadata;
- lifecycle hooks;
- safe filesystem helpers;
- ownership-aware pack activation;
- guarded world replacement;
- managed `allowlist.json` and player `permissions.json` reconciliation;
- managed behavior/resource pack binding to worlds;
- RCON startup/shutdown control;
- module-level smoke tests and real container lifecycle integration.

Remaining work is mostly deeper Bedrock-specific behavior and transition testing rather than another structural rewrite.

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
│   ├── player-access/
│   │   ├── allowlist.json
│   │   └── permissions.json
│   ├── world-packs/
│   │   └── <level-name>/
│   │       ├── behavior.json
│   │       └── resource.json
│   └── world-source.json
├── server.properties
├── allowlist.json
├── permissions.json
├── worlds/
├── behavior_packs/
├── resource_packs/
└── logs/
```

Managed metadata is operational state rather than secret material and is written as `0644` so operators and read-only diagnostics can inspect it without using the Minecraft runtime UID.

Back up `/data` independently. S3 delivery in this image is **not** a world backup system.

### Ownership before deletion

The central deletion rule is:

> `REMOVE_EXTRA=true` means "remove stale state previously recorded as runtime-managed", not "delete everything absent from desired state".

This rule is used for active pack directories, player access, and world pack bindings. Operator-owned state remains outside the runtime's deletion set unless it was explicitly adopted as managed state.

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
  |- prepare /data and eula.txt
  |- resolve/adopt/install managed BDS state
  |- verify native dependencies
  |- optionally import/replace a world archive
  |- obtain + activate behavior packs
  |- obtain + activate resource packs
  |- apply server.properties overrides
  |- reconcile managed allowlist/permissions
  `- reconcile managed world pack bindings
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
  |- remove readiness immediately
  |- try serialized RCON stop
  |- wait for clean exit
  |- TERM fallback
  `- KILL fallback
```

The install ordering is intentional. World pack binding happens after `server.properties` so it sees the final `level-name`, and after shared pack activation so it reads the active managed manifests.

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

## Managed BDS installation

`/data/.bds-install.json` is the primary managed-install marker. It records the installation mode, requested/resolved version, artifact identity, and download-source fingerprint. `.bds-version` remains for compatibility and legacy adoption.

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

Pinned version changes are treated as incompatible managed state. Intentional replacement requires:

```yaml
FORCE_REINSTALL: "true"
```

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

## Managed player access

Player access is optional. With no managed source configured, existing BDS files are preserved untouched by this feature.

### Allowlist

Desired allowlist entries can be supplied directly:

```yaml
BDS_ALLOWLIST_JSON: >-
  [
    {"name":"PlayerOne"},
    {"name":"PlayerTwo","ignoresPlayerLimit":true}
  ]
```

or from a mounted JSON file:

```yaml
BDS_ALLOWLIST_FILE: "/config/allowlist.json"
```

Set only one of `BDS_ALLOWLIST_JSON` and `BDS_ALLOWLIST_FILE`.

The desired format is an array of objects with:

- `name`: required Gamertag;
- `xuid`: optional non-empty string;
- `ignoresPlayerLimit`: optional boolean, default `false`.

Ownership identity is `name`. The desired object overlays the current BDS object with the same name. This is important because BDS may populate an `xuid`; if desired state omits `xuid`, the existing BDS-populated value is retained.

By default:

```yaml
BDS_ALLOWLIST_REMOVE_EXTRA: "false"
```

Existing unowned players are preserved. When `true`, only stale names previously recorded under `/data/.managed/player-access/allowlist.json` are removed.

If you use the allowlist, also configure the BDS `allow-list` property, for example:

```yaml
ALLOW_LIST: "true"
```

### Player permissions

Desired top-level `permissions.json` entries can be supplied directly:

```yaml
BDS_PERMISSIONS_JSON: >-
  [
    {"xuid":"2533274790000001","permission":"member"},
    {"xuid":"2533274790000002","permission":"operator"}
  ]
```

or from a mounted file:

```yaml
BDS_PERMISSIONS_FILE: "/config/permissions.json"
```

Set only one of `BDS_PERMISSIONS_JSON` and `BDS_PERMISSIONS_FILE`.

Managed desired permissions accept:

```text
visitor
member
operator
```

Ownership identity is `xuid`. Existing unowned entries are preserved by default.

```yaml
BDS_PERMISSIONS_REMOVE_EXTRA: "false"
```

When set to `true`, only stale XUIDs previously recorded under `/data/.managed/player-access/permissions.json` are removed.

This feature manages the BDS top-level player `permissions.json`; it is distinct from Script API module-permission configuration under BDS `config/` directories.

### Why merge instead of replace?

`allowlist.json` and player permissions are mutable BDS runtime state. BDS or an operator may legitimately add data between container starts. Treating a ConfigMap as an authoritative whole-file replacement would discard those changes and can accidentally remove access.

The image therefore reconciles only the entries it owns.

Changes are applied during the install phase before BDS launches. If files are modified externally while BDS is already running, use the appropriate BDS reload command or restart workflow; this image does not continuously rewrite player access while the server is running.

## Behavior and resource packs

Pack management has two separate responsibilities:

1. **delivery/activation** into shared `/data/behavior_packs` and `/data/resource_packs`;
2. optional **binding** of runtime-managed packs to one world.

Putting a pack in a shared pack directory does not by itself make this image silently attach every pack to every world.

### S3-compatible delivery

Common settings:

```yaml
S3_ENDPOINT: "https://minio.example.com"
S3_ACCESS_KEY: "..."
S3_SECRET_KEY: "..."
```

Behavior pack example:

```yaml
BEHAVIORPACKS_ENABLED: "true"
BEHAVIORPACKS_S3_BUCKET: "minecraft"
BEHAVIORPACKS_S3_PREFIX: "behavior_packs/latest"
BEHAVIORPACKS_SYNC_ONCE: "true"
BEHAVIORPACKS_REMOVE_EXTRA: "false"
```

Resource pack example:

```yaml
RESOURCEPACKS_ENABLED: "true"
RESOURCEPACKS_S3_BUCKET: "minecraft"
RESOURCEPACKS_S3_PREFIX: "resource_packs/latest"
RESOURCEPACKS_SYNC_ONCE: "true"
RESOURCEPACKS_REMOVE_EXTRA: "false"
```

Local or read-only mounted input may be supplied with:

```yaml
INPUT_BEHAVIORPACKS_DIR: "/behavior_packs"
INPUT_RESOURCEPACKS_DIR: "/resource_packs"
```

The runtime records the top-level pack entries it owns in:

```text
/data/.managed/content-assets/behavior_packs.json
/data/.managed/content-assets/resource_packs.json
```

With remove-extra disabled, new managed input is overlaid while existing active content is preserved. With remove-extra enabled, stale active entries are removed only when they were previously recorded as runtime-managed. Unowned operator entries are preserved.

When S3 mirroring itself uses `--remove`, the configured input directory is still the mirror destination. Do not point an authoritative mirror at an input directory containing unrelated files.

## Managed world pack binding

World pack binding is disabled by default:

```yaml
WORLD_PACKS_BINDING_ENABLED: "false"
```

Enable it when runtime-managed shared packs should be reconciled into one existing world:

```yaml
WORLD_PACKS_BINDING_ENABLED: "true"
LEVEL_NAME: "Bedrock level"
```

The target is resolved from the **final** `level-name` in `server.properties`. You may override only the binding target with:

```yaml
WORLD_PACKS_LEVEL_NAME: "Bedrock level"
```

The target directory must already exist:

```text
/data/worlds/<level-name>/
```

Binding intentionally does not manufacture an empty world directory. If the configured target does not exist, startup fails rather than creating ambiguous persistent state.

For each runtime-managed shared pack, the image reads `manifest.json` and uses:

```text
header.uuid    -> pack_id
header.version -> version
```

It reconciles entries into:

```text
/data/worlds/<level-name>/world_behavior_packs.json
/data/worlds/<level-name>/world_resource_packs.json
```

Only packs already present in the runtime's content-asset ownership metadata are candidates for automatic binding. Operator-installed shared packs are not implicitly adopted.

The default is non-destructive:

```yaml
WORLD_PACKS_REMOVE_EXTRA: "false"
```

Existing unowned bindings remain. If a managed pack keeps the same UUID but its manifest version changes, the binding version is updated.

With:

```yaml
WORLD_PACKS_REMOVE_EXTRA: "true"
```

only stale pack IDs previously recorded under `/data/.managed/world-packs/<level-name>/` are removed.

Startup fails on malformed manifests, duplicate managed pack UUIDs, unsafe world names, or malformed/duplicate current binding entries instead of guessing.

## Guarded world import/replacement

World S3 delivery is a bootstrap/import mechanism.

```yaml
WORLD_S3_BUCKET: "minecraft"
WORLD_S3_KEY: "worlds/worlds.zip"
WORLD_INSTALL_ONCE: "true"
WORLD_REPLACE: "false"
```

The archive may contain a top-level `worlds/` directory or world directories directly at archive root.

Existing worlds are preserved by default. Replacing an existing world requires both:

```yaml
WORLD_INSTALL_ONCE: "false"
WORLD_REPLACE: "true"
```

Archives are checked for ZIP integrity, absolute/traversal paths, and symbolic-link entries before extraction. A successful managed import records a source fingerprint and archive SHA-256 in `/data/.managed/world-source.json`.

S3 world import is not a backup scheduler. Backups/snapshots should be handled independently from the import path.

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

### GitOps player-access files

A ConfigMap can provide **desired entries** without becoming the authoritative owner of the BDS output file itself:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: minecraft-bedrock-access
data:
  allowlist.json: |-
    [
      {"name":"PlayerOne"},
      {"name":"PlayerTwo","ignoresPlayerLimit":true}
    ]
  permissions.json: |-
    [
      {"xuid":"2533274790000001","permission":"operator"}
    ]
```

Mount it read-only somewhere outside `/data`, then set:

```yaml
- name: BDS_ALLOWLIST_FILE
  value: /config/access/allowlist.json
- name: BDS_PERMISSIONS_FILE
  value: /config/access/permissions.json
```

The image merges those desired entries into the persistent BDS-owned files under `/data`.

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
- module loading and lifecycle ordering;
- `server.properties` behavior;
- managed BDS install mismatch/adoption rules;
- safe filesystem operations;
- lifecycle hooks;
- active pack ownership behavior;
- player-access merge/ownership behavior;
- world pack manifest/binding/remove-extra behavior;
- managed-metadata permissions;
- RCON startup behavior;
- world archive/path safety and world source metadata;
- Docker builds for both image targets;
- an actual container lifecycle integration using a local fake BDS ELF fixture.

The container integration exercises install-only, managed installation, root-to-non-root startup, player-access reconciliation, behavior/resource pack binding, readiness, healthcheck, graceful signal termination, and readiness cleanup without depending on the live BDS download service.

## Remaining design work

The monolithic lifecycle problem is gone, and the first major Bedrock-native state surfaces now have explicit ownership models. Remaining work should deepen those boundaries rather than bypass them.

Likely next areas:

- optional RCON-assisted live reload workflows for access changes made while BDS is already running;
- manifest dependency-graph and paired behavior/resource pack validation;
- richer new-world bootstrap workflows;
- stronger S3 source/cache conflict diagnostics;
- broader persistent-volume upgrade/reinstall/state-migration matrices;
- periodic integration against a real pinned BDS artifact in addition to the deterministic fake fixture;
- additional RCON/shutdown integration scenarios.

The rule for future features is simple: **define ownership and destructive transitions before adding automation**.

## License

This repository is licensed under the [MIT License](LICENSE).

Minecraft and Minecraft Bedrock Dedicated Server are products of Microsoft/Mojang. This project is independent and is not affiliated with or endorsed by Microsoft or Mojang.
