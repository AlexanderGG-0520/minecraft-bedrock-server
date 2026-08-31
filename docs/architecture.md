# Architecture

This document defines the responsibility and state-ownership boundaries of the Minecraft Bedrock server runtime.

The goal is not to reproduce Minecartainer file-for-file. The goal is to give Bedrock Dedicated Server the same class of lifecycle rigor: disposable compute, long-lived state, explicit ownership, guarded destructive transitions, and regression-tested orchestration.

## Core rule

`entrypoint.sh` is a composition root, not the implementation of the server lifecycle.

It may:

- locate and source runtime modules;
- initialize configuration;
- install signal handlers;
- dispatch command modes;
- invoke preflight and the top-level lifecycle.

It must not accumulate BDS installation, S3 delivery, world mutation, pack ownership, player-access policy, property editing, RCON, or shutdown policy.

## Module boundaries

| Module | Responsibility |
| --- | --- |
| `logging.sh` | Runtime logging and fatal errors |
| `common.sh` | Generic predicates and validation helpers |
| `config.sh` | Environment defaults and the `server.properties` mapping contract |
| `filesystem.sh` | Safe path operations, `/data` preparation, atomic directory transitions, ownership repair, privilege drop |
| `content_state.sh` | Ownership metadata and ownership-aware activation for externally supplied pack content |
| `player_access.sh` | Declarative merge and ownership policy for `allowlist.json` and top-level player `permissions.json` |
| `preflight.sh` | Validate configuration before persistent-state mutation or runtime launch |
| `lifecycle.sh` | Bounded pre/post install and pre-runtime hooks |
| `s3_client.sh` | Configure S3-compatible MinIO `mc` access |
| `content_assets.sh` | Fetch behavior/resource packs and delegate activation to managed-content policy |
| `world_pack_binding.sh` | Resolve managed pack manifests and ownership-aware world behavior/resource pack bindings |
| `server_install.sh` | Resolve, download, install, adopt, and validate managed BDS installation state |
| `server_properties.sh` | Apply supported environment overrides to `server.properties` |
| `world_install.sh` | Validate, fingerprint, and atomically bootstrap/replace worlds from an external archive |
| `rcon.sh` | Execute RCON commands, startup commands, and serialize stop requests |
| `shutdown.sh` | Bounded graceful termination and signal fallbacks |
| `runtime.sh` | Server process launch, readiness state, runtime health, and process waiting |
| `install_phase.sh` | Orchestrate installation responsibilities in required order |
| `runtime_phase.sh` | Orchestrate install-only or install-then-runtime behavior |
| `command_mode.sh` | CLI-style command dispatch |

## Dependency direction

The intended direction is:

```text
entrypoint.sh
  -> command / lifecycle orchestration
      -> feature modules
          -> common infrastructure helpers
```

Feature modules do not call the entrypoint. Infrastructure helpers do not decide lifecycle order.

For example:

- `install_phase.sh` knows when BDS, worlds, packs, properties, player access, and world bindings are reconciled;
- `server_install.sh` knows how BDS managed state transitions work but not when runtime launches;
- `content_assets.sh` knows how pack inputs are obtained but not which operator-owned active entries may be deleted;
- `content_state.sh` owns that active-pack deletion/ownership policy;
- `world_pack_binding.sh` consumes content ownership metadata and pack manifests but does not fetch or activate shared packs;
- `player_access.sh` owns reconciliation of BDS player-access files but not `server.properties` or runtime reload commands;
- `shutdown.sh` owns termination policy while `rcon.sh` owns application-level control requests.

A feature module should not depend on an unrelated feature module merely for utility code. Shared mechanics belong in infrastructure helpers or remain local to the feature when they are feature-specific.

## Persistent-state model

`/data` is long-lived state and may survive many container or Pod replacements.

The runtime therefore distinguishes between different classes of state instead of treating `/data` as one mutable directory.

Managed metadata under `/data/.managed` is operational state, not secret material. Runtime-generated JSON markers are created as `0644` so operators, diagnostics, and read-only sidecars can inspect them without requiring the Minecraft runtime UID.

### Managed BDS installation

The primary marker is:

```text
/data/.bds-install.json
```

It records:

- marker schema version;
- managed artifact identity;
- installation mode (`latest`, `stable`, explicit version, or custom URL);
- requested version;
- resolved version;
- download-source fingerprint.

`.bds-version` is retained for compatibility and legacy-state adoption, but it is no longer the sole source of truth.

Pinned/custom managed state is not silently replaced when the requested state changes. `FORCE_REINSTALL=true` is required for an intentional incompatible replacement. Floating `latest` and `stable` channels may update within the same managed mode.

### Managed pack ownership

Behavior/resource pack ownership is recorded below:

```text
/data/.managed/content-assets/
├── behavior_packs.json
└── resource_packs.json
```

The active directories may contain both runtime-managed and operator-owned top-level entries.

`*_REMOVE_EXTRA=true` does not grant permission to delete arbitrary active content. It removes only stale entries previously recorded as managed by this runtime. Unowned operator entries remain outside that deletion set.

When `*_REMOVE_EXTRA=false`, previously managed entries that disappear from the current input remain active and remain recorded as managed, allowing a later explicit remove-extra transition to clean them up safely.

### Managed player access

Player-access ownership is recorded below:

```text
/data/.managed/player-access/
├── allowlist.json
└── permissions.json
```

The runtime reconciles desired entries into BDS-owned mutable files instead of replacing those files wholesale.

For `allowlist.json`:

- ownership identity is the player `name`;
- a desired entry overlays the current entry with the same name;
- an existing `xuid` survives when desired state omits it, allowing BDS-populated XUIDs to remain intact;
- unowned current entries are preserved;
- `BDS_ALLOWLIST_REMOVE_EXTRA=true` removes only stale names previously recorded as runtime-managed.

For top-level player `permissions.json`:

- ownership identity is `xuid`;
- desired `visitor`, `member`, or `operator` state overlays the same XUID;
- unowned current entries are preserved;
- `BDS_PERMISSIONS_REMOVE_EXTRA=true` removes only stale XUIDs previously recorded as runtime-managed.

This is deliberately not an authoritative whole-file ConfigMap copy. BDS and operators may legitimately mutate these files between container starts.

### Managed world-pack bindings

Per-world binding ownership is recorded below:

```text
/data/.managed/world-packs/<level-name>/
├── behavior.json
└── resource.json
```

When `WORLD_PACKS_BINDING_ENABLED=true`, the runtime binds only shared packs already listed in its content-asset ownership metadata. Arbitrary operator-installed packs in `/data/behavior_packs` or `/data/resource_packs` are therefore not adopted implicitly.

For each runtime-managed pack, `world_pack_binding.sh` reads the pack header UUID and version from `manifest.json` and reconciles the corresponding entry into:

```text
/data/worlds/<level-name>/world_behavior_packs.json
/data/worlds/<level-name>/world_resource_packs.json
```

The target world is `WORLD_PACKS_LEVEL_NAME` when explicitly set, otherwise the final `level-name` from `server.properties` after environment overrides have been applied.

The world directory must already exist. Binding never creates an empty world directory merely to satisfy configuration.

Existing unowned bindings are preserved. `WORLD_PACKS_REMOVE_EXTRA=true` removes only stale pack IDs previously recorded as runtime-managed. A changed manifest version updates the managed binding for the same pack UUID.

Malformed manifests, duplicate managed pack UUIDs, unsafe world names, malformed current binding files, and duplicate current binding IDs are fail-fast conditions.

### Managed world source

When a world archive is installed from S3-compatible storage, the runtime records:

```text
/data/.managed/world-source.json
```

The marker contains a source fingerprint and the installed archive SHA-256.

With `WORLD_INSTALL_ONCE=true`, existing worlds are preserved even if the configured source later changes; a source drift warning is emitted when the existing world has managed source metadata.

Replacing an existing world requires both:

```text
WORLD_INSTALL_ONCE=false
WORLD_REPLACE=true
```

This makes replacement an explicit destructive transition rather than an accidental consequence of changing one bootstrap flag.

## Lifecycle

Normal runtime:

```text
preflight
  -> optional ownership repair
  -> privilege drop
  -> pre-install hooks
  -> install phase
       -> managed BDS install/adoption
       -> optional world bootstrap/replacement
       -> shared behavior/resource pack activation
       -> server.properties reconciliation
       -> player-access reconciliation
       -> world pack-binding reconciliation
  -> post-install hooks
  -> pre-runtime hooks
  -> launch BDS
  -> optional RCON startup commands
  -> readiness
  -> graceful shutdown / signal fallback
```

The ordering inside the install phase is part of the contract. World-pack binding must happen after `server.properties` so it sees the final `level-name`, and after shared pack activation so it reads the active managed manifests.

Install-only runtime:

```text
preflight
  -> optional ownership repair
  -> privilege drop
  -> pre-install hooks
  -> install phase
  -> post-install hooks
  -> exit 0
```

Runtime-only requirements such as an RCON credential are not required by install-only mode.

Hooks execute from:

```text
/hooks/pre-install.d/
/hooks/post-install.d/
/hooks/pre-runtime.d/
```

when `HOOKS_ENABLED=true`. Hook failures are fatal by default and may be bounded with `HOOKS_TIMEOUT_SEC`.

## Filesystem safety rules

Destructive helpers reject empty/root filesystem paths.

Directory activation uses staging plus rename rather than mutating active directories file-by-file where practical. Managed JSON state uses temporary files plus activation/rollback semantics rather than partially rewriting active files.

World archives are validated before extraction for:

- ZIP integrity;
- absolute paths;
- `..` traversal;
- symbolic-link entries.

An empty pack input does not replace an existing active pack directory.

Ownership-aware remove-extra flags never mean "delete everything not present in desired state." They mean "delete stale state previously recorded as owned by this runtime."

## Readiness and shutdown

Readiness is runtime state, not install state.

`/data/.ready` is created only after:

- the BDS process has remained alive through `READY_DELAY`; and
- configured `RCON_CMDS_STARTUP` commands have completed successfully.

The readiness file is removed when the process exits or shutdown begins.

Shutdown attempts application-level RCON stop first when enabled, then uses bounded process-signal fallbacks. Duplicate RCON stop paths are serialized with an ephemeral lock outside the PVC.

## Regression boundary

The required status workflow covers four layers:

1. Bash syntax and ShellCheck;
2. module-level lifecycle/state smoke tests;
3. Docker builds for latest and stable targets;
4. an actual container lifecycle integration using a local fake BDS ELF fixture.

The container integration verifies install-only, managed install metadata, Bedrock player-access reconciliation, shared-pack-to-world binding, runtime readiness, healthcheck behavior, signal termination, and readiness cleanup without depending on Mojang's live BDS download service.

## Remaining Minecartainer-class work

The major lifecycle architecture and the first Bedrock-native managed-state features are now present. Remaining work is narrower capability expansion and deeper transition testing rather than another structural rewrite.

Useful next areas include:

- optional live RCON reload workflows for player-access changes applied while a server is already running;
- validation of manifest dependency graphs and paired behavior/resource pack relationships;
- richer new-world bootstrap workflows without violating the rule that binding must not manufacture a fake world directory;
- stronger S3 source/cache ownership metadata and source-conflict diagnostics;
- persistent-volume upgrade/reinstall matrices across BDS versions and managed-state migrations;
- periodic integration against a real pinned BDS artifact in addition to the deterministic fake-BDS CI fixture;
- additional shutdown/RCON integration cases using a controllable test server.

The standard remains the same: add automation only after its state ownership and destructive boundaries are explicit.
