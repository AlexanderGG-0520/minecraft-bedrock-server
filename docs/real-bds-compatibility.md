# Real Bedrock Dedicated Server compatibility

The required pull-request checks intentionally use deterministic fake BDS artifacts. They prove the container lifecycle and persistent-state machine without depending on Mojang availability.

That is not enough to prove compatibility with the current official Bedrock Dedicated Server binary.

Stage 5 therefore adds a separate real-BDS compatibility layer:

```text
required PR checks
  -> deterministic lifecycle/state correctness

real-bds-compatibility.yml
  -> current Mojang distribution + binary compatibility
```

The two layers have different failure domains and must remain separate.

## Triggers and manual runs

`.github/workflows/real-bds-compatibility.yml` runs:

- after runtime-affecting changes are pushed to `main`;
- on Monday and Thursday as a periodic upstream compatibility check;
- manually through `workflow_dispatch`.

The `main` push trigger is path-scoped to the Docker/runtime implementation and the compatibility harness itself. It gives a newly merged runtime change an immediate real-BDS result without making the external check a prerequisite for merging that pull request.

Automatic runs test:

```text
VERSION=latest
```

A manual run may provide an explicit BDS version. This is useful when reproducing a compatibility regression against a version that is no longer the latest release.

The workflow is deliberately not a required pull-request status check. Mojang download availability, CDN incidents, website changes, or transient internet failures must not make unrelated repository changes unmergeable.

A failed compatibility run is still actionable: determine whether the failure is an upstream availability problem, a resolver incompatibility, a native-library incompatibility, or a lifecycle regression.

## What the real-BDS harness proves

`test/real-bds-compatibility.sh` builds on a Docker named volume and performs these transitions:

```text
empty Docker volume
  -> install official BDS
  -> validate managed install metadata
  -> launch real BDS
  -> create/open a real world
  -> bind the configured UDP port
  -> satisfy the image healthcheck
  -> docker stop
  -> remove readiness
  -> reopen the same persistent world
  -> satisfy runtime/health again
  -> docker stop
```

The test verifies:

- the official artifact can be resolved and downloaded;
- `bedrock_server` is executable and its native dependencies are available in the image;
- `.bds-install.json` and `.bds-version` agree with the resolved artifact;
- the real BDS process stays alive through readiness;
- a real world directory is generated and `level.dat` survives shutdown;
- BDS binds the configured Bedrock UDP port;
- the image-level Docker healthcheck becomes healthy;
- `docker stop` completes with container exit code `0`;
- `/data/.ready` is removed after shutdown;
- the same persistent Docker volume can be opened by a second real-BDS runtime cycle.

The harness uses a named volume rather than a host bind mount. Host-runner UID differences are not part of this compatibility question and must not create false failures.

## RCON boundary

The real-BDS compatibility workflow sets:

```text
ENABLE_RCON=false
```

This is intentional. The purpose of this layer is to detect compatibility between the container lifecycle and the upstream BDS binary/distribution.

RCON startup commands, RCON stop behavior, and fallback shutdown semantics have their own deterministic test boundary. A failure in optional control-plane behavior should not be confused with an upstream BDS binary failing to start.

## Official download URL identity

Mojang has changed the official Linux BDS distribution host over time.

The current canonical version URL is treated as:

```text
https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-<version>.zip
```

The latest-version page parser also accepts the legacy AzureEdge URL format as a fallback.

For managed installation identity:

- `custom-url` remains source-strict: changing the URL fingerprint is an incompatible source transition;
- `latest`, `stable`, and explicit official `version` modes are identified by mode/requested/resolved artifact version rather than a particular Mojang CDN hostname;
- when the official URL changes but the resolved artifact version does not, the runtime refreshes `source_fingerprint` metadata without reinstalling the payload.

This distinction prevents a Mojang CDN migration from forcing operators to set `FORCE_REINSTALL=true` for an otherwise unchanged official BDS installation.

## Failure triage

When a real compatibility run fails, classify the earliest failing boundary:

1. **official page resolution** — the download-page structure or URL format changed;
2. **artifact download** — upstream/CDN/network failure or retired explicit version;
3. **install/native dependency check** — archive layout or Linux ABI requirements changed;
4. **runtime process exit** — BDS no longer starts with the current image/runtime configuration;
5. **world/UDP readiness** — the process exists but does not reach usable server state;
6. **Docker healthcheck** — the runtime contract and actual process state disagree;
7. **shutdown/restart** — termination or persistent world reopen behavior changed.

Do not weaken the deterministic required tests to make an upstream compatibility failure disappear. Fix the appropriate compatibility boundary, then keep the reproduction case when practical.
