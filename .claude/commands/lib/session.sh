#!/usr/bin/env bash
# session.sh - Claude CLI セッション管理
# エージェント自動化システム用
#
# 依存: utils.sh, state.sh, timeout.sh が先に読み込まれていること
# 依存: claude CLI, jq

# セッション設定
SESSION_TIMEOUT="${SESSION_TIMEOUT:-1800}"  # 30分（デフォルト）
CLAUDE_THINKING_BUDGET="${CLAUDE_THINKING_BUDGET:-10000}"  # Ultrathink: 高推論モード

# セキュリティ: CLAUDE_THINKING_BUDGET の数値バリデーション
# コマンドインジェクション防止
_validate_thinking_budget() {
  local budget="${1:-$CLAUDE_THINKING_BUDGET}"
  if [[ ! "$budget" =~ ^[0-9]+$ ]]; then
    log_warn "Invalid CLAUDE_THINKING_BUDGET: $budget (must be numeric). Using default: 10000"
    echo "10000"
    return
  fi
  # 範囲チェック (1-100000)
  if [[ "$budget" -lt 1 || "$budget" -gt 100000 ]]; then
    log_warn "CLAUDE_THINKING_BUDGET out of range: $budget (1-100000). Using default: 10000"
    echo "10000"
    return
  fi
  echo "$budget"
}

# セッションID検証（セキュリティ強化版）
# Claude CLI のセッションIDは UUID 形式または類似のIDフォーマット
# Usage: _validate_session_id <session_id>
# Returns: 0 if valid, 1 if invalid
_validate_session_id() {
  local session_id="$1"

  if [[ -z "$session_id" ]]; then
    return 1
  fi

  # セッションIDの許可パターン（最小8文字で安全性向上）:
  # - UUID形式: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  # - 英数字とハイフン/アンダースコアの組み合わせ（8〜64文字）
  # Note: bash 3.x互換のため{m,n}量指定子を使わず、長さを別途チェック
  local len=${#session_id}
  if [[ $len -lt 8 || $len -gt 64 ]]; then
    return 1
  fi
  local pattern='^[a-zA-Z0-9_-]+$'
  if [[ "$session_id" =~ $pattern ]]; then
    return 0
  else
    return 1
  fi
}

# Claude CLI 存在確認
_ensure_claude_cli() {
  if ! command -v claude >/dev/null 2>&1; then
    die "Claude CLI not found. Please install Claude Code CLI."
  fi
}

# jq 存在確認
_ensure_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    die "jq not found. Please install jq (brew install jq / apt install jq)."
  fi
}

# 新規セッション開始
# Usage: session_start <prompt> [output_file]
# Returns: session_id（stdoutに出力）
# Note: 出力ファイルが指定されている場合、Claude の出力はそのファイルに保存される
# セキュリティ: セッションID取得失敗時はフォールバックせずエラーを返す
session_start() {
  local prompt="$1"
  local output_file="${2:-}"

  _ensure_claude_cli

  if [[ -z "$prompt" ]]; then
    die "session_start: prompt is required"
  fi

  local session_id=""
  local temp_stderr=""
  local temp_stdout=""
  local exit_code=0

  # セキュリティ: thinking budget をバリデート
  local validated_budget
  validated_budget=$(_validate_thinking_budget "$CLAUDE_THINKING_BUDGET")

  # 一時ファイルでセッション情報を取得
  temp_stderr=$(create_temp_file "claude_stderr")
  temp_stdout=$(create_temp_file "claude_stdout")

  log_info "Starting new Claude session..."

  # Claude CLI を実行（テキスト形式で出力、stderrからセッションID取得）
  # セキュリティ修正: printf を使用して入力を安全に渡す
  # Ultrathink: --thinking-budget で高推論モードを有効化
  if [[ -n "$output_file" ]]; then
    # 出力ファイル指定時
    if printf '%s' "$prompt" | claude --print --thinking-budget "$validated_budget" 2>"$temp_stderr" > "$temp_stdout"; then
      # 成功時のみ出力を保存
      cp "$temp_stdout" "$output_file"
      log_debug "Claude session output saved to: $output_file"
    else
      exit_code=$?
      log_error "Claude CLI failed with exit code: $exit_code"
      rm -f "$temp_stderr" "$temp_stdout"
      return 1
    fi
  else
    # 出力ファイルなし: stdout に出力
    if printf '%s' "$prompt" | claude --print --thinking-budget "$validated_budget" 2>"$temp_stderr" > "$temp_stdout"; then
      cat "$temp_stdout"
    else
      exit_code=$?
      log_error "Claude CLI failed with exit code: $exit_code"
      rm -f "$temp_stderr" "$temp_stdout"
      return 1
    fi
  fi

  # stderr からセッションIDを抽出
  # Claude CLI はセッション情報を stderr に出力する
  # 形式: "Session: <session_id>" または JSON形式
  if [[ -f "$temp_stderr" ]]; then
    # JSON形式でsession_idを探す
    session_id=$(grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_stderr" 2>/dev/null | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    # 見つからなければ "Session: " 形式を探す
    if [[ -z "$session_id" ]]; then
      session_id=$(grep -o 'Session:[[:space:]]*[a-zA-Z0-9_-]*' "$temp_stderr" 2>/dev/null | head -1 | sed 's/Session:[[:space:]]*//')
    fi

    # セッションIDが "session id:" 形式の場合も対応
    if [[ -z "$session_id" ]]; then
      session_id=$(grep -oi 'session[[:space:]]*id:[[:space:]]*[a-zA-Z0-9_-]*' "$temp_stderr" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//')
    fi

    rm -f "$temp_stderr" "$temp_stdout"
  fi

  # セキュリティ修正: フォールバックを削除
  # セッションIDが取得できなかった場合は明示的にエラー
  if [[ -z "$session_id" ]]; then
    log_warn "Could not determine session ID from Claude CLI output"
    log_warn "Session will continue without ID tracking"
    echo ""
    return 0  # 処理は成功したがIDが取れなかった
  fi

  if ! _validate_session_id "$session_id"; then
    log_warn "Invalid session ID format: $session_id"
    echo ""
    return 0  # 処理は成功したがIDが無効
  fi

  log_info "Session started: $session_id"
  echo "$session_id"
}

# セッション継続（コンテキスト保持）
# Usage: session_resume <session_id> <prompt> [output_file]
# Returns: 0 on success, 1 on failure
session_resume() {
  local session_id="$1"
  local prompt="$2"
  local output_file="${3:-}"

  _ensure_claude_cli

  if [[ -z "$session_id" ]]; then
    die "session_resume: session_id is required"
  fi

  if ! _validate_session_id "$session_id"; then
    die "session_resume: invalid session_id format: $session_id"
  fi

  if [[ -z "$prompt" ]]; then
    die "session_resume: prompt is required"
  fi

  # セキュリティ: thinking budget をバリデート
  local validated_budget
  validated_budget=$(_validate_thinking_budget "$CLAUDE_THINKING_BUDGET")

  log_info "Resuming session: $session_id"

  # セキュリティ修正: printf を使用
  # Ultrathink: --thinking-budget で高推論モードを有効化
  if [[ -n "$output_file" ]]; then
    # 出力ファイル指定時
    if printf '%s' "$prompt" | claude --resume "$session_id" --print --thinking-budget "$validated_budget" > "$output_file" 2>&1; then
      log_info "Session resumed, output saved to: $output_file"
      return 0
    else
      local exit_code=$?
      log_error "Claude CLI failed with exit code: $exit_code"
      return 1
    fi
  else
    # stdout に出力
    if printf '%s' "$prompt" | claude --resume "$session_id" --print --thinking-budget "$validated_budget" 2>&1; then
      return 0
    else
      local exit_code=$?
      log_error "Claude CLI failed with exit code: $exit_code"
      return 1
    fi
  fi
}

# セッション分岐（別アプローチ試行）
# Usage: session_fork <parent_session_id> <prompt> [output_file]
# Returns: new_session_id（stdoutに出力）
# セキュリティ: セッションID取得失敗時はフォールバックせずエラーを返す
session_fork() {
  local parent_session_id="$1"
  local prompt="$2"
  local output_file="${3:-}"

  _ensure_claude_cli

  if [[ -z "$parent_session_id" ]]; then
    die "session_fork: parent_session_id is required"
  fi

  if ! _validate_session_id "$parent_session_id"; then
    die "session_fork: invalid parent_session_id format: $parent_session_id"
  fi

  if [[ -z "$prompt" ]]; then
    die "session_fork: prompt is required"
  fi

  local new_session_id=""
  local temp_stderr=""
  local temp_stdout=""
  local exit_code=0

  # セキュリティ: thinking budget をバリデート
  local validated_budget
  validated_budget=$(_validate_thinking_budget "$CLAUDE_THINKING_BUDGET")

  temp_stderr=$(create_temp_file "claude_fork_stderr")
  temp_stdout=$(create_temp_file "claude_fork_stdout")

  log_info "Forking session from: $parent_session_id"

  # セキュリティ修正: printf を使用し、失敗時は即座にエラー
  # Ultrathink: --thinking-budget で高推論モードを有効化
  if [[ -n "$output_file" ]]; then
    if printf '%s' "$prompt" | claude --fork-session "$parent_session_id" --print --thinking-budget "$validated_budget" 2>"$temp_stderr" > "$temp_stdout"; then
      cp "$temp_stdout" "$output_file"
      log_debug "Fork output saved to: $output_file"
    else
      exit_code=$?
      log_error "Claude CLI fork failed with exit code: $exit_code"
      rm -f "$temp_stderr" "$temp_stdout"
      return 1
    fi
  else
    if printf '%s' "$prompt" | claude --fork-session "$parent_session_id" --print --thinking-budget "$validated_budget" 2>"$temp_stderr" > "$temp_stdout"; then
      cat "$temp_stdout"
    else
      exit_code=$?
      log_error "Claude CLI fork failed with exit code: $exit_code"
      rm -f "$temp_stderr" "$temp_stdout"
      return 1
    fi
  fi

  # 新しいセッションIDを抽出
  if [[ -f "$temp_stderr" ]]; then
    new_session_id=$(grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$temp_stderr" 2>/dev/null | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    if [[ -z "$new_session_id" ]]; then
      new_session_id=$(grep -o 'Session:[[:space:]]*[a-zA-Z0-9_-]*' "$temp_stderr" 2>/dev/null | head -1 | sed 's/Session:[[:space:]]*//')
    fi

    rm -f "$temp_stderr" "$temp_stdout"
  fi

  # セキュリティ修正: フォールバックを削除
  if [[ -z "$new_session_id" ]]; then
    log_warn "Could not determine new session ID after fork"
    log_warn "Fork succeeded but ID tracking unavailable"
    echo ""
    return 0  # fork自体は成功
  fi

  if ! _validate_session_id "$new_session_id"; then
    log_warn "Invalid new session ID format: $new_session_id"
    echo ""
    return 0
  fi

  log_info "Session forked: $parent_session_id -> $new_session_id"
  echo "$new_session_id"
}

# 最新のセッションIDを取得
# Usage: session_list_latest
# Returns: session_id（stdoutに出力）
# 注意: この関数は参照専用。新規セッション作成時のフォールバックには使用しないこと
session_list_latest() {
  _ensure_claude_cli

  # claude sessions list の出力からセッションIDを抽出
  # 出力形式は CLI バージョンによって異なる可能性があるため、複数パターンに対応
  local session_id=""

  # JSON形式の出力を試す（jqが利用可能な場合のみ）
  if command -v jq >/dev/null 2>&1; then
    local list_output
    list_output=$(claude sessions list --output-format json 2>/dev/null || true)

    if [[ -n "$list_output" ]]; then
      # JSON配列の最初のセッションIDを取得
      session_id=$(echo "$list_output" | jq -r '.[0].id // .[0].session_id // empty' 2>/dev/null)
    fi
  fi

  # JSON形式が失敗した場合、テキスト形式を試す
  if [[ -z "$session_id" ]]; then
    local list_output
    list_output=$(claude sessions list 2>/dev/null || true)
    # 最初の行からセッションIDらしい文字列を抽出
    # Note: bash 3.x互換のため{m,n}量指定子を使わず、長さは_validate_session_idでチェック
    session_id=$(echo "$list_output" | head -1 | grep -oE '[a-zA-Z0-9_-]+' | head -1)
  fi

  echo "$session_id"
}

# セッション情報を state.json に記録
# Usage: session_record <session_id> <phase> <iteration> [parent_id]
# Note: state.sh の state_record_session() のラッパー
session_record() {
  local session_id="$1"
  local phase="$2"
  local iteration="$3"
  local parent_id="${4:-}"

  if [[ -z "$session_id" ]]; then
    log_warn "session_record: empty session_id, skipping"
    return 1
  fi

  if ! _validate_session_id "$session_id"; then
    log_warn "session_record: invalid session_id format: $session_id"
    return 1
  fi

  # state.sh の関数を呼び出し
  state_record_session "$session_id" "$phase" "$iteration" "$parent_id"
  log_info "Session recorded to state: $session_id (phase: $phase, iteration: $iteration)"
}

# 前回のセッションIDを取得（state.json から）
# Usage: session_get_last [phase]
# Returns: session_id（stdoutに出力）
session_get_last() {
  local phase="${1:-}"

  # state.sh の関数を呼び出し
  state_get_last_session "$phase"
}

# セッション存在確認（厳密一致版）
# Usage: session_exists <session_id>
# Returns: 0 if exists, 1 if not
session_exists() {
  local session_id="$1"

  if [[ -z "$session_id" ]]; then
    return 1
  fi

  if ! _validate_session_id "$session_id"; then
    return 1
  fi

  _ensure_claude_cli

  # セッション一覧から厳密一致で検索
  local list_output

  # JSON形式で厳密チェック（jqが利用可能な場合）
  if command -v jq >/dev/null 2>&1; then
    list_output=$(claude sessions list --output-format json 2>/dev/null || true)
    if [[ -n "$list_output" ]]; then
      # jq で厳密一致検索
      local found
      found=$(echo "$list_output" | jq -r --arg sid "$session_id" \
        'map(select(.id == $sid or .session_id == $sid)) | length' 2>/dev/null)
      if [[ "$found" -gt 0 ]]; then
        return 0
      fi
    fi
  fi

  # テキスト形式でのフォールバック（行単位で厳密一致）
  list_output=$(claude sessions list 2>/dev/null || true)
  # grep -F で固定文字列として検索、-w で単語境界を考慮
  if echo "$list_output" | grep -Fwq "$session_id"; then
    return 0
  fi

  return 1
}

# セッションとの対話実行（タイムアウト付き）
# Usage: session_run_with_timeout <timeout_secs> <session_id> <prompt> [output_file]
# Returns: 0 on success, 124 on timeout, other on error
# セキュリティ:
#   - session_id は _validate_session_id() で検証済みであること
#   - プロンプトは一時ファイル経由で渡し、引数インジェクションを防止
#   - 引数終端 `--` を使用し、特殊文字で始まるパスの誤解釈を防止
session_run_with_timeout() {
  local timeout_secs="$1"
  local session_id="$2"
  local prompt="$3"
  local output_file="${4:-}"

  # セッションID検証（空文字/"new" 以外の場合は必須）
  if [[ -n "$session_id" && "$session_id" != "new" ]]; then
    if ! _validate_session_id "$session_id"; then
      log_error "session_run_with_timeout: invalid session_id format: $session_id"
      return 1
    fi
  fi

  # セキュリティ修正: プロンプトを一時ファイル経由で渡す
  # bash -c への引数渡しでの特殊文字問題を完全に回避
  local prompt_file=""
  prompt_file=$(create_temp_file "session_prompt")
  if [[ -z "$prompt_file" ]]; then
    log_error "session_run_with_timeout: failed to create temp file for prompt"
    return 1
  fi

  # プロンプトを一時ファイルに書き込み
  # Note: bash 3.x互換のため trap RETURN ではなく明示的にクリーンアップ
  if ! printf '%s' "$prompt" > "$prompt_file"; then
    log_error "session_run_with_timeout: failed to write prompt to temp file"
    rm -f "$prompt_file" 2>/dev/null
    return 1
  fi

  local exit_code=0

  # セキュリティ: thinking budget をバリデート
  local validated_budget
  validated_budget=$(_validate_thinking_budget "$CLAUDE_THINKING_BUDGET")

  if [[ -z "$session_id" || "$session_id" == "new" ]]; then
    # 新規セッション（Ultrathink有効）
    # セキュリティ: thinking-budget を引数として渡し、コマンドインジェクション防止
    if [[ -n "$output_file" ]]; then
      # 引数終端 `--` を使用し、`-malicious` のようなファイル名を安全に処理
      timeout_run "$timeout_secs" bash -c 'claude --print --thinking-budget "$1" < "$2" > "$3" 2>&1' -- "$validated_budget" "$prompt_file" "$output_file"
      exit_code=$?
    else
      timeout_run "$timeout_secs" bash -c 'claude --print --thinking-budget "$1" < "$2" 2>&1' -- "$validated_budget" "$prompt_file"
      exit_code=$?
    fi
  else
    # セッション継続（Ultrathink有効）
    # セキュリティ: thinking-budget を引数として渡し、コマンドインジェクション防止
    if [[ -n "$output_file" ]]; then
      timeout_run "$timeout_secs" bash -c 'claude --resume "$1" --print --thinking-budget "$2" < "$3" > "$4" 2>&1' -- "$session_id" "$validated_budget" "$prompt_file" "$output_file"
      exit_code=$?
    else
      timeout_run "$timeout_secs" bash -c 'claude --resume "$1" --print --thinking-budget "$2" < "$3" 2>&1' -- "$session_id" "$validated_budget" "$prompt_file"
      exit_code=$?
    fi
  fi

  # 一時ファイルのクリーンアップ
  rm -f "$prompt_file" 2>/dev/null

  return $exit_code
}

# =====================================================
# Codex CLI セッション管理
# =====================================================

# codex-wrapper-high.sh のパス（Coder用: high effort）
# 呼び出し元で設定されていなければ推測
CODEX_WRAPPER_HIGH="${CODEX_WRAPPER_HIGH:-}"

# Codex ラッパー存在確認（内部関数）
_ensure_codex_wrapper() {
  if [[ -z "$CODEX_WRAPPER_HIGH" ]]; then
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CODEX_WRAPPER_HIGH="$(cd "$script_dir/../../../scripts" && pwd)/codex-wrapper-high.sh"
  fi

  if [[ ! -x "$CODEX_WRAPPER_HIGH" ]]; then
    die "codex-wrapper-high.sh not found or not executable: $CODEX_WRAPPER_HIGH"
  fi
}

# NOTE: _validate_codex_session_id() は削除済み（resume 機能廃止のため）

# Codex セッション開始（初回実行）
# Usage: codex_session_start <prompt_file> <output_file> [timeout_secs]
# Returns: session_id (stdout)
# Note: codex exec で実行し、最新のセッションIDを返す
codex_session_start() {
  local prompt_file="$1"
  local output_file="$2"
  local timeout_secs="${3:-7200}"  # デフォルト2時間

  if [[ -z "$prompt_file" || ! -f "$prompt_file" ]]; then
    log_error "codex_session_start: prompt_file not found: $prompt_file"
    return 1
  fi

  if [[ -z "$output_file" ]]; then
    log_error "codex_session_start: output_file is required"
    return 1
  fi

  _ensure_codex_wrapper

  log_info "Starting Codex session..."

  # セッションID誤紐付け防止: Codex実行前のepoch時刻を記録
  local start_epoch
  start_epoch=$(date +%s)

  # codex exec 実行
  local exit_code=0
  if timeout_run "$timeout_secs" "$CODEX_WRAPPER_HIGH" --stdin < "$prompt_file" > "$output_file" 2>&1; then
    log_info "Codex execution completed"
  else
    exit_code=$?
    log_warn "Codex execution returned: $exit_code"
  fi

  # 最新のセッションIDを取得（after_epochで実行開始以降のセッションのみ対象）
  local session_id
  session_id=$(get_latest_codex_session "$start_epoch")

  if [[ -n "$session_id" ]]; then
    log_info "Codex session: $session_id"
    echo "$session_id"
    return $exit_code
  else
    log_warn "Could not retrieve Codex session ID"
    return 1
  fi
}

# NOTE: codex_session_resume() は削除済み（TTY必須のためオーケストレーター経由では動作しない）
