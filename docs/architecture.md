# Architecture

This document describes the responsibility boundaries of the Bedrock server runtime.

The goal is not to reproduce Minecartainer file-for-file. The goal is to give Minecraft Bedrock Dedicated Server the same kind of explicit lifecycle boundaries so future features can be added without turning the entrypoint back into a monolith.

## Core rule

`entrypoint.sh` is a composition root, not the implementation of the server lifecycle.

It may:

- locate and source runtime modules;
- initialize configuration;
- install process signal handlers;
- dispatch command modes;
- invoke preflight and the top-level lifecycle.

It should not accumulate implementation details for BDS installation, S3 delivery, world mutation, property editing, RCON, or shutdown policy.

## Current modules

| Module | Responsibility |
| --- | --- |
| `logging.sh` | Structured runtime logging and fatal errors |
| `common.sh` | Small generic predicates and validation helpers |
| `config.sh` | Environment defaults and the `server.properties` mapping contract |
| `filesystem.sh` | `/data` preparation, EULA file, atomic directory activation, ownership repair |
| `preflight.sh` | Validate deployment configuration before lifecycle mutation/startup |
| `s3_client.sh` | Configure the S3-compatible MinIO client |
| `content_assets.sh` | Fetch and activate behavior/resource packs |
| `server_install.sh` | Resolve, download, install, and validate the BDS executable/runtime files |
| `server_properties.sh` | Apply supported environment overrides to `server.properties` |
| `world_install.sh` | Bootstrap worlds from an external archive |
| `rcon.sh` | Execute RCON commands and serialize the stop request |
| `shutdown.sh` | Bounded graceful termination and process-signal fallbacks |
| `runtime.sh` | Ready state, privilege drop, process launch, and health checks |
| `install_phase.sh` | Orchestrate installation responsibilities in their required order |
| `runtime_phase.sh` | Orchestrate install followed by runtime |
| `command_mode.sh` | CLI-style command dispatch without embedding feature implementations |

## Dependency direction

The intended dependency direction is:

```text
entrypoint.sh
  -> command / lifecycle orchestration
      -> feature modules
          -> common infrastructure helpers
```

Feature modules should not call the entrypoint. Infrastructure helpers should not know about lifecycle ordering.

For example:

- `install_phase.sh` knows that a world bootstrap happens after BDS installation;
- `world_install.sh` knows how to install a world, but not when startup should call it;
- `s3_client.sh` knows how to configure object-storage access, but not which assets should exist;
- `shutdown.sh` owns termination policy while `rcon.sh` only owns Minecraft-level control requests.

## Persistent-state boundary

`/data` is long-lived state and may survive many container or Pod replacements.

Future changes that can delete, replace, or reinterpret data under `/data` must therefore be designed as explicit state transitions. The module split is a prerequisite for that work; it is not itself sufficient protection.

The next state-safety layer should add managed installation metadata and ownership information so the runtime can distinguish:

- files managed by this image;
- operator-owned files;
- externally delivered assets;
- persistent world state;
- incompatible requested state that should fail rather than be guessed.

## Compatibility rule for this refactor

The initial modularization is intentionally behavior-preserving.

It does not add new lifecycle features. Existing environment variables, command modes, install order, default RCON policy, BDS version resolution, S3 bootstrap behavior, property overrides, health checks, and shutdown fallbacks remain the compatibility contract.

Feature work should be reviewed separately after the modular boundary is established.

## Target: Minecartainer-class operational capabilities

"Minecartainer-class" means comparable operational rigor, not identical Java Edition features.

Java-specific concepts such as JVM tuning, Java server types, Java mod loaders, or Java modpack providers do not belong in the Bedrock runtime merely for parity.

The Bedrock roadmap should instead converge on equivalent operational capabilities:

1. **Managed BDS installation state**
   - structured install marker instead of relying only on `.bds-version`;
   - requested/resolved version and artifact/source identity;
   - explicit mismatch detection and guarded force-reinstall behavior.

2. **First-class lifecycle modes**
   - install-only operation for PVC pre-warming and Kubernetes Jobs;
   - explicit install/runtime boundary exposed through command mode;
   - lifecycle hooks with bounded execution and strict/non-strict policy.

3. **Filesystem and archive safety**
   - safe path helpers for destructive operations;
   - archive path validation before world extraction;
   - transactional temporary-file handling and cleanup.

4. **Managed content ownership**
   - distinguish image-managed/external pack content from operator content;
   - make destructive `remove-extra` behavior ownership-aware rather than directory-authoritative by default;
   - support local immutable inputs and S3-compatible sources through one policy boundary.

5. **World lifecycle policy**
   - explicit install/import semantics;
   - guarded reset/replacement behavior;
   - source conflict detection and safer extraction/activation.

6. **Bedrock configuration/state management**
   - stronger `server.properties` bootstrap and override validation;
   - explicit allowlist/permissions management where useful;
   - Bedrock-native behavior/resource-pack deployment workflows.

7. **RCON and shutdown lifecycle**
   - validated shutdown budget;
   - startup/control command support where useful;
   - stronger Kubernetes preStop/termination contract tests.

8. **Regression and runtime verification**
   - unit-like shell smoke tests per module boundary;
   - container runtime smoke tests;
   - persistent-volume restart/reinstall tests;
   - Kubernetes examples and lifecycle regression coverage.

The order matters: state ownership and lifecycle contracts should be established before adding broad automation.
