#!/usr/bin/env bash
# reviewer.sh - Reviewer (Codex) 実行関数
# エージェント自動化システム用
#
# 依存: utils.sh, state.sh, timeout.sh が先に読み込まれていること
# 依存: codex CLI, jq

# レビュワー設定
REVIEWER_TIMEOUT="${REVIEWER_TIMEOUT:-7200}"  # 2時間（Codex xhigh用）
REVIEWER_PARALLEL_MAX="${REVIEWER_PARALLEL_MAX:-3}"  # 最大並列数
REVIEWER_DEFAULT_LIST="safety,perf,consistency"  # デフォルトレビュワー一覧

# =====================================================
# 動的レビュワー選択
# =====================================================

# 利用可能なレビュワー一覧を取得
# Usage: reviewer_list_available
# Returns: カンマ区切りのレビュワー名一覧
reviewer_list_available() {
  local prompt_dir
  prompt_dir=$(_get_prompt_dir)

  local reviewers=()
  for f in "$prompt_dir"/reviewer_*.md; do
    if [[ -f "$f" ]]; then
      local name
      name=$(basename "$f" | sed 's/^reviewer_//' | sed 's/\.md$//')
      if _validate_reviewer_name "$name" 2>/dev/null; then
        reviewers+=("$name")
      fi
    fi
  done

  # カンマ区切りで返す
  local IFS=','
  echo "${reviewers[*]}"
}

# タスク内容を分析し、適切なレビュワーを動的に選択
# Usage: reviewer_select_dynamic <coder_output> [task_description]
# Returns: カンマ区切りのレビュワー名一覧 (stdout)
# Note: Codex/Claude に問い合わせてタスク内容に最適なレビュワーを選択
reviewer_select_dynamic() {
  local coder_output="$1"
  local task_description="${2:-}"

  if [[ -z "$coder_output" || ! -f "$coder_output" ]]; then
    log_warn "reviewer_select_dynamic: coder_output not found, using defaults"
    echo "$REVIEWER_DEFAULT_LIST"
    return
  fi

  # 利用可能なレビュワー一覧を取得
  local available
  available=$(reviewer_list_available)

  if [[ -z "$available" ]]; then
    log_warn "No reviewers available, using defaults"
    echo "$REVIEWER_DEFAULT_LIST"
    return
  fi

  # コード内容からヒューリスティックにレビュワーを選択
  # （将来的にはCodex/Claudeで分析可能）
  local selected=()
  local content
  content=$(cat "$coder_output" 2>/dev/null || true)

  # 常に基本レビュワーを含める
  selected+=("safety")

  # SQL/DB関連コードがあればsql_injectionレビュワーを追加
  if echo "$content" | grep -qiE '(SELECT|INSERT|UPDATE|DELETE|sql|database|query)'; then
    if echo "$available" | grep -q "sql_injection"; then
      selected+=("sql_injection")
    fi
  fi

  # パフォーマンス関連
  if echo "$content" | grep -qiE '(loop|iteration|cache|memory|performance|async|await)'; then
    selected+=("perf")
  fi

  # フロントエンド/UI関連
  if echo "$content" | grep -qiE '(component|render|style|css|html|jsx|tsx|vue)'; then
    if echo "$available" | grep -q "accessibility"; then
      selected+=("accessibility")
    fi
    selected+=("consistency")
  else
    # バックエンド/汎用の場合
    selected+=("consistency")
  fi

  # 認証/セキュリティ関連
  if echo "$content" | grep -qiE '(auth|login|password|token|jwt|session|cookie|credential)'; then
    if echo "$available" | grep -q "auth_security"; then
      selected+=("auth_security")
    fi
  fi

  # 重複を除去
  local unique_arr
  mapfile -t unique_arr < <(printf '%s\n' "${selected[@]}" | sort -u)

  # available との交差処理（存在しないレビュワーを除外）
  # available はカンマ区切り → 配列に変換
  local available_arr
  IFS=',' read -ra available_arr <<< "$available"

  local final_selected=()
  for sel in "${unique_arr[@]}"; do
    for avail in "${available_arr[@]}"; do
      if [[ "$sel" == "$avail" ]]; then
        final_selected+=("$sel")
        break
      fi
    done
  done

  # 交差後に空になった場合はデフォルトにフォールバック
  if [[ ${#final_selected[@]} -eq 0 ]]; then
    log_warn "Dynamic selection resulted in no valid reviewers, using defaults"
    echo "$REVIEWER_DEFAULT_LIST"
    return
  fi

  local result
  result=$(IFS=','; echo "${final_selected[*]}")

  log_info "Dynamic reviewer selection: $result (from candidates: $(IFS=','; echo "${unique_arr[*]}"))"
  echo "$result"
}

# レビュワー名検証（パストラバーサル/インジェクション防止）
# Usage: _validate_reviewer_name <name>
# Returns: 0 if valid, 1 if invalid (exits on invalid)
_validate_reviewer_name() {
  local name="$1"

  if [[ -z "$name" ]]; then
    log_error "Reviewer name cannot be empty"
    return 1
  fi

  # 許可パターン: 英数字、ハイフン、アンダースコアのみ（1-50文字）
  # Note: bash 3.x互換のため{m,n}量指定子を使わず、長さを別途チェック
  local len=${#name}
  if [[ $len -lt 1 || $len -gt 50 ]]; then
    log_error "Invalid reviewer name: '$name' (allowed: 1-50 chars)"
    return 1
  fi

  local pattern='^[a-zA-Z0-9_-]+$'
  if [[ ! "$name" =~ $pattern ]]; then
    log_error "Invalid reviewer name: '$name' (allowed: alphanumeric, hyphen, underscore)"
    return 1
  fi

  # 追加チェック: パストラバーサル文字を明示的に拒否
  if [[ "$name" == *".."* ]] || [[ "$name" == *"/"* ]] || [[ "$name" == *"\\"* ]]; then
    log_error "Invalid reviewer name: '$name' contains path traversal characters"
    return 1
  fi

  return 0
}

# codex-wrapper-xhigh.sh のパス（Reviewer用: xhigh effort）
# 呼び出し元で設定されていなければ推測
CODEX_WRAPPER_XHIGH="${CODEX_WRAPPER_XHIGH:-}"

# Codex ラッパー存在確認
_ensure_codex_wrapper() {
  if [[ -z "$CODEX_WRAPPER_XHIGH" ]]; then
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CODEX_WRAPPER_XHIGH="$(cd "$script_dir/../../../scripts" && pwd)/codex-wrapper-xhigh.sh"
  fi

  if [[ ! -x "$CODEX_WRAPPER_XHIGH" ]]; then
    die "codex-wrapper-xhigh.sh not found or not executable: $CODEX_WRAPPER_XHIGH"
  fi
}

# プロンプトディレクトリ（呼び出し元で設定されていなければ推測）
_get_prompt_dir() {
  if [[ -n "${PROMPT_DIR:-}" ]]; then
    echo "$PROMPT_DIR"
    return
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "$(cd "$script_dir/../../../docs/prompts" && pwd)"
}

# 単一レビュワー実行
# Usage: reviewer_run_single <reviewer_name> <coder_output> <output_file> [timeout_secs]
# Returns: 0 on success, 124 on timeout, 1 on error
# Stdout: 新しい session_id（ログ/追跡用）
# Note: codex resume は TTY 必須のため、常に新規セッションで実行
#       session_id/task_tmpdir パラメータは後方互換性のため受け取るが無視される
reviewer_run_single() {
  local reviewer_name="$1"
  local coder_output="$2"
  local output_file="$3"
  local timeout_secs="${4:-$REVIEWER_TIMEOUT}"
  # 後方互換性: session_id/task_tmpdir は受け取るが使用しない（codex resume は TTY 必須）
  # local session_id="${5:-}"
  # local task_tmpdir="${6:-}"

  if [[ -z "$reviewer_name" ]]; then
    log_error "reviewer_run_single: reviewer_name is required"
    return 1
  fi

  # セキュリティ: レビュワー名を検証
  if ! _validate_reviewer_name "$reviewer_name"; then
    return 1
  fi

  if [[ -z "$coder_output" || ! -f "$coder_output" ]]; then
    log_error "reviewer_run_single: coder_output not found: $coder_output"
    return 1
  fi

  if [[ -z "$output_file" ]]; then
    log_error "reviewer_run_single: output_file is required"
    return 1
  fi

  _ensure_codex_wrapper

  local prompt_dir
  prompt_dir=$(_get_prompt_dir)
  local prompt_file="$prompt_dir/reviewer_${reviewer_name}.md"

  if [[ ! -f "$prompt_file" ]]; then
    log_warn "Reviewer prompt not found: $prompt_file (skip)"
    return 1
  fi

  # プロンプト内容を結合
  local combined_content
  combined_content=$(cat "$prompt_file" "$coder_output")

  local exit_code=0
  local new_session_id=""

  # 常に新規セッションで実行（codex resume は TTY 必須のため使用不可）
  log_info "Running reviewer: $reviewer_name (timeout: ${timeout_secs}s)"

  # セッションID誤紐付け防止: Codex実行前のepoch時刻を記録
  local start_epoch
  start_epoch=$(date +%s)

  # 入力を一時ファイルに結合
  local combined_input
  combined_input=$(create_temp_file "review_input_${reviewer_name}")
  echo "$combined_content" > "$combined_input"

  if timeout_run "$timeout_secs" "$CODEX_WRAPPER_XHIGH" --stdin < "$combined_input" > "$output_file" 2>&1; then
    log_info "Reviewer $reviewer_name completed"
    exit_code=0
  else
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      log_warn "Reviewer $reviewer_name timed out after ${timeout_secs}s"
      echo "[TIMEOUT] Reviewer $reviewer_name timed out after ${timeout_secs}s" > "$output_file"
    else
      log_warn "Reviewer $reviewer_name returned non-zero: $exit_code"
    fi
  fi

  rm -f "$combined_input"

  # session_id を取得して出力（ログ/追跡用）
  # after_epoch パラメータで実行開始以降に作成されたセッションのみを対象
  new_session_id=$(get_latest_codex_session "$start_epoch" 2>/dev/null || true)
  if [[ -n "$new_session_id" ]]; then
    echo "$new_session_id"
  fi

  return $exit_code
}

# 並列レビュワー実行（セッション対応版）
# Usage: reviewer_run_parallel <reviewer_list> <coder_output> <output_dir> [timeout_secs] [phase_for_files] [task_tmpdir] [phase_for_state]
# Returns: 0 if all succeeded, number of failures otherwise
# Note: reviewer_list はカンマ区切り（例: "safety,perf,consistency"）
# Note: 各レビュワーの結果は <output_dir>/<phase_for_files>_review_<reviewer>.md に保存
# Note: session_id は state.json から phase_for_state を使って取得・保存
reviewer_run_parallel() {
  local reviewer_list="$1"
  local coder_output="$2"
  local output_dir="$3"
  local timeout_secs="${4:-$REVIEWER_TIMEOUT}"
  local phase_for_files="${5:-phase}"
  local task_tmpdir="${6:-}"
  local phase_for_state="${7:-$phase_for_files}"  # state.json 用フェーズ名（suffix なし）

  if [[ -z "$reviewer_list" ]]; then
    log_warn "reviewer_run_parallel: reviewer_list is empty"
    return 0
  fi

  if [[ -z "$coder_output" || ! -f "$coder_output" ]]; then
    log_error "reviewer_run_parallel: coder_output not found: $coder_output"
    return 1
  fi

  mkdir -p "$output_dir"

  _ensure_codex_wrapper

  local prompt_dir
  prompt_dir=$(_get_prompt_dir)

  # レビュワーリストをパース
  IFS=',' read -ra reviewers <<<"$reviewer_list"
  local num_reviewers=${#reviewers[@]}

  if [[ $num_reviewers -eq 0 ]]; then
    log_warn "No reviewers specified"
    return 0
  fi

  log_info "Starting parallel review with $num_reviewers reviewers: ${reviewer_list}"

  # セッションIDを state.json から取得（phase_for_state を使用）
  local session_ids_json="{}"
  if [[ -n "$task_tmpdir" ]]; then
    session_ids_json=$(reviewer_get_all_session_ids "$phase_for_state" 2>/dev/null || echo "{}")
  fi

  # バックグラウンドジョブで並列実行
  local pids=()
  local outputs=()
  local names=()
  local session_id_files=()  # 各レビュワーの新session_idを受け取るファイル
  local stagger_idx=0  # 1秒スタガー用インデックス

  for r in "${reviewers[@]}"; do
    # セキュリティ: レビュワー名を検証
    if ! _validate_reviewer_name "$r"; then
      log_warn "Skipping invalid reviewer: $r"
      continue
    fi
    local prompt_file="$prompt_dir/reviewer_${r}.md"
    if [[ ! -f "$prompt_file" ]]; then
      log_warn "Reviewer prompt not found: $prompt_file (skip)"
      continue
    fi

    local outfile="$output_dir/${phase_for_files}_review_${r}.md"
    local session_id_file
    session_id_file=$(create_temp_file "session_id_${r}")

    # 既存のsession_idを取得
    local existing_session_id=""
    if [[ "$session_ids_json" != "{}" ]]; then
      existing_session_id=$(echo "$session_ids_json" | jq -r --arg r "$r" '.[$r] // empty' 2>/dev/null || true)
    fi

    # 1秒スタガー起動（セッションID誤紐付け防止）
    # 効果: 各レビュワーが異なる epoch を持つ → 誤紐付けゼロ
    # Codex実行時間（2時間）に比べ、N秒の遅延は無視可能
    if [[ $stagger_idx -gt 0 ]]; then
      log_debug "Stagger delay: ${stagger_idx}s for reviewer $r"
      sleep "$stagger_idx"
    fi

    # バックグラウンドで実行
    # Note: ループ変数をサブシェル用に保存（レースコンディション対策）
    local _outfile="$outfile"
    local _reviewer="$r"
    local _timeout="$timeout_secs"
    local _session_id="$existing_session_id"
    local _task_tmpdir="$task_tmpdir"
    local _coder_output="$coder_output"
    local _session_id_file="$session_id_file"
    (
      local new_sid
      new_sid=$(reviewer_run_single "$_reviewer" "$_coder_output" "$_outfile" "$_timeout" "$_session_id" "$_task_tmpdir")
      local ret=$?

      # 新しいsession_idがあれば保存
      if [[ -n "$new_sid" ]]; then
        echo "$new_sid" > "$_session_id_file"
      fi

      exit $ret
    ) &

    pids+=($!)
    outputs+=("$outfile")
    names+=("$r")
    session_id_files+=("$session_id_file")
    stagger_idx=$((stagger_idx + 1))  # 次のレビュワー用にインクリメント
  done

  # 全レビュワーの完了を待機
  local failures=0
  local i=0
  for pid in "${pids[@]}"; do
    # wait の終了コードを先に取得（`if ! wait` だと $? は ! の結果になる）
    wait "$pid"
    local ret=$?
    if [[ $ret -ne 0 ]]; then
      log_warn "Reviewer ${names[$i]} exited with code $ret"
      failures=$((failures + 1))
    fi

    # 新しいsession_idを state.json に保存
    if [[ -f "${session_id_files[$i]}" ]]; then
      local new_sid
      new_sid=$(cat "${session_id_files[$i]}" 2>/dev/null || true)
      if [[ -n "$new_sid" && -n "$task_tmpdir" ]]; then
        # iteration 番号は state.json から取得（phase_for_state を使用）
        local current_iteration=1
        local phase_idx
        phase_idx=$(state_find_phase "$phase_for_state" 2>/dev/null || echo "-1")
        if [[ "$phase_idx" != "-1" ]]; then
          current_iteration=$(state_get ".phases[$phase_idx].iteration" 2>/dev/null || echo 1)
        fi
        reviewer_set_session_id "$phase_for_state" "$current_iteration" "${names[$i]}" "$new_sid" 2>/dev/null || true
      fi
      rm -f "${session_id_files[$i]}"
    fi

    i=$((i + 1))
  done

  log_info "Parallel review completed: ${#pids[@]} reviewers, $failures failures"
  return $failures
}

# レビュー結果集約
# Usage: reviewer_aggregate <output_dir> <phase> [output_file]
# Returns: path to aggregated file (stdout)
reviewer_aggregate() {
  local output_dir="$1"
  local phase="$2"
  local output_file="${3:-}"

  if [[ -z "$output_file" ]]; then
    output_file="$output_dir/${phase}_reviews.md"
  fi

  : > "$output_file"

  # レビューファイルを検索して集約
  local count=0
  for review_file in "$output_dir"/${phase}_review_*.md; do
    if [[ -f "$review_file" ]]; then
      local basename
      basename=$(basename "$review_file")
      echo "## $basename" >> "$output_file"
      cat "$review_file" >> "$output_file"
      echo "" >> "$output_file"
      count=$((count + 1))
    fi
  done

  log_info "Aggregated $count review files -> $output_file"
  echo "$output_file"
}

# ブロッカー（High重大度）検出
# Usage: reviewer_has_blockers <reviews_file>
# Returns: 0 if blockers found, 1 if not
reviewer_has_blockers() {
  local reviews_file="$1"

  if [[ -z "$reviews_file" || ! -f "$reviews_file" ]]; then
    return 1
  fi

  # [High] タグを検索（大文字小文字区別なし）
  if grep -qi '\[High\]' "$reviews_file" 2>/dev/null; then
    return 0
  fi

  return 1
}

# 重大度別カウント
# Usage: reviewer_count_by_severity <reviews_file>
# Returns: JSON object with counts (stdout)
# Example: {"high": 3, "medium": 5, "low": 2}
reviewer_count_by_severity() {
  local reviews_file="$1"

  if [[ -z "$reviews_file" || ! -f "$reviews_file" ]]; then
    echo '{"high": 0, "medium": 0, "low": 0}'
    return
  fi

  local high_count medium_count low_count

  # 大文字小文字を区別せずカウント
  high_count=$(grep -ci '\[High\]' "$reviews_file" 2>/dev/null || echo 0)
  medium_count=$(grep -ci '\[Medium\]' "$reviews_file" 2>/dev/null || echo 0)
  low_count=$(grep -ci '\[Low\]' "$reviews_file" 2>/dev/null || echo 0)

  # jq で安全にJSON生成
  jq -n \
    --argjson high "$high_count" \
    --argjson medium "$medium_count" \
    --argjson low "$low_count" \
    '{high: $high, medium: $medium, low: $low}'
}

# レビュー結果のサマリーを表示
# Usage: reviewer_show_summary <reviews_file>
reviewer_show_summary() {
  local reviews_file="$1"

  if [[ -z "$reviews_file" || ! -f "$reviews_file" ]]; then
    log_warn "Reviews file not found: $reviews_file"
    return 1
  fi

  local counts
  counts=$(reviewer_count_by_severity "$reviews_file")

  local high medium low
  high=$(echo "$counts" | jq -r '.high')
  medium=$(echo "$counts" | jq -r '.medium')
  low=$(echo "$counts" | jq -r '.low')

  echo "=== Review Summary ==="
  echo "File: $reviews_file"
  echo ""
  echo "Severity Counts:"
  echo "  [High]:   $high"
  echo "  [Medium]: $medium"
  echo "  [Low]:    $low"
  echo ""

  if [[ $high -gt 0 ]]; then
    echo "Status: BLOCKERS FOUND"
    return 0
  else
    echo "Status: PASS (no blockers)"
    return 0
  fi
}

# レビュー結果を state.json に記録
# Usage: reviewer_record_to_state <phase> <iteration> <reviews_file>
reviewer_record_to_state() {
  local phase="$1"
  local iteration="$2"
  local reviews_file="$3"

  if [[ -z "$phase" ]]; then
    log_warn "reviewer_record_to_state: phase is empty"
    return 1
  fi

  # セキュリティ: iteration が数値であることを検証
  if [[ ! "$iteration" =~ ^[0-9]+$ ]]; then
    log_warn "reviewer_record_to_state: invalid iteration: $iteration"
    iteration=0
  fi

  local phase_idx
  phase_idx=$(state_find_phase "$phase")

  if [[ "$phase_idx" == "-1" ]]; then
    log_warn "Phase not found in state: $phase"
    return 1
  fi

  local counts
  counts=$(reviewer_count_by_severity "$reviews_file")

  local has_blockers=false
  if reviewer_has_blockers "$reviews_file"; then
    has_blockers=true
  fi

  # レビュー情報を構築
  local review_obj
  review_obj=$(jq -n \
    --argjson iter "$iteration" \
    --argjson blockers "$has_blockers" \
    --argjson counts "$counts" \
    --arg file "$reviews_file" \
    --arg ts "$(get_timestamp)" \
    '{
      iteration: $iter,
      has_blockers: $blockers,
      severity_counts: $counts,
      file: $file,
      timestamp: $ts
    }')

  state_append ".phases[$phase_idx].reviews" "$review_obj"
  # Note: state_save() は呼び出し元で一括実行すること（トランザクション的一貫性のため）
  log_debug "Review recorded to state for phase: $phase (iteration: $iteration)"
}

# 全レビュー実行（ワンショット関数）
# Usage: reviewer_run_all <reviewer_list> <coder_output> <output_dir> <phase> [suffix] [timeout_secs] [task_tmpdir]
# Returns: path to aggregated reviews file (stdout), exit code 0 on success, 1 if all reviewers failed
reviewer_run_all() {
  local reviewer_list="$1"
  local coder_output="$2"
  local output_dir="$3"
  local phase="$4"
  local suffix="${5:-}"
  local timeout_secs="${6:-$REVIEWER_TIMEOUT}"
  local task_tmpdir="${7:-$output_dir}"  # デフォルトは output_dir

  # 並列実行
  # phase_with_suffix: ファイル命名用（例: impl_iter2）
  # phase: state.json 用（例: impl）
  local phase_with_suffix="${phase}${suffix}"
  local failures=0
  reviewer_run_parallel "$reviewer_list" "$coder_output" "$output_dir" "$timeout_secs" "$phase_with_suffix" "$task_tmpdir" "$phase" || failures=$?

  # レビュワー数をカウント
  local num_reviewers
  IFS=',' read -ra _rev_array <<< "$reviewer_list"
  num_reviewers=${#_rev_array[@]}

  # 全レビュワーが失敗した場合はエラー
  if [[ $failures -ge $num_reviewers && $num_reviewers -gt 0 ]]; then
    log_error "All $num_reviewers reviewers failed"
    return 1
  fi

  if [[ $failures -gt 0 ]]; then
    log_warn "$failures of $num_reviewers reviewers failed (continuing with partial results)"
  fi

  # 集約
  local agg_file="$output_dir/${phase}_reviews${suffix}.md"
  reviewer_aggregate "$output_dir" "$phase_with_suffix" "$agg_file"

  echo "$agg_file"
}
