#!/usr/bin/env bash
# state.sh - state.json 操作関数
# エージェント自動化システム用

# 依存: utils.sh が先に読み込まれていること
# 依存: jq コマンド

# jq パス検証（インジェクション防止）
# 許可パターン: .foo, .foo_bar, .foo[0], .foo.bar[1].baz など
# Usage: _validate_jq_path <jq_path>
# Returns: 0 if valid, 1 if invalid
_validate_jq_path() {
  local jq_path="$1"

  # 空文字列は不正
  if [[ -z "$jq_path" ]]; then
    return 1
  fi

  # 許可されるパターン:
  # - 先頭は "." で始まる
  # - 識別子: [a-zA-Z_][a-zA-Z0-9_]*
  # - 配列インデックス: \[[0-9]+\]
  # - これらの組み合わせ
  local pattern='^(\.[a-zA-Z_][a-zA-Z0-9_]*|\[[0-9]+\])+$'
  if [[ "$jq_path" =~ $pattern ]]; then
    return 0
  else
    return 1
  fi
}

# グローバル変数
STATE_FILE=""
STATE_DIR=""
STATE_LOCK_FILE=""
STATE_LOCK_TIMEOUT="${STATE_LOCK_TIMEOUT:-30}"

# state.json スキーマバージョン
readonly STATE_SCHEMA_VERSION="1.0.0"

# ロック取得ヘルパー（内部用）
_state_lock() {
  if [[ -z "$STATE_LOCK_FILE" ]]; then
    return 0  # ロックファイルが設定されていない場合はスキップ
  fi
  lock_acquire "$STATE_LOCK_FILE" "$STATE_LOCK_TIMEOUT"
}

# ロック解放ヘルパー（内部用）
_state_unlock() {
  if [[ -z "$STATE_LOCK_FILE" ]]; then
    return 0
  fi
  lock_release "$STATE_LOCK_FILE"
}

# 新規 state.json 生成
# Usage: state_init <plan_path> <task_name> [output_dir]
state_init() {
  local plan_path="$1"
  local task_name="$2"
  local output_dir="${3:-}"

  ensure_cmd jq

  # 出力ディレクトリ決定
  if [[ -z "$output_dir" ]]; then
    # スクリプトの場所から .claude/tmp/<task_name> を計算
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    output_dir="$(dirname "$script_dir")/tmp/${task_name}"
  fi

  ensure_dir "$output_dir"

  STATE_DIR="$output_dir"
  STATE_FILE="${output_dir}/state.json"
  STATE_LOCK_FILE="${output_dir}/.state.lock"

  local task_id
  task_id=$(generate_uuid)
  local now
  now=$(get_timestamp)

  # 初期 state.json 生成（jqで安全にJSON生成）
  jq -n \
    --arg version "$STATE_SCHEMA_VERSION" \
    --arg task_id "$task_id" \
    --arg task_name "$task_name" \
    --arg plan_path "$plan_path" \
    --arg now "$now" \
    '{
      version: $version,
      task: {
        id: $task_id,
        name: $task_name,
        plan_path: $plan_path
      },
      status: "pending",
      phases: [],
      quality_gate: {
        level: null,
        status: "pending"
      },
      sessions: {
        coder_sessions: []
      },
      timeouts: {
        codex_secs: 7200,
        claude_secs: 1800
      },
      created_at: $now,
      updated_at: $now,
      error: null
    }' > "$STATE_FILE"

  log_info "State initialized: $STATE_FILE"
  echo "$STATE_FILE"
}

# state.json 読み込み
# Usage: state_load <state_file>
state_load() {
  local state_file="$1"

  ensure_cmd jq
  ensure_file "$state_file"

  STATE_FILE="$state_file"
  STATE_DIR="$(dirname "$state_file")"
  STATE_LOCK_FILE="${STATE_DIR}/.state.lock"

  # スキーマバージョンチェック
  local version
  version=$(jq -r '.version // "unknown"' "$STATE_FILE")

  if [[ "$version" != "$STATE_SCHEMA_VERSION" ]]; then
    log_warn "State schema version mismatch: $version (expected: $STATE_SCHEMA_VERSION)"
  fi

  log_debug "State loaded: $STATE_FILE"
  return 0
}

# state.json 保存（updated_at を更新）
state_save() {
  if [[ -z "$STATE_FILE" ]]; then
    die "State not initialized. Call state_init or state_load first."
  fi

  _state_lock || die "Failed to acquire state lock"
  # Note: bash 3.x互換のため trap RETURN ではなく明示的にunlock

  local now
  now=$(get_timestamp)

  # updated_at を更新
  local tmp_file
  tmp_file=$(create_temp_file "state")
  jq --arg ts "$now" '.updated_at = $ts' "$STATE_FILE" > "$tmp_file"
  if ! mv "$tmp_file" "$STATE_FILE"; then
    rm -f "$tmp_file"
    _state_unlock
    die "Failed to save state file"
  fi

  _state_unlock
  log_debug "State saved: $STATE_FILE"
}

# 値取得
# Usage: state_get <jq_path>
# Example: state_get '.status'
# Example: state_get '.phases[0].name'
state_get() {
  local jq_path="$1"

  if [[ -z "$STATE_FILE" ]]; then
    die "State not initialized."
  fi

  # セキュリティ: jq パス検証（state_set/state_append と同様）
  if ! _validate_jq_path "$jq_path"; then
    die "Invalid jq path: $jq_path (allowed: .identifier, [index], combinations)"
  fi

  jq -r "$jq_path // empty" "$STATE_FILE"
}

# 値設定
# Usage: state_set <jq_path> <value>
# Example: state_set '.status' '"running"'
# Example: state_set '.phases[0].iteration' '2'
state_set() {
  local jq_path="$1"
  local value="$2"

  if [[ -z "$STATE_FILE" ]]; then
    die "State not initialized."
  fi

  # jq パスインジェクション防止
  if ! _validate_jq_path "$jq_path"; then
    die "Invalid jq path: $jq_path (allowed: .identifier, [index], combinations)"
  fi

  _state_lock || die "Failed to acquire state lock"
  # Note: bash 3.x互換のため trap RETURN ではなく明示的にunlock

  local tmp_file
  tmp_file=$(create_temp_file "state")

  # 値が JSON として有効かチェック
  # セキュリティ: 常に --argjson/--arg を使用してインジェクションを防止
  local jq_exit=0
  if echo "$value" | jq -e . >/dev/null 2>&1; then
    # JSON値として設定（--argjson で安全に渡す）
    jq --argjson v "$value" "${jq_path} = \$v" "$STATE_FILE" > "$tmp_file" || jq_exit=$?
  else
    # 文字列として設定（--arg で安全に渡す）
    jq --arg v "$value" "${jq_path} = \$v" "$STATE_FILE" > "$tmp_file" || jq_exit=$?
  fi

  # jq 失敗時は一時ファイルを削除してエラー
  if [[ $jq_exit -ne 0 ]]; then
    rm -f "$tmp_file"
    _state_unlock
    die "Failed to update state: jq error at $jq_path"
  fi

  if ! mv "$tmp_file" "$STATE_FILE"; then
    rm -f "$tmp_file"
    _state_unlock
    die "Failed to update state file"
  fi
  _state_unlock
  log_debug "State set: $jq_path = $value"
}

# 配列に追加
# Usage: state_append <jq_array_path> <json_object>
# Example: state_append '.phases' '{"name":"test","status":"pending"}'
state_append() {
  local jq_path="$1"
  local json_obj="$2"

  if [[ -z "$STATE_FILE" ]]; then
    die "State not initialized."
  fi

  # jq パスインジェクション防止
  if ! _validate_jq_path "$jq_path"; then
    die "Invalid jq path: $jq_path (allowed: .identifier, [index], combinations)"
  fi

  # JSON妥当性チェック（インジェクション防止）
  if ! echo "$json_obj" | jq -e . >/dev/null 2>&1; then
    die "Invalid JSON object: $json_obj"
  fi

  _state_lock || die "Failed to acquire state lock"
  # Note: bash 3.x互換のため trap RETURN ではなく明示的にunlock

  local tmp_file
  tmp_file=$(create_temp_file "state")

  # --argjson で安全にJSONオブジェクトを渡す
  local jq_exit=0
  jq --argjson obj "$json_obj" "${jq_path} += [\$obj]" "$STATE_FILE" > "$tmp_file" || jq_exit=$?

  # jq 失敗時は一時ファイルを削除してエラー
  if [[ $jq_exit -ne 0 ]]; then
    rm -f "$tmp_file"
    _state_unlock
    die "Failed to append to state: jq error at $jq_path"
  fi

  if ! mv "$tmp_file" "$STATE_FILE"; then
    rm -f "$tmp_file"
    _state_unlock
    die "Failed to update state file"
  fi
  _state_unlock

  log_debug "State appended to $jq_path"
}

# フェーズのインデックスを取得
# Usage: state_find_phase <phase_name>
# Returns: index (0-based) or -1 if not found
state_find_phase() {
  local phase_name="$1"

  if [[ -z "$STATE_FILE" ]]; then
    die "State not initialized."
  fi

  local index
  index=$(jq --arg name "$phase_name" '
    .phases | to_entries | map(select(.value.name == $name)) | .[0].key // -1
  ' "$STATE_FILE")

  echo "$index"
}

# フェーズを追加または更新
# Usage: state_upsert_phase <phase_name> <max_iterations>
state_upsert_phase() {
  local phase_name="$1"
  local max_iterations="${2:-5}"

  local index
  index=$(state_find_phase "$phase_name")

  if [[ "$index" == "-1" ]]; then
    # 新規追加（jqで安全にJSON生成）
    local phase_obj
    phase_obj=$(jq -n \
      --arg name "$phase_name" \
      --argjson max_iter "$max_iterations" \
      '{
        name: $name,
        status: "pending",
        iteration: 0,
        max_iterations: $max_iter,
        coder: null,
        reviews: [],
        fixes: [],
        started_at: null,
        completed_at: null
      }')
    state_append '.phases' "$phase_obj"
    log_info "Phase added: $phase_name"
  else
    log_debug "Phase already exists: $phase_name (index: $index)"
  fi
}

# フェーズの状態を更新
# Usage: state_set_phase_status <phase_name> <status>
state_set_phase_status() {
  local phase_name="$1"
  local status="$2"

  local index
  index=$(state_find_phase "$phase_name")

  if [[ "$index" == "-1" ]]; then
    die "Phase not found: $phase_name"
  fi

  state_set ".phases[$index].status" "\"$status\""

  # started_at / completed_at を自動設定
  local now
  now=$(get_timestamp)

  case "$status" in
    running|review|fixing)
      local started_at
      started_at=$(state_get ".phases[$index].started_at")
      if [[ -z "$started_at" || "$started_at" == "null" ]]; then
        state_set ".phases[$index].started_at" "\"$now\""
      fi
      ;;
    completed|failed|timeout|escalated)  # escalated を追加
      state_set ".phases[$index].completed_at" "\"$now\""
      ;;
  esac
}

# セッション情報を記録
# Usage: state_record_session <session_id> <phase> <iteration> [parent_id]
state_record_session() {
  local session_id="$1"
  local phase="$2"
  local iteration="$3"
  local parent_id="${4:-}"
  local now
  now=$(get_timestamp)

  # jqで安全にJSON生成
  local session_obj
  if [[ -z "$parent_id" ]]; then
    session_obj=$(jq -n \
      --arg sid "$session_id" \
      --arg p "$phase" \
      --argjson iter "$iteration" \
      --arg ts "$now" \
      '{
        session_id: $sid,
        phase: $p,
        iteration: $iter,
        created_at: $ts
      }')
  else
    session_obj=$(jq -n \
      --arg sid "$session_id" \
      --arg p "$phase" \
      --argjson iter "$iteration" \
      --arg parent "$parent_id" \
      --arg ts "$now" \
      '{
        session_id: $sid,
        phase: $p,
        iteration: $iter,
        parent_session_id: $parent,
        created_at: $ts
      }')
  fi

  state_append '.sessions.coder_sessions' "$session_obj"
  log_debug "Session recorded: $session_id"
}

# 最後のセッションIDを取得
# Usage: state_get_last_session [phase]
state_get_last_session() {
  local phase="${1:-}"

  if [[ -z "$STATE_FILE" ]]; then
    die "State not initialized."
  fi

  if [[ -n "$phase" ]]; then
    jq -r --arg p "$phase" '
      .sessions.coder_sessions | map(select(.phase == $p)) | last | .session_id // empty
    ' "$STATE_FILE"
  else
    jq -r '.sessions.coder_sessions | last | .session_id // empty' "$STATE_FILE"
  fi
}

# エラー情報を記録
# Usage: state_set_error <code> <message> [phase]
state_set_error() {
  local code="$1"
  local message="$2"
  local phase="${3:-}"

  local now
  now=$(get_timestamp)

  # jqで安全にJSON生成
  local error_obj
  if [[ -n "$phase" ]]; then
    error_obj=$(jq -n \
      --arg c "$code" \
      --arg m "$message" \
      --arg p "$phase" \
      --arg ts "$now" \
      '{
        code: $c,
        message: $m,
        phase: $p,
        timestamp: $ts
      }')
  else
    error_obj=$(jq -n \
      --arg c "$code" \
      --arg m "$message" \
      --arg ts "$now" \
      '{
        code: $c,
        message: $m,
        timestamp: $ts
      }')
  fi

  state_set '.error' "$error_obj"
  log_error "Error recorded: [$code] $message"
}

# エラーをクリア
state_clear_error() {
  state_set '.error' 'null'
}

# 状態のサマリーを表示
state_show_summary() {
  if [[ -z "$STATE_FILE" ]]; then
    die "State not initialized."
  fi

  echo "=== State Summary ==="
  echo "File: $STATE_FILE"
  echo ""
  jq -r '
    "Task: \(.task.name) (\(.task.id))",
    "Status: \(.status)",
    "Created: \(.created_at)",
    "Updated: \(.updated_at)",
    "",
    "Phases:",
    (.phases[] | "  - \(.name): \(.status) (iteration: \(.iteration)/\(.max_iterations))"),
    "",
    "Quality Gate: \(.quality_gate.status) (level: \(.quality_gate.level // "not set"))",
    "",
    if .error then "Error: [\(.error.code)] \(.error.message)" else "" end
  ' "$STATE_FILE"
}

# stale state の検出（5分以上更新がない running 状態）
# Returns: 0 if stale, 1 if not stale
state_is_stale() {
  local threshold_secs="${1:-300}"  # デフォルト5分

  if [[ -z "$STATE_FILE" ]]; then
    return 1
  fi

  local status
  status=$(state_get '.status')

  if [[ "$status" != "running" ]]; then
    return 1
  fi

  local updated_at
  updated_at=$(state_get '.updated_at')
  local now
  now=$(get_timestamp)

  local age_secs
  age_secs=$(date_diff_secs "$updated_at" "$now") || return 1

  if [[ $age_secs -gt $threshold_secs ]]; then
    log_warn "State is stale: ${age_secs}s since last update"
    return 0
  fi

  return 1
}

# state をバックアップ
state_backup() {
  if [[ -z "$STATE_FILE" ]]; then
    die "State not initialized."
  fi

  local backup_file="${STATE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$STATE_FILE" "$backup_file"
  log_debug "State backed up: $backup_file"
  echo "$backup_file"
}

# =====================================================
# Reviewer Session ID Management (Reference Only)
# =====================================================
# NOTE: These functions store session IDs for logging/tracking purposes.
# `codex resume` requires full interactive TTY and cannot be used via orchestrator.
# The session IDs are retained for debugging and audit trail, not for session resumption.
# =====================================================

# レビュワーの最新 session_id を取得
# Usage: reviewer_get_session_id <phase> <reviewer_name>
# Returns: session_id (stdout), empty if not found
reviewer_get_session_id() {
  local phase="$1"
  local reviewer_name="$2"

  if [[ -z "$phase" || -z "$reviewer_name" ]]; then
    return 1
  fi

  if [[ -z "$STATE_FILE" ]]; then
    return 1
  fi

  # 最新のイテレーションから該当レビュワーの session_id を取得
  # jq クエリ説明:
  #   1. 指定フェーズを検索
  #   2. reviews配列の最後のエントリ（最新イテレーション）を取得
  #   3. reviewers配列から指定レビュワーを検索
  #   4. session_id を返す（存在しない場合は empty）
  local session_id
  session_id=$(jq -r --arg phase "$phase" --arg reviewer "$reviewer_name" '
    .phases[]
    | select(.name == $phase)
    | .reviews[-1].reviewers[]?
    | select(.name == $reviewer)
    | .session_id // empty
  ' "$STATE_FILE" 2>/dev/null)

  if [[ -n "$session_id" && "$session_id" != "null" ]]; then
    echo "$session_id"
    return 0
  fi

  return 1
}

# レビュワーの session_id を保存
# Usage: reviewer_set_session_id <phase> <iteration> <reviewer_name> <session_id>
# Note: 該当レビュワーエントリが存在しない場合は作成する
reviewer_set_session_id() {
  local phase="$1"
  local iteration="$2"
  local reviewer_name="$3"
  local session_id="$4"

  if [[ -z "$phase" || -z "$iteration" || -z "$reviewer_name" || -z "$session_id" ]]; then
    log_error "reviewer_set_session_id: all parameters are required"
    return 1
  fi

  if [[ -z "$STATE_FILE" ]]; then
    log_error "reviewer_set_session_id: State not initialized"
    return 1
  fi

  _state_lock || { log_error "Failed to acquire state lock"; return 1; }

  # jq でレビュワーエントリを更新（存在しなければ追加）
  # jq クエリ説明:
  #   1. 指定フェーズを探す
  #   2. reviews 配列がなければ初期化
  #   3. 該当イテレーションを探す（なければ作成）
  #   4. reviewers 配列内で該当レビュワーを探す
  #   5. 存在すれば session_id を更新、なければ新規追加
  local tmp_file
  tmp_file=$(create_temp_file "state_reviewer")

  jq --arg phase "$phase" \
     --argjson iter "$iteration" \
     --arg reviewer "$reviewer_name" \
     --arg sid "$session_id" '
    # フェーズを探す
    .phases |= map(
      if .name == $phase then
        # reviews 配列を確認
        .reviews |= (
          if . == null then [{"iteration": $iter, "reviewers": []}]
          else .
          end
        )
        # 該当イテレーションを探すか作成
        | .reviews |= (
          if any(.iteration == $iter) then
            map(
              if .iteration == $iter then
                .reviewers |= (
                  if . == null then [] else . end
                )
                | .reviewers |= (
                  if any(.name == $reviewer) then
                    map(if .name == $reviewer then .session_id = $sid else . end)
                  else
                    . + [{"name": $reviewer, "session_id": $sid}]
                  end
                )
              else .
              end
            )
          else
            . + [{"iteration": $iter, "reviewers": [{"name": $reviewer, "session_id": $sid}]}]
          end
        )
      else .
      end
    )
  ' "$STATE_FILE" > "$tmp_file"

  local jq_exit=$?
  if [[ $jq_exit -eq 0 && -s "$tmp_file" ]]; then
    mv "$tmp_file" "$STATE_FILE"
    _state_unlock
    state_save  # updated_at を更新
    log_debug "Reviewer session_id saved: $phase/$reviewer_name = $session_id"
    return 0
  else
    rm -f "$tmp_file"
    _state_unlock
    log_error "Failed to save reviewer session_id"
    return 1
  fi
}

# 全レビュワーの session_id をまとめて取得
# Usage: reviewer_get_all_session_ids <phase>
# Returns: JSON object {"safety": "uuid", "perf": "uuid", ...} (stdout)
reviewer_get_all_session_ids() {
  local phase="$1"

  if [[ -z "$phase" ]]; then
    echo "{}"
    return 1
  fi

  if [[ -z "$STATE_FILE" ]]; then
    echo "{}"
    return 1
  fi

  # jq クエリ説明:
  #   1. 指定フェーズを検索
  #   2. reviews配列の最後のエントリ（最新イテレーション）を取得
  #   3. reviewers配列から {name: session_id} のオブジェクトを生成
  #   4. 全てをマージして単一オブジェクトに
  jq -r --arg phase "$phase" '
    .phases[]
    | select(.name == $phase)
    | .reviews[-1].reviewers // []
    | map({(.name): .session_id})
    | add // {}
  ' "$STATE_FILE" 2>/dev/null || echo "{}"
}
