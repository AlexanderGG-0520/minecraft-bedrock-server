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

It must not accumulate BDS installation, S3 delivery, world mutation, pack ownership, property editing, RCON, or shutdown policy.

## Module boundaries

| Module | Responsibility |
| --- | --- |
| `logging.sh` | Runtime logging and fatal errors |
| `common.sh` | Generic predicates and validation helpers |
| `config.sh` | Environment defaults and the `server.properties` mapping contract |
| `filesystem.sh` | Safe path operations, `/data` preparation, atomic directory transitions, ownership repair, privilege drop |
| `content_state.sh` | Ownership metadata and ownership-aware activation for externally supplied pack content |
| `preflight.sh` | Validate configuration before persistent-state mutation or runtime launch |
| `lifecycle.sh` | Bounded pre/post install and pre-runtime hooks |
| `s3_client.sh` | Configure S3-compatible MinIO `mc` access |
| `content_assets.sh` | Fetch behavior/resource packs and delegate activation to managed-content policy |
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

- `install_phase.sh` knows when BDS, worlds, packs, and properties are installed;
- `server_install.sh` knows how BDS managed state transitions work but not when runtime launches;
- `content_assets.sh` knows how pack inputs are obtained but not which operator-owned active entries may be deleted;
- `content_state.sh` owns that deletion/ownership policy;
- `shutdown.sh` owns termination policy while `rcon.sh` owns application-level control requests.

## Persistent-state model

`/data` is long-lived state and may survive many container or Pod replacements.

The runtime therefore distinguishes between different classes of state instead of treating `/data` as one mutable directory.

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
```

The active directories may contain both runtime-managed and operator-owned top-level entries.

`*_REMOVE_EXTRA=true` does not grant permission to delete arbitrary active content. It removes only stale entries previously recorded as managed by this runtime. Unowned operator entries remain outside that deletion set.

When `*_REMOVE_EXTRA=false`, previously managed entries that disappear from the current input remain active and remain recorded as managed, allowing a later explicit remove-extra transition to clean them up safely.

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
  -> post-install hooks
  -> pre-runtime hooks
  -> launch BDS
  -> optional RCON startup commands
  -> readiness
  -> graceful shutdown / signal fallback
```

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

Directory activation uses staging plus rename rather than mutating active directories file-by-file where possible.

World archives are validated before extraction for:

- ZIP integrity;
- absolute paths;
- `..` traversal;
- symbolic-link entries.

An empty pack input does not replace an existing active pack directory.

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

The container integration verifies install-only, managed install metadata, runtime readiness, healthcheck behavior, signal termination, and readiness cleanup without depending on Mojang's live BDS download service.

## Remaining Minecartainer-class work

The major architectural groundwork is now present. Remaining work is primarily Bedrock-specific capability expansion rather than another monolithic refactor.

Useful next areas include:

- explicit allowlist/permissions GitOps management with a clearly defined ownership policy;
- Bedrock-native world behavior/resource pack binding workflows;
- richer S3 source/cache ownership metadata and source-conflict diagnostics;
- persistent-volume upgrade/reinstall matrix tests across more managed-state transitions;
- Kubernetes examples for install-only Jobs, hooks, and guarded world replacement;
- additional shutdown/RCON integration cases using a controllable test server.

The standard remains the same: add automation only after its state ownership and destructive boundaries are explicit.
