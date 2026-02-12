#!/usr/bin/env bash
# coder.sh - Coder (Claude) 実行関数
# エージェント自動化システム用
#
# 依存: utils.sh, state.sh, session.sh が先に読み込まれていること
# 依存: claude CLI, jq

# Coder 設定
CODER_TIMEOUT="${CODER_TIMEOUT:-1800}"  # 30分（デフォルト）
CODER_MAX_PARALLEL="${CODER_MAX_PARALLEL:-1}"  # 最大並列Coder数

# =====================================================
# 動的エージェント起動
# =====================================================

# タスクの複雑さを分析
# Usage: coder_analyze_task_complexity <plan_path>
# Returns: complexity level (stdout): simple, moderate, complex
coder_analyze_task_complexity() {
  local plan_path="$1"

  if [[ -z "$plan_path" || ! -f "$plan_path" ]]; then
    echo "simple"
    return
  fi

  local content
  content=$(cat "$plan_path" 2>/dev/null || true)

  # ヒューリスティック: タスクの複雑さを判定
  local score=0

  # ファイル数の言及があるか
  local file_mentions
  file_mentions=$(echo "$content" | grep -ciE '\.(ts|js|py|go|rs|java|tsx|jsx|vue|sh)' 2>/dev/null | tr -d '\n' || echo 0)
  # 空の場合は0にフォールバック
  [[ -z "$file_mentions" ]] && file_mentions=0
  if [[ $file_mentions -gt 10 ]]; then
    score=$((score + 2))
  elif [[ $file_mentions -gt 5 ]]; then
    score=$((score + 1))
  fi

  # 複数モジュール/パッケージの変更
  if echo "$content" | grep -qiE '(multiple|several|many|各|複数).*(file|module|package|component)'; then
    score=$((score + 2))
  fi

  # リファクタリング/マイグレーション
  if echo "$content" | grep -qiE '(refactor|migration|リファクタ|移行|マイグレーション)'; then
    score=$((score + 2))
  fi

  # テスト作成
  if echo "$content" | grep -qiE '(test|spec|テスト)'; then
    score=$((score + 1))
  fi

  # 結果を返す
  if [[ $score -ge 4 ]]; then
    echo "complex"
  elif [[ $score -ge 2 ]]; then
    echo "moderate"
  else
    echo "simple"
  fi
}

# 推奨Coder数を取得
# Usage: coder_get_recommended_count <complexity> [max_coders]
# Returns: recommended coder count (stdout)
coder_get_recommended_count() {
  local complexity="$1"
  local max_coders="${2:-$CODER_MAX_PARALLEL}"

  case "$complexity" in
    complex)
      # 複雑なタスク: 最大数を推奨
      echo "$max_coders"
      ;;
    moderate)
      # 中程度: 2つまで
      local count=2
      [[ $count -gt $max_coders ]] && count=$max_coders
      echo "$count"
      ;;
    simple|*)
      # シンプル: 1つ
      echo "1"
      ;;
  esac
}

# 動的エージェント戦略情報をログ出力
# Usage: coder_log_strategy <plan_path> <max_coders>
coder_log_strategy() {
  local plan_path="$1"
  local max_coders="${2:-1}"

  local complexity
  complexity=$(coder_analyze_task_complexity "$plan_path")

  local recommended
  recommended=$(coder_get_recommended_count "$complexity" "$max_coders")

  log_info "Dynamic agent strategy:"
  log_info "  Task complexity: $complexity"
  log_info "  Max coders allowed: $max_coders"
  log_info "  Recommended coders: $recommended"

  echo "$recommended"
}

# jq 存在確認
_ensure_jq_coder() {
  if ! command -v jq >/dev/null 2>&1; then
    die "jq not found. Please install jq (brew install jq / apt install jq)."
  fi
}

# プロンプトディレクトリ（呼び出し元で設定されていなければデフォルト）
PROMPT_DIR="${PROMPT_DIR:-}"

# プロンプト構築
# Usage: coder_build_prompt <plan_path> <phase> [extra_context]
# Returns: 構築されたプロンプト（stdoutに出力）
coder_build_prompt() {
  local plan_path="$1"
  local phase="$2"
  local extra_context="${3:-}"

  if [[ -z "$plan_path" ]]; then
    die "coder_build_prompt: plan_path is required"
  fi

  if [[ ! -f "$plan_path" ]]; then
    die "coder_build_prompt: plan file not found: $plan_path"
  fi

  if [[ -z "$phase" ]]; then
    die "coder_build_prompt: phase is required"
  fi

  # フェーズ名を検証（セキュリティ）
  _validate_identifier "$phase" "phase"

  # プロンプトディレクトリを決定（ローカル変数を使用してグローバルを上書きしない）
  local prompt_dir
  if [[ -n "$PROMPT_DIR" ]]; then
    prompt_dir="$PROMPT_DIR"
  else
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    prompt_dir="$(cd "$script_dir/../../.." && pwd)/docs/prompts"
  fi

  # フェーズ別プロンプト
  local prompt_file="$prompt_dir/coder_phase_${phase}.md"
  if [[ ! -f "$prompt_file" ]]; then
    # フォールバック: impl プロンプト
    prompt_file="$prompt_dir/coder_phase_impl.md"
  fi

  local phase_prompt=""
  if [[ -f "$prompt_file" ]]; then
    phase_prompt=$(cat "$prompt_file")
  else
    log_warn "No phase prompt found, using minimal instructions"
    phase_prompt="Execute the ${phase} phase according to the plan."
  fi

  # プロンプト構築（ヒアドキュメント内の $(...) 展開を防ぐため、変数は別途追記）
  {
    cat <<'EOF'
# Plan
EOF
    cat "$plan_path"
    cat <<'EOF'

# Phase Instructions
EOF
    printf '%s\n' "$phase_prompt"
    cat <<'EOF'

# Context
EOF
    printf 'Current phase: %s\n' "$phase"
    if [[ -n "$extra_context" ]]; then
      printf '\n%s\n' "$extra_context"
    fi
    cat <<'EOF'

# Output Format
- 変更差分とテスト結果を Markdown で出力
- 末尾に `---OUTPUT-END---` を付ける
EOF
  }
}

# Coder 実行（新規セッション）
# Usage: coder_run <plan_path> <phase> <output_file> [extra_context]
# Returns: session_id（stdoutに出力）、実行結果は output_file に保存
coder_run() {
  local plan_path="$1"
  local phase="$2"
  local output_file="$3"
  local extra_context="${4:-}"

  if [[ -z "$output_file" ]]; then
    die "coder_run: output_file is required"
  fi

  log_info "Running Coder for phase: $phase"

  # プロンプト構築
  local prompt
  prompt=$(coder_build_prompt "$plan_path" "$phase" "$extra_context")

  # 新規セッション開始
  local session_id
  session_id=$(session_start "$prompt" "$output_file")

  if [[ -n "$session_id" ]]; then
    log_info "Coder session: $session_id"
    log_info "Coder output: $output_file"
  else
    log_warn "Session ID not captured, but output may still be valid"
  fi

  echo "$session_id"
}

# Coder 修正実行
# Usage: coder_run_fix <plan_path> <phase> <reviews_file> <iteration> <output_file> [session_id] [fix_until]
# Returns: session_id（stdoutに出力）
# fix_until: high | medium | low | all（デフォルト: all）
coder_run_fix() {
  local plan_path="$1"
  local phase="$2"
  local reviews_file="$3"
  local iteration="$4"
  local output_file="$5"
  local session_id="${6:-}"
  local fix_until="${7:-all}"

  if [[ -z "$reviews_file" || ! -f "$reviews_file" ]]; then
    die "coder_run_fix: reviews_file not found: $reviews_file"
  fi

  if [[ -z "$output_file" ]]; then
    die "coder_run_fix: output_file is required"
  fi

  log_info "Running Coder fix iteration $iteration for phase: $phase"

  # fix_until に基づいた動的メッセージ
  local fix_message
  case "$fix_until" in
    high)
      fix_message="[High] 重大度の指摘を必ず解消してください。"
      ;;
    medium)
      fix_message="[High] と [Medium] 重大度の指摘を必ず解消してください。"
      ;;
    low|all|*)
      fix_message="[High]、[Medium]、[Low] すべての指摘を解消してください。"
      ;;
  esac

  # 修正プロンプト構築（ヒアドキュメント内の $(...) 展開を防ぐため、変数は別途追記）
  local fix_prompt
  fix_prompt=$({
    printf '# Review Feedback (Iteration %s)\n' "$iteration"
    printf '%s\n\n' "$fix_message"
    cat "$reviews_file"
    cat <<'EOF'

# Original Plan
EOF
    cat "$plan_path"
    cat <<'EOF'

# Instructions
- 上記の重大度に応じた指摘を解消する
- 変更差分とテスト結果を Markdown で出力
- 末尾に `---OUTPUT-END---` を付ける

---OUTPUT-END---
EOF
  })

  local new_session_id=""

  if [[ -n "$session_id" ]] && _validate_session_id "$session_id"; then
    # セッション継続
    log_info "Resuming session: $session_id"
    if session_resume "$session_id" "$fix_prompt" "$output_file"; then
      new_session_id="$session_id"
    else
      log_warn "Session resume failed, starting new session"
      new_session_id=$(session_start "$fix_prompt" "$output_file")
    fi
  else
    # 新規セッション
    new_session_id=$(session_start "$fix_prompt" "$output_file")
  fi

  if [[ -n "$new_session_id" ]]; then
    log_info "Fix session: $new_session_id"
  fi

  echo "$new_session_id"
}

# Coder セッション継続
# Usage: coder_resume <session_id> <prompt> <output_file>
# Returns: 0 on success, 1 on failure
coder_resume() {
  local session_id="$1"
  local prompt="$2"
  local output_file="$3"

  if [[ -z "$session_id" ]]; then
    die "coder_resume: session_id is required"
  fi

  if [[ -z "$prompt" ]]; then
    die "coder_resume: prompt is required"
  fi

  if [[ -z "$output_file" ]]; then
    die "coder_resume: output_file is required"
  fi

  log_info "Resuming Coder session: $session_id"

  if session_resume "$session_id" "$prompt" "$output_file"; then
    log_info "Coder resumed, output: $output_file"
    return 0
  else
    log_error "Coder resume failed for session: $session_id"
    return 1
  fi
}

# Coder セッション分岐
# Usage: coder_fork <parent_session_id> <prompt> <output_file>
# Returns: new_session_id（stdoutに出力）
coder_fork() {
  local parent_session_id="$1"
  local prompt="$2"
  local output_file="$3"

  if [[ -z "$parent_session_id" ]]; then
    die "coder_fork: parent_session_id is required"
  fi

  if [[ -z "$prompt" ]]; then
    die "coder_fork: prompt is required"
  fi

  if [[ -z "$output_file" ]]; then
    die "coder_fork: output_file is required"
  fi

  log_info "Forking Coder session from: $parent_session_id"

  local new_session_id
  new_session_id=$(session_fork "$parent_session_id" "$prompt" "$output_file")

  if [[ -n "$new_session_id" ]]; then
    log_info "Coder forked: $parent_session_id -> $new_session_id"
    log_info "Coder fork output: $output_file"
  else
    log_warn "Fork session ID not captured"
  fi

  echo "$new_session_id"
}

# Coder 実行（タイムアウト付き）
# Usage: coder_run_with_timeout <timeout_secs> <plan_path> <phase> <output_file> [session_id]
# Returns: 0 on success, 124 on timeout, other on error
coder_run_with_timeout() {
  local timeout_secs="$1"
  local plan_path="$2"
  local phase="$3"
  local output_file="$4"
  local session_id="${5:-}"

  log_info "Running Coder with timeout: ${timeout_secs}s"

  # プロンプト構築
  local prompt
  prompt=$(coder_build_prompt "$plan_path" "$phase")

  # セッション実行（タイムアウト付き）
  if session_run_with_timeout "$timeout_secs" "$session_id" "$prompt" "$output_file"; then
    log_info "Coder completed within timeout"
    return 0
  else
    local ret=$?
    if [[ $ret -eq 124 ]]; then
      log_warn "Coder timed out after ${timeout_secs}s"
    else
      log_warn "Coder returned error: $ret"
    fi
    return $ret
  fi
}

# Coder 出力検証
# Usage: coder_validate_output <output_file>
# Returns: 0 if valid (contains OUTPUT-END marker), 1 if incomplete
coder_validate_output() {
  local output_file="$1"

  if [[ ! -f "$output_file" ]]; then
    log_warn "Output file not found: $output_file"
    return 1
  fi

  if [[ ! -s "$output_file" ]]; then
    log_warn "Output file is empty: $output_file"
    return 1
  fi

  # OUTPUT-END マーカーを確認
  if grep -q '\-\-\-OUTPUT-END\-\-\-' "$output_file"; then
    log_debug "Output validated: $output_file"
    return 0
  else
    log_warn "Output missing ---OUTPUT-END--- marker: $output_file"
    return 1
  fi
}

# state.json にCoder情報を記録
# Usage: coder_record_to_state <phase> <session_id> <output_file>
coder_record_to_state() {
  local phase="$1"
  local session_id="$2"
  local output_file="$3"

  # jq 依存チェック
  _ensure_jq_coder

  if [[ -z "$phase" ]]; then
    log_warn "coder_record_to_state: phase is empty"
    return 1
  fi

  local phase_idx
  phase_idx=$(state_find_phase "$phase")

  if [[ "$phase_idx" == "-1" ]]; then
    log_warn "Phase not found in state: $phase"
    return 1
  fi

  # coder 情報を更新
  local coder_obj
  if [[ -n "$session_id" ]]; then
    coder_obj=$(jq -n \
      --arg sid "$session_id" \
      --arg out "$output_file" \
      '{
        session_id: $sid,
        output_file: $out
      }')
  else
    coder_obj=$(jq -n \
      --arg out "$output_file" \
      '{
        output_file: $out
      }')
  fi

  state_set ".phases[$phase_idx].coder" "$coder_obj"

  # セッションも記録（session_id がある場合）
  if [[ -n "$session_id" ]]; then
    local iteration
    iteration=$(state_get ".phases[$phase_idx].iteration")
    [[ -z "$iteration" || "$iteration" == "null" ]] && iteration=0
    session_record "$session_id" "$phase" "$iteration"
  fi

  state_save
  log_debug "Coder info recorded to state for phase: $phase"
}

# 最新の Coder 出力ファイルを取得
# Usage: coder_get_latest_output <phase> <tmpdir>
# Returns: output_file path（stdoutに出力）
coder_get_latest_output() {
  local phase="$1"
  local tmpdir="$2"

  if [[ -z "$tmpdir" || ! -d "$tmpdir" ]]; then
    return 1
  fi

  # フェーズ名検証
  _validate_identifier "$phase" "phase"

  # 最新の修正ファイルを探す（fix3, fix2, fix1 の順）
  local i
  for i in 10 9 8 7 6 5 4 3 2 1; do
    local fix_file="$tmpdir/${phase}_coder_fix${i}.md"
    if [[ -f "$fix_file" ]]; then
      echo "$fix_file"
      return 0
    fi
  done

  # 修正ファイルがなければオリジナル
  local original="$tmpdir/${phase}_coder.md"
  if [[ -f "$original" ]]; then
    echo "$original"
    return 0
  fi

  return 1
}
