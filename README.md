# minecraft-bedrock-server

Kubernetes での運用を前提にした、Minecraft Bedrock Dedicated Server 向けのコンテナランタイムです。

## 今回の改善内容（修正 + 新機能）

### 修正した点

- **`UID` 環境変数の Bash 予約変数衝突を修正**
  - これまで `UID` は Bash の readonly 予約変数と衝突しやすく、意図したユーザー ID での実行が不安定でした。
  - 実行ユーザー指定を `RUN_UID` / `RUN_GID` に統一し、必要に応じて既存の `UID` / `GID` からフォールバックするようにしました。

- **`BDS_CHANNEL=stable` が実質未使用だった問題を修正**
  - Dockerfile の `bedrock-stable` ステージが持つ `BDS_CHANNEL` / `BDS_STABLE_VERSION` を `entrypoint.sh` が解釈するようにし、
    stable チャンネル利用時に固定バージョンを確実に取得できるようにしました。

### 追加した新機能

- **コンテナ HEALTHCHECK 対応**
  - `docker-entrypoint.sh healthcheck` サブコマンドを追加。
  - `.ready` ファイルの有無と `bedrock_server` プロセスを検査し、異常時は非 0 で終了します。
  - Dockerfile に `HEALTHCHECK` を追加し、オーケストレータでの死活監視を強化しました。

## 主な環境変数

### 必須

- `EULA=true`

### 実行ユーザー

- `RUN_UID` (default: 実行時のユーザー ID。Bash 環境では `$UID` に従います)
- `RUN_GID` (default: 実行時のグループ ID)

> 注意: `UID` は Bash の予約済み readonly 変数のため、環境変数 `UID` を指定しても互換フォールバックとしては利用されません。
> 実行ユーザー/グループを明示したい場合は、`RUN_UID` / `RUN_GID` を指定してください。

### Bedrock バージョン制御

- `VERSION` (default: `latest`)
  - `latest` の場合は公式配布ページから最新版 URL を解決
  - `1.21.130.4` のような固定値を指定可能
- `BDS_CHANNEL` (default: `latest`)
  - `stable` を使う場合は `BDS_STABLE_VERSION` を必ず指定
- `BDS_STABLE_VERSION`
- `BDS_DOWNLOAD_URL` (指定時は最優先)

## 使い方（例）

```bash
docker run --rm \
  -e EULA=true \
  -e RUN_UID=1000 \
  -e RUN_GID=1000 \
  -p 19132:19132/udp \
  -v "$(pwd)/data:/data" \
  <image>
```

stable チャンネルの例:

```bash
docker run --rm \
  -e EULA=true \
  -e BDS_CHANNEL=stable \
  -e BDS_STABLE_VERSION=1.21.130.4 \
  -v "$(pwd)/data:/data" \
  <image>
```
