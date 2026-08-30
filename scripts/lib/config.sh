# shellcheck shell=bash

declare -gA PROP_MAP=()

initialize_config() {
  : "${DATA_DIR:=/data}"

  if [[ -z "${RUN_UID:-}" ]]; then
    RUN_UID="$(printenv UID 2>/dev/null || true)"
    : "${RUN_UID:=1000}"
  fi
  if [[ -z "${RUN_GID:-}" ]]; then
    RUN_GID="$(printenv GID 2>/dev/null || true)"
    : "${RUN_GID:=1000}"
  fi

  : "${EULA:=}"

  : "${VERSION:=latest}"
  : "${BDS_DOWNLOAD_URL:=}"
  : "${BDS_CHANNEL:=latest}"
  : "${BDS_STABLE_VERSION:=}"

  : "${READY_DELAY:=5}"
  : "${FIX_OWNERSHIP:=true}"

  : "${ENABLE_RCON:=true}"
  : "${RCON_HOST:=127.0.0.1}"
  : "${RCON_PORT:=19134}"
  : "${RCON_PASSWORD:=}"

  : "${S3_ENDPOINT:=}"
  : "${S3_ACCESS_KEY:=}"
  : "${S3_SECRET_KEY:=}"

  : "${BEHAVIORPACKS_ENABLED:=true}"
  : "${BEHAVIORPACKS_S3_BUCKET:=}"
  : "${BEHAVIORPACKS_S3_PREFIX:=behavior_packs/latest}"
  : "${BEHAVIORPACKS_SYNC_ONCE:=true}"
  : "${BEHAVIORPACKS_REMOVE_EXTRA:=true}"
  : "${INPUT_BEHAVIORPACKS_DIR:=/behavior_packs}"

  : "${RESOURCEPACKS_ENABLED:=true}"
  : "${RESOURCEPACKS_S3_BUCKET:=}"
  : "${RESOURCEPACKS_S3_PREFIX:=resource_packs/latest}"
  : "${RESOURCEPACKS_SYNC_ONCE:=true}"
  : "${RESOURCEPACKS_REMOVE_EXTRA:=true}"
  : "${INPUT_RESOURCEPACKS_DIR:=/resource_packs}"

  : "${WORLD_S3_BUCKET:=}"
  : "${WORLD_S3_KEY:=}"
  : "${WORLD_INSTALL_ONCE:=true}"

  : "${BDS_PROPERTIES:=}"

  : "${RCON_RETRIES:=5}"
  : "${RCON_RETRY_DELAY:=1}"
  : "${RCON_TIMEOUT:=5}"
  : "${SHUTDOWN_WAIT_TIMEOUT:=60}"
  : "${SHUTDOWN_TERM_WAIT:=10}"
  : "${RCON_STOP_LOCK:=/tmp/.rcon-stop.lockdir}"

  RCON_STOP_IN_PROGRESS=0
  RCON_STOP_RESULT=1
  SERVER_PID=""

  PROP_MAP=(
    [SERVER_NAME]="server-name"
    [GAMEMODE]="gamemode"
    [FORCE_GAMEMODE]="force-gamemode"
    [DIFFICULTY]="difficulty"
    [ALLOW_CHEATS]="allow-cheats"
    [MAX_PLAYERS]="max-players"
    [ONLINE_MODE]="online-mode"
    [ALLOW_LIST]="allow-list"
    [SERVER_PORT]="server-port"
    [SERVER_PORTV6]="server-portv6"
    [LEVEL_NAME]="level-name"
    [LEVEL_SEED]="level-seed"
    [LEVEL_TYPE]="level-type"
    [DEFAULT_PLAYER_PERMISSION_LEVEL]="default-player-permission-level"
    [TEXTUREPACK_REQUIRED]="texturepack-required"
    [VIEW_DISTANCE]="view-distance"
    [TICK_DISTANCE]="tick-distance"
    [MAX_THREADS]="max-threads"
    [PLAYER_IDLE_TIMEOUT]="player-idle-timeout"
    [CHAT_RESTRICTION]="chat-restriction"
    [ENABLE_LAN_VISIBILITY]="enable-lan-visibility"
    [SERVER_PUBLIC_IP]="server-public-ip"
  )
}
