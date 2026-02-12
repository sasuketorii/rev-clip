#!/usr/bin/env bash
#
# codex-review-hook.sh - 変更ファイルキュー収集（レビューは実行しない）
#
# このフックは Claude Code の Edit/Write 操作後に実行され、
# 変更されたファイルをキューに蓄積します。
# 実際のレビューは auto_orchestrate.sh のフェーズ完了時に実行されます。
#
# Codex推奨設計:
#   - PostToolUse: キュー蓄積のみ（レビューしない）
#   - フェーズ完了時: git diff で一括レビュー
#
# 使用方法:
#   Claude Code の PostToolUse フックとして設定
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
QUEUE_FILE="${REPO_ROOT}/.claude/tmp/review_queue.json"
QUEUE_DIR="$(dirname "$QUEUE_FILE")"
QUEUE_LOCK="${REPO_ROOT}/.claude/tmp/review_queue.lock"

# ログ出力
log_hook() {
  echo "[review-hook] $*" >&2
}

# jq 依存チェック
check_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    log_hook "ERROR: jq is required but not installed. Please install jq (brew install jq / apt install jq)."
    exit 1
  fi
}

# ロック付きでコマンドを実行（mkdir ベースの簡易ロック）
# 注意: flock はシェル関数を実行できないため、mkdir ロックに統一
# Usage: with_lock <command> [args...]
with_lock() {
  mkdir -p "$QUEUE_DIR"

  # mkdir による簡易ロック（macOS/Linux両対応、auto_orchestrate.shと同じ方式）
  local lock_dir="${QUEUE_LOCK}.d"
  local max_attempts=50
  local attempt=0

  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
      log_hook "WARN: Could not acquire lock after ${max_attempts} attempts, proceeding anyway"
      break
    fi
    sleep 0.1
  done

  # コマンド実行
  "$@"

  # ロック解放
  rmdir "$lock_dir" 2>/dev/null || true
}

# キューファイル初期化
init_queue() {
  mkdir -p "$QUEUE_DIR"
  if [[ ! -f "$QUEUE_FILE" ]]; then
    echo '{"pending_review":false,"changed_files":[],"last_change":""}' > "$QUEUE_FILE"
  fi
}

# キューにファイルを追加（内部関数、ロックなし）
_add_to_queue_internal() {
  local file_path="$1"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local tmp_file
  tmp_file=$(mktemp)
  jq --arg fp "$file_path" --arg ts "$timestamp" '
    .pending_review = true |
    .last_change = $ts |
    if (.changed_files | index($fp)) then .
    else .changed_files += [$fp]
    end
  ' "$QUEUE_FILE" > "$tmp_file" && mv "$tmp_file" "$QUEUE_FILE"
}

# キューにファイルを追加（ロック付き）
add_to_queue() {
  local file_path="$1"
  with_lock _add_to_queue_internal "$file_path"
}

# メイン処理
main() {
  # jq 依存チェック（必須）
  check_jq

  # 引数からツール名とファイルパスを取得
  # フック入力形式: JSON via stdin
  local input
  input=$(cat)

  # ツール名を取得
  local tool_name
  tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)

  # Edit または Write 操作の場合のみ処理
  if [[ "$tool_name" != "Edit" && "$tool_name" != "Write" ]]; then
    exit 0
  fi

  # ファイルパスを取得
  local file_path
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

  if [[ -z "$file_path" ]]; then
    exit 0
  fi

  # 絶対パスをリポジトリ相対パスに正規化
  # git diff は相対パスでないと動作しないため
  if [[ "$file_path" == /* ]]; then
    # 絶対パスの場合、REPO_ROOTからの相対パスに変換
    if [[ "$file_path" == "$REPO_ROOT/"* ]]; then
      file_path="${file_path#$REPO_ROOT/}"
    else
      # リポジトリ外のファイルはスキップ
      log_hook "Skipping file outside repo: $file_path"
      exit 0
    fi
  fi

  # コードファイルのみキューに追加
  case "$file_path" in
    *.sh|*.py|*.js|*.ts|*.tsx|*.rs|*.go|*.java|*.rb|*.php|*.c|*.cpp|*.h|*.hpp)
      ;;
    *)
      # 非コードファイルはスキップ
      exit 0
      ;;
  esac

  # キュー初期化
  init_queue

  # キューに追加
  add_to_queue "$file_path"
  log_hook "Queued for review: $file_path"

  exit 0
}

main "$@"
