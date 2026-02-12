#!/usr/bin/env bash
set -euo pipefail

# ディレクトリ設定
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
PROMPT_DIR="$REPO_ROOT/docs/prompts"
TMP_BASE="$REPO_ROOT/.claude/tmp"
QUALITY_GATE="$REPO_ROOT/scripts/quality_gate.sh"
CODEX_WRAPPER_HIGH="$REPO_ROOT/scripts/codex-wrapper-high.sh"
CODEX_WRAPPER_XHIGH="$REPO_ROOT/scripts/codex-wrapper-xhigh.sh"
CODEX_WRAPPER="$CODEX_WRAPPER_HIGH"  # 後方互換性
LIB_DIR="$DIR/lib"
REVIEW_QUEUE_FILE="$REPO_ROOT/.claude/tmp/review_queue.json"
REVIEW_QUEUE_LOCK="$REPO_ROOT/.claude/tmp/review_queue.lock"

# lib 読み込み
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/timeout.sh"
source "$LIB_DIR/session.sh"
source "$LIB_DIR/coder.sh"
source "$LIB_DIR/reviewer.sh"

# グローバル変数
PLAN=""
PHASE=""
REVIEWERS="safety,perf,consistency"
GATE=""
CODER_OUT=""
RUN_CODER=false
MAX_ITERATIONS=5
CODEX_TIMEOUT=7200  # 2時間（秒）
CLAUDE_TIMEOUT=1800 # 30分（秒）
RESUME_STATE=""     # --resume で指定された state.json
CONTINUE_SESSION=false  # --continue-session: 前回セッションを継続
FORK_SESSION=false      # --fork-session: 前回セッションを分岐
SESSION_ID=""           # 現在のセッションID
FIX_UNTIL="all"         # --fix-until: 修正対象レベル（high/medium/low/all）デフォルト: all
LOCK_FILE=""            # ロックファイルパス（acquire_lock で設定）
LOCK_ACQUIRED=false     # ロック取得成功フラグ（release_lock のガード用）
RECOVER_MODE=false      # --recover: stale state をリカバリ
AGENT_STRATEGY="fixed"  # --agent-strategy: fixed(デフォルト) または dynamic
MAX_CODERS=1            # --max-coders: 最大Coderエージェント数（dynamic時）
REVIEWER_STRATEGY="fixed"  # --reviewer-strategy: fixed(デフォルト) または auto

usage() {
  cat <<'USAGE'
Usage: auto_orchestrate.sh --plan PATH --phase PHASE [OPTIONS]
       auto_orchestrate.sh --resume STATE_FILE [OPTIONS]

Options:
  --plan PATH                 プランファイルのパス（新規実行時は必須）
  --phase PHASE               フェーズ名: test, impl など（新規実行時は必須）
  --resume STATE_FILE         state.json から再開（中断した実行を継続）
  --reviewers LIST            レビュワー一覧（デフォルト: safety,perf,consistency）
  --coder-output FILE         Coder出力ファイル（指定しない場合は自動パス）
  --gate levelA|levelB|levelC 品質ゲートのレベル
  --run-coder                 ClaudeCode CLIでCoderを自動起動
  --continue-session          前回のセッションを継続（コンテキスト保持）
  --fork-session              前回のセッションを分岐（別アプローチ試行）
  --max-iterations N          レビュー反復の最大回数（デフォルト: 5）
                              Note: N=1は「1回レビューして問題があれば即失敗」を意味する
  --fix-until LEVEL           修正対象レベル: high, medium, low, all（デフォルト: all）
  --codex-timeout SECS        Codexレビューのタイムアウト秒（デフォルト: 7200 = 2時間）
  --claude-timeout SECS       Claude Coderのタイムアウト秒（デフォルト: 1800 = 30分）
  --recover                   Stale state を検出してクリーンアップ（--resume と併用）
  --agent-strategy MODE       エージェント起動戦略: fixed(デフォルト), dynamic
  --max-coders N              最大Coderエージェント数（dynamic時、デフォルト: 1）
  --reviewer-strategy MODE    レビュワー選択戦略: fixed(デフォルト), auto
  --status                    state.json のサマリーを表示
  -h, --help                  ヘルプを表示

Session Options:
  --continue-session と --fork-session は --resume と組み合わせて使用します。
  これにより、前回のClaude CLIセッションのコンテキストを保持したまま
  作業を継続できます（API課金なしでコンテキスト継続）。

Steps:
 1) --run-coder 指定時: ClaudeCode CLIでCoderを起動しフェーズ出力を生成
 2) 各観点レビュワー(Codex)を並列実行し、指摘を集約
 3) ブロッカー指摘があれば修正→再レビューを反復（最大 max-iterations 回）
 4) --gate 指定時: 品質ゲートを実行

Examples:
  # 新規実行
  ./auto_orchestrate.sh --plan .agent/plan_*.md --phase impl --run-coder --gate levelB

  # 中断後の再開
  ./auto_orchestrate.sh --resume .claude/tmp/<task>/state.json

  # セッション継続（前回のコンテキストを保持）
  ./auto_orchestrate.sh --resume .claude/tmp/<task>/state.json --continue-session

  # セッション分岐（別アプローチを試行）
  ./auto_orchestrate.sh --resume .claude/tmp/<task>/state.json --fork-session

  # 状態確認
  ./auto_orchestrate.sh --resume .claude/tmp/<task>/state.json --status
USAGE
}

# 注: log_info, log_warn, log_error, die, ensure_cmd は lib/utils.sh から提供
SHOW_STATUS=false

# シグナルハンドリング用変数
CLEANUP_DONE=false

# =====================================================
# Lock Functions (同時実行防止)
# =====================================================

# ロック取得
# Usage: acquire_lock <task_tmpdir>
# Returns: 0 on success, dies on failure
# Note: macOS では flock がない場合があるため、mkdir ベースのロックも使用
# Security: LOCK_ACQUIRED フラグで所有権を管理し、他プロセスのロック誤解除を防止
acquire_lock() {
  local task_tmpdir="$1"
  local lock_file="$task_tmpdir/.lock"
  local lock_dir="${lock_file}.d"

  # まず mkdir を試みる（アトミック操作）
  if mkdir "$lock_dir" 2>/dev/null; then
    # ロック取得成功 - ここで初めて LOCK_FILE と LOCK_ACQUIRED を設定
    LOCK_FILE="$lock_file"
    LOCK_ACQUIRED=true
    log_debug "Lock acquired (mkdir): $lock_dir"
    return 0
  fi

  # 既存ロックがある場合、stale かどうかチェック
  if [[ -d "$lock_dir" ]]; then
    # ロックディレクトリの作成時刻を確認（1時間以上前なら stale とみなす）
    local lock_age=0
    if [[ "$(uname)" == "Darwin" ]]; then
      # macOS
      lock_age=$(( $(date +%s) - $(stat -f %m "$lock_dir" 2>/dev/null || echo 0) ))
    else
      # Linux
      lock_age=$(( $(date +%s) - $(stat -c %Y "$lock_dir" 2>/dev/null || echo 0) ))
    fi

    if [[ $lock_age -gt 3600 ]]; then
      log_warn "Found stale lock (age: ${lock_age}s). Removing..."
      rmdir "$lock_dir" 2>/dev/null || rm -rf "$lock_dir" 2>/dev/null || true
      if mkdir "$lock_dir" 2>/dev/null; then
        LOCK_FILE="$lock_file"
        LOCK_ACQUIRED=true
        log_debug "Lock acquired after stale removal: $lock_dir"
        return 0
      fi
    fi
  fi

  # ロック取得失敗 - LOCK_FILE は設定しない（EXIT trap で他プロセスのロックを解除しないため）
  die "Another instance is running (lock: $lock_dir). Use --recover --resume STATE_FILE to force cleanup."
}

# ロック解放
# Usage: release_lock
# Security: LOCK_ACQUIRED が true の場合のみ解除（他プロセスのロック誤解除防止）
release_lock() {
  # ロック取得に成功していない場合は何もしない
  if [[ "${LOCK_ACQUIRED:-}" != "true" ]]; then
    return 0
  fi

  if [[ -n "${LOCK_FILE:-}" ]]; then
    local lock_dir="${LOCK_FILE}.d"
    if [[ -d "$lock_dir" ]]; then
      rmdir "$lock_dir" 2>/dev/null || rm -rf "$lock_dir" 2>/dev/null || true
      log_debug "Lock released: $lock_dir"
    fi
    LOCK_ACQUIRED=false
  fi
}

# =====================================================
# Recovery Functions (stale state 検出・クリーンアップ)
# =====================================================

# stale state 検出
# Usage: is_state_stale <state_file> [max_age_secs]
# Returns: 0 if stale, 1 if fresh
is_state_stale() {
  local state_file="$1"
  local max_age_secs="${2:-3600}"  # デフォルト1時間

  if [[ ! -f "$state_file" ]]; then
    return 1  # ファイルがなければ stale ではない
  fi

  local updated_at
  updated_at=$(jq -r '.updated_at // empty' "$state_file" 2>/dev/null)

  if [[ -z "$updated_at" ]]; then
    return 0  # updated_at がなければ stale とみなす
  fi

  local now_epoch updated_epoch age_secs
  now_epoch=$(date +%s)

  # macOS と Linux 両対応の日付パース
  # ISO 8601 形式: 2024-01-15T12:34:56.789Z または 2024-01-15T12:34:56Z
  local date_part="${updated_at%.*}"  # 小数点以下を除去
  date_part="${date_part%Z}"          # 末尾の Z を除去

  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: date -j -f を使用（TZ=UTC で UTC として解釈）
    updated_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$date_part" +%s 2>/dev/null || echo 0)
  else
    # Linux: date -d を使用
    updated_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo 0)
  fi

  if [[ $updated_epoch -eq 0 ]]; then
    log_warn "Could not parse updated_at timestamp: $updated_at"
    return 0  # パース失敗は stale とみなす
  fi

  age_secs=$((now_epoch - updated_epoch))

  if [[ $age_secs -gt $max_age_secs ]]; then
    log_warn "State is stale: last updated ${age_secs}s ago (max: ${max_age_secs}s)"
    return 0
  fi

  return 1
}

# リカバリ処理
# Usage: recover_stale_state <state_file>
# Security: 対象パスが TMP_BASE 配下であることを検証
recover_stale_state() {
  local state_file="$1"

  # セキュリティ: state_file が TMP_BASE 配下かつ state.json であることを検証
  local abs_state_file abs_tmp_base
  abs_state_file=$(cd "$(dirname "$state_file")" 2>/dev/null && pwd)/$(basename "$state_file")
  abs_tmp_base=$(cd "$TMP_BASE" 2>/dev/null && pwd)

  if [[ ! "$abs_state_file" == "$abs_tmp_base"/* ]]; then
    die "recover_stale_state: state_file must be under TMP_BASE ($TMP_BASE)"
  fi

  if [[ "$(basename "$state_file")" != "state.json" ]]; then
    die "recover_stale_state: state_file must be named 'state.json'"
  fi

  local task_tmpdir
  task_tmpdir=$(dirname "$state_file")

  log_info "Recovering stale state: $state_file"

  # ロックファイル/ディレクトリを強制削除
  local lock_file="$task_tmpdir/.lock"
  local lock_dir="${lock_file}.d"

  if [[ -d "$lock_dir" ]]; then
    rmdir "$lock_dir" 2>/dev/null || rm -rf "$lock_dir" 2>/dev/null || true
    log_info "Removed stale lock directory: $lock_dir"
  fi

  if [[ -f "$lock_file" ]]; then
    rm -f "$lock_file" 2>/dev/null || true
    log_info "Removed stale lock file: $lock_file"
  fi

  # state.json のステータスを recovered に更新
  if [[ -f "$state_file" ]]; then
    local tmp_file
    tmp_file=$(create_temp_file "state_recover")  # macOS 互換
    local now
    now=$(get_timestamp)

    if jq --arg ts "$now" '.status = "recovered" | .recovered_at = $ts' "$state_file" > "$tmp_file" 2>/dev/null; then
      mv "$tmp_file" "$state_file"
      log_info "State marked as recovered"
    else
      rm -f "$tmp_file" 2>/dev/null || true
      log_warn "Could not update state file"
    fi
  fi

  log_info "Recovery complete. You can now re-run with --resume $state_file"
}

# クリーンアップ関数
cleanup() {
  if [[ "${CLEANUP_DONE:-}" == "true" ]]; then
    return
  fi
  CLEANUP_DONE=true

  log_warn "Signal received, cleaning up..."

  # タスクロックを解放
  release_lock

  # 状態ファイルが初期化されている場合、interrupted 状態を保存
  # Note: ${STATE_FILE:-} で未定義時のエラーを防止（set -u 対策）
  if [[ -n "${STATE_FILE:-}" && -f "$STATE_FILE" ]]; then
    # ロックを解放（もし保持していれば）
    if [[ -n "${STATE_LOCK_FILE:-}" ]]; then
      lock_release "$STATE_LOCK_FILE" 2>/dev/null || true
    fi

    # 状態を interrupted に更新（直接 jq で操作、ロックなし）
    local tmp_file
    tmp_file=$(mktemp)
    local now
    now=$(get_timestamp)
    if jq --arg ts "$now" '.status = "interrupted" | .updated_at = $ts' "$STATE_FILE" > "$tmp_file" 2>/dev/null; then
      mv "$tmp_file" "$STATE_FILE" 2>/dev/null || true
      log_info "State saved as 'interrupted': $STATE_FILE"
    else
      rm -f "$tmp_file" 2>/dev/null || true
    fi
  fi

  log_info "Cleanup completed. You can resume with: --resume $STATE_FILE"
  exit 130  # 標準的なSIGINT終了コード
}

# シグナルトラップ設定
# SIGINT/SIGTERM: 完全クリーンアップ（状態保存 + ロック解放）
# EXIT: ロック解放のみ（die や set -e による中断でもロックを解放）
trap cleanup SIGINT SIGTERM
trap 'release_lock' EXIT

# 注: タイムアウト機能は lib/timeout.sh に移動済み
# timeout_run() を使用してください

# 引数が存在するか確認するヘルパー関数
require_arg() {
  local opt="$1"
  local val="$2"
  if [[ -z "$val" || "$val" == --* ]]; then
    die "Option $opt requires an argument"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan)
        [[ $# -ge 2 ]] || die "Option --plan requires an argument"
        require_arg "--plan" "$2"
        PLAN="$2"; shift 2 ;;
      --phase)
        [[ $# -ge 2 ]] || die "Option --phase requires an argument"
        require_arg "--phase" "$2"
        PHASE="$2"; shift 2 ;;
      --resume)
        [[ $# -ge 2 ]] || die "Option --resume requires an argument"
        require_arg "--resume" "$2"
        RESUME_STATE="$2"; shift 2 ;;
      --status) SHOW_STATUS=true; shift ;;
      --recover) RECOVER_MODE=true; shift ;;
      --reviewers)
        [[ $# -ge 2 ]] || die "Option --reviewers requires an argument"
        require_arg "--reviewers" "$2"
        # セキュリティ: 各レビュワー名を検証（パストラバーサル/インジェクション防止）
        IFS=',' read -ra _reviewers <<< "$2"
        for _r in "${_reviewers[@]}"; do
          _validate_identifier "$_r" "reviewer name"
        done
        REVIEWERS="$2"; shift 2 ;;
      --coder-output)
        [[ $# -ge 2 ]] || die "Option --coder-output requires an argument"
        require_arg "--coder-output" "$2"
        CODER_OUT="$2"; shift 2 ;;
      --gate)
        [[ $# -ge 2 ]] || die "Option --gate requires an argument"
        require_arg "--gate" "$2"
        GATE="$2"; shift 2 ;;
      --run-coder) RUN_CODER=true; shift ;;
      --continue-session) CONTINUE_SESSION=true; shift ;;
      --fork-session) FORK_SESSION=true; shift ;;
      --max-iterations)
        [[ $# -ge 2 ]] || die "Option --max-iterations requires an argument"
        require_arg "--max-iterations" "$2"
        # 正の整数であることを検証
        if [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
          die "--max-iterations must be a positive integer (got: $2)"
        fi
        MAX_ITERATIONS="$2"; shift 2 ;;
      --fix-until)
        [[ $# -ge 2 ]] || die "Option --fix-until requires an argument"
        require_arg "--fix-until" "$2"
        case "$2" in
          high|medium|low|all) FIX_UNTIL="$2" ;;
          *) die "--fix-until must be one of: high, medium, low, all" ;;
        esac
        shift 2 ;;
      --codex-timeout)
        [[ $# -ge 2 ]] || die "Option --codex-timeout requires an argument"
        require_arg "--codex-timeout" "$2"
        # 正の整数であることを検証（上限: 86400秒=24時間）
        if [[ ! "$2" =~ ^[1-9][0-9]*$ ]] || [[ "$2" -gt 86400 ]]; then
          die "--codex-timeout must be a positive integer <= 86400 (got: $2)"
        fi
        CODEX_TIMEOUT="$2"; shift 2 ;;
      --claude-timeout)
        [[ $# -ge 2 ]] || die "Option --claude-timeout requires an argument"
        require_arg "--claude-timeout" "$2"
        # 正の整数であることを検証（上限: 86400秒=24時間）
        if [[ ! "$2" =~ ^[1-9][0-9]*$ ]] || [[ "$2" -gt 86400 ]]; then
          die "--claude-timeout must be a positive integer <= 86400 (got: $2)"
        fi
        CLAUDE_TIMEOUT="$2"; shift 2 ;;
      --agent-strategy)
        [[ $# -ge 2 ]] || die "Option --agent-strategy requires an argument"
        require_arg "--agent-strategy" "$2"
        case "$2" in
          fixed|dynamic) AGENT_STRATEGY="$2" ;;
          *) die "--agent-strategy must be one of: fixed, dynamic" ;;
        esac
        shift 2 ;;
      --max-coders)
        [[ $# -ge 2 ]] || die "Option --max-coders requires an argument"
        require_arg "--max-coders" "$2"
        if [[ ! "$2" =~ ^[1-9][0-9]*$ ]] || [[ "$2" -gt 10 ]]; then
          die "--max-coders must be a positive integer <= 10 (got: $2)"
        fi
        MAX_CODERS="$2"; shift 2 ;;
      --reviewer-strategy)
        [[ $# -ge 2 ]] || die "Option --reviewer-strategy requires an argument"
        require_arg "--reviewer-strategy" "$2"
        case "$2" in
          fixed|auto) REVIEWER_STRATEGY="$2" ;;
          *) die "--reviewer-strategy must be one of: fixed, auto" ;;
        esac
        shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown arg: $1" ;;
    esac
  done

  # 相互排他チェック: --continue-session と --fork-session は同時指定不可
  if [[ "$CONTINUE_SESSION" == "true" ]] && [[ "$FORK_SESSION" == "true" ]]; then
    die "--continue-session and --fork-session are mutually exclusive. Please specify only one."
  fi

  # --resume モードの場合、state.json から設定を読み込む
  if [[ -n "$RESUME_STATE" ]]; then
    if [[ ! -f "$RESUME_STATE" ]]; then
      die "State file not found: $RESUME_STATE"
    fi
    state_load "$RESUME_STATE"

    # --status のみ指定時はサマリー表示して終了
    if [[ "$SHOW_STATUS" == "true" ]]; then
      state_show_summary
      exit 0
    fi

    # state.json から PLAN, PHASE を復元
    PLAN=$(state_get '.task.plan_path')
    # 現在の running フェーズを探す
    local running_phase
    running_phase=$(jq -r '.phases[] | select(.status == "running" or .status == "review" or .status == "fixing") | .name' "$RESUME_STATE" | head -1)
    if [[ -n "$running_phase" ]]; then
      PHASE="$running_phase"
    else
      # running がなければ最後の pending を使う
      PHASE=$(jq -r '.phases[] | select(.status == "pending") | .name' "$RESUME_STATE" | head -1)
    fi

    log_info "Resuming from state: $RESUME_STATE"
    log_info "  Plan: $PLAN"
    log_info "  Phase: $PHASE"

    # セッション継続/分岐オプション処理
    if [[ "$CONTINUE_SESSION" == "true" ]] || [[ "$FORK_SESSION" == "true" ]]; then
      # 前回のセッションIDを取得
      SESSION_ID=$(session_get_last "$PHASE")
      if [[ -n "$SESSION_ID" ]]; then
        log_info "  Previous session: $SESSION_ID"
        if [[ "$FORK_SESSION" == "true" ]]; then
          log_info "  Mode: Fork (creating new branch from previous session)"
        else
          log_info "  Mode: Continue (resuming previous session)"
        fi
      else
        log_warn "No previous session found for phase: $PHASE"
        log_info "Will start a new session instead"
        CONTINUE_SESSION=false
        FORK_SESSION=false
      fi
    fi
  else
    # --recover モードの場合は --resume が必須（--plan/--phase は不要）
    if [[ "$RECOVER_MODE" == "true" ]]; then
      die "--recover requires --resume to specify the state file"
    fi

    # 新規実行時は --plan と --phase が必須
    [[ -n "$PLAN" ]] || die "--plan is required (or use --resume)"
    [[ -n "$PHASE" ]] || die "--phase is required (or use --resume)"
    [[ -f "$PLAN" ]] || die "plan not found: $PLAN"
  fi
}

# Note: _validate_identifier() is defined in lib/utils.sh

# ClaudeCode CLIでCoderを起動（セッション対応版）
run_coder() {
  local tmpdir="$1"
  local phase="$2"
  local plan="$3"

  # プロンプトインジェクション防止: phase を検証
  _validate_identifier "$phase" "phase"

  local outfile="$tmpdir/${phase}_coder.md"
  local new_session_id=""

  log_info "Running Coder (ClaudeCode) for phase: $phase"

  # セッションモードに応じた実行
  if [[ "$FORK_SESSION" == "true" ]] && [[ -n "$SESSION_ID" ]]; then
    # セッション分岐
    log_info "Forking from session: $SESSION_ID"
    local fork_prompt
    fork_prompt=$(coder_build_prompt "$plan" "$phase" "Forked from session: $SESSION_ID")
    new_session_id=$(coder_fork "$SESSION_ID" "$fork_prompt" "$outfile")
  elif [[ "$CONTINUE_SESSION" == "true" ]] && [[ -n "$SESSION_ID" ]]; then
    # セッション継続
    log_info "Continuing session: $SESSION_ID"
    local resume_prompt
    resume_prompt=$(coder_build_prompt "$plan" "$phase" "Resuming session: $SESSION_ID")
    if coder_resume "$SESSION_ID" "$resume_prompt" "$outfile"; then
      new_session_id="$SESSION_ID"
    else
      log_warn "Session resume failed, starting new session"
      new_session_id=$(coder_run "$plan" "$phase" "$outfile")
    fi
  else
    # 新規セッション
    new_session_id=$(coder_run "$plan" "$phase" "$outfile")
  fi

  # セッションIDを更新
  if [[ -n "$new_session_id" ]]; then
    SESSION_ID="$new_session_id"
    # state.json に記録
    coder_record_to_state "$phase" "$new_session_id" "$outfile"
    log_info "Session recorded: $new_session_id"
  fi

  log_info "Coder output saved: $outfile"
  echo "$outfile"
}

# =====================================================
# Batch Review Functions (Codex推奨設計)
# =====================================================

# ロック付きでコマンドを実行
# Usage: _with_queue_lock <command> [args...]
_with_queue_lock() {
  local lock_dir="${REVIEW_QUEUE_LOCK}.d"
  local max_attempts=50
  local attempt=0

  mkdir -p "$(dirname "$REVIEW_QUEUE_LOCK")"

  # mkdir による簡易ロック（macOS/Linux両対応）
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
      log_error "Could not acquire queue lock after ${max_attempts} attempts"
      return 1
    fi
    sleep 0.1
  done

  # コマンド実行
  "$@"
  local ret=$?

  # ロック解放
  rmdir "$lock_dir" 2>/dev/null || true
  return $ret
}

# レビューキューの状態を確認
# Returns: 0 if pending review exists, 1 otherwise
review_queue_has_pending() {
  if [[ ! -f "$REVIEW_QUEUE_FILE" ]]; then
    return 1
  fi
  local pending
  pending=$(jq -r '.pending_review // false' "$REVIEW_QUEUE_FILE" 2>/dev/null || echo "false")
  [[ "$pending" == "true" ]]
}

# レビューキューから変更ファイル一覧を取得
# Returns: newline-separated list of files
review_queue_get_files() {
  if [[ ! -f "$REVIEW_QUEUE_FILE" ]]; then
    return 0
  fi
  jq -r '.changed_files[]? // empty' "$REVIEW_QUEUE_FILE" 2>/dev/null || true
}

# レビューキューをクリア（内部関数）
_review_queue_clear_internal() {
  if [[ -f "$REVIEW_QUEUE_FILE" ]]; then
    echo '{"pending_review":false,"changed_files":[],"last_change":""}' > "$REVIEW_QUEUE_FILE"
    log_info "Review queue cleared"
  fi
}

# レビューキューをクリア（ロック付き）
review_queue_clear() {
  _with_queue_lock _review_queue_clear_internal
}

# git diff スナップショットを作成（キュー対象ファイルのみ）
# Usage: review_create_diff_snapshot <output_file>
# Returns: 0 on success (diff exists), 1 on no changes
review_create_diff_snapshot() {
  local output_file="$1"
  local diff_content=""

  # キューから対象ファイル一覧を取得
  local queued_files
  queued_files=$(review_queue_get_files)

  if [[ -z "$queued_files" ]]; then
    log_info "No files in queue to review"
    return 1
  fi

  # 未追跡ファイルを git add -N で intent-to-add（実際には追加しない）
  local file
  while IFS= read -r file; do
    if [[ -n "$file" ]] && [[ -f "$file" ]]; then
      # 未追跡ファイルの場合のみ intent-to-add
      if ! git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
        git add -N "$file" 2>/dev/null || true
      fi
    fi
  done <<< "$queued_files"

  # キュー対象ファイルのみの diff を取得
  # セキュリティ: 機密ファイルが混入しないよう、キューに登録されたファイルのみ
  local files_array=()
  while IFS= read -r file; do
    if [[ -n "$file" ]]; then
      files_array+=("$file")
    fi
  done <<< "$queued_files"

  if [[ ${#files_array[@]} -gt 0 ]]; then
    diff_content=$(git diff HEAD -- "${files_array[@]}" 2>/dev/null || true)
  fi

  if [[ -z "$diff_content" ]]; then
    log_info "No changes to review in queued files"
    return 1
  fi

  # スナップショットをファイルに保存
  printf '%s\n' "$diff_content" > "$output_file"
  log_info "Diff snapshot created: $output_file ($(wc -l < "$output_file") lines, ${#files_array[@]} files)"
  return 0
}

# バッチレビューを実行（フェーズ完了時に呼ばれる）
# Usage: run_batch_review <tmpdir> <phase>
# Returns: path to aggregated review file
run_batch_review() {
  local tmpdir="$1"
  local phase="$2"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  log_info "=== Running Batch Review (Phase: $phase) ==="

  # レビューキューを確認
  if ! review_queue_has_pending; then
    log_info "No pending reviews in queue"
    return 0
  fi

  # スナップショット作成
  local snapshot_file="$tmpdir/${phase}_diff_snapshot_${timestamp}.patch"
  if ! review_create_diff_snapshot "$snapshot_file"; then
    review_queue_clear
    return 0
  fi

  # レビュープロンプト作成
  local review_prompt_file="$tmpdir/${phase}_batch_review_prompt.md"
  local queued_files
  queued_files=$(review_queue_get_files)

  # 変更ファイルリストを事前構築（コマンドインジェクション対策）
  local formatted_files
  formatted_files=$(printf '%s\n' "$queued_files" | sed 's/^/  - /')

  # ヒアドキュメント内でのコマンド置換を避けるため、静的部分と動的部分を分離
  # 静的ヘッダー部分（展開なし）
  cat > "$review_prompt_file" <<'EOF'
# Batch Code Review Request

## Review Context
EOF

  # 動的なメタデータ部分（変数展開のみ、コマンド置換なし）
  {
    printf '%s\n' "- Phase: $phase"
    printf '%s\n' "- Timestamp: $timestamp"
    printf '%s\n' "- Changed files:"
    printf '%s\n' "$formatted_files"
  } >> "$review_prompt_file"

  # 静的な中間部分（展開なし）
  cat >> "$review_prompt_file" <<'EOF'

## Review Focus
Please review the following git diff for:
1. **[High] Security Issues**: Injection vulnerabilities, credential exposure, unsafe operations
2. **[High] Critical Bugs**: Logic errors, race conditions, data loss risks
3. **[Medium] Design Issues**: Architecture problems, poor abstractions, maintainability concerns
4. **[Medium] Error Handling**: Missing or inadequate error handling
5. **[Low] Code Quality**: Style, naming, documentation

## Output Format
For each issue found:
```
[Severity] Category: Brief description
  File: <path>
  Line: <number or range>
  Issue: <detailed explanation>
  Suggestion: <how to fix>
```

If no issues are found, respond with: "No issues found."

## Git Diff
```diff
EOF

  # diff内容を安全に追記（catの出力を直接書き込み、コマンド置換を回避）
  cat "$snapshot_file" >> "$review_prompt_file"

  # 閉じフェンスを追記
  printf '%s\n' '```' >> "$review_prompt_file"

  # Codex レビュー実行
  local review_output="$tmpdir/${phase}_batch_review_${timestamp}.md"

  log_info "Running Codex batch review (timeout: ${CODEX_TIMEOUT}s)..."

  if timeout_run "$CODEX_TIMEOUT" _run_codex_with_redirect "$review_prompt_file" "$review_output"; then
    log_info "Batch review completed: $review_output"
  else
    local ret=$?
    if [[ $ret -eq 124 ]]; then
      log_warn "Batch review timed out after ${CODEX_TIMEOUT}s"
      echo "[TIMEOUT] Batch review timed out after ${CODEX_TIMEOUT}s" > "$review_output"
    else
      log_warn "Batch review returned non-zero: $ret"
    fi
  fi

  # キューをクリア
  review_queue_clear

  # クリーンアップ
  rm -f "$review_prompt_file"

  echo "$review_output"
}

# レビュー結果からブロッカー（High重大度）を検出
has_blockers() {
  local reviews_file="$1"
  if [[ ! -f "$reviews_file" ]]; then
    return 1
  fi
  # [High] タグを検索
  grep -qi '\[High\]' "$reviews_file" 2>/dev/null
}

# レビュー結果から指定レベルまでの問題を検出
# Usage: has_issues <reviews_file> <level>
# level: high, medium, low, all
# Returns: 0 if issues found, 1 if no issues found
# Note: dies if file doesn't exist (that's an error, not "no issues")
has_issues() {
  local reviews_file="$1"
  local level="${2:-high}"

  if [[ -z "$reviews_file" ]]; then
    die "has_issues: reviews_file is required"
  fi

  if [[ ! -f "$reviews_file" ]]; then
    die "has_issues: reviews file not found: $reviews_file"
  fi

  if [[ ! -r "$reviews_file" ]]; then
    die "has_issues: cannot read reviews file: $reviews_file"
  fi

  local ret=1  # デフォルト: 問題なし
  case "$level" in
    high)
      grep -qi '\[High\]' "$reviews_file" 2>/dev/null && ret=0
      ;;
    medium)
      grep -qiE '\[High\]|\[Medium\]' "$reviews_file" 2>/dev/null && ret=0
      ;;
    low|all)
      grep -qiE '\[High\]|\[Medium\]|\[Low\]' "$reviews_file" 2>/dev/null && ret=0
      ;;
    *)
      log_warn "has_issues: unknown level: $level, defaulting to high"
      grep -qi '\[High\]' "$reviews_file" 2>/dev/null && ret=0
      ;;
  esac

  # タグフォーマット警告（戻り値に影響しない）
  if [[ $ret -ne 0 ]]; then
    if ! grep -qiE '\[High\]|\[Medium\]|\[Low\]|No issues found' "$reviews_file" 2>/dev/null; then
      log_warn "has_issues: Review file may have non-standard format. Expected [High]/[Medium]/[Low] tags."
    fi
  fi

  return $ret
}

# 重大度別カウントを取得してログ出力
# Usage: show_issue_counts <reviews_file>
show_issue_counts() {
  local reviews_file="$1"

  if [[ ! -f "$reviews_file" ]]; then
    return
  fi

  local high_count medium_count low_count
  high_count=$(grep -ci '\[High\]' "$reviews_file" 2>/dev/null || echo 0)
  medium_count=$(grep -ci '\[Medium\]' "$reviews_file" 2>/dev/null || echo 0)
  low_count=$(grep -ci '\[Low\]' "$reviews_file" 2>/dev/null || echo 0)

  log_info "Issue counts: [High]=$high_count [Medium]=$medium_count [Low]=$low_count"
}

# エスカレーションレポート生成
# Usage: generate_escalation_report <tmpdir> <phase> <reviews_file> <iteration>
# Returns: レポートファイルパス
generate_escalation_report() {
  local tmpdir="$1"
  local phase="$2"
  local reviews_file="$3"
  local iteration="$4"
  local timestamp
  timestamp=$(date -u +"%Y%m%dT%H%M%SZ")  # ファイル名用

  local report_file="$tmpdir/${phase}_escalation_report_${timestamp}.md"

  # Issue counts 事前計算
  local high_count=0 medium_count=0 low_count=0
  if [[ -f "$reviews_file" && -r "$reviews_file" ]]; then
    high_count=$(grep -ci '\[High\]' "$reviews_file" 2>/dev/null || echo 0)
    medium_count=$(grep -ci '\[Medium\]' "$reviews_file" 2>/dev/null || echo 0)
    low_count=$(grep -ci '\[Low\]' "$reviews_file" 2>/dev/null || echo 0)
  fi

  {
    printf "# Escalation Report\n\n"
    printf "## Quick Summary\n"
    printf "| Severity | Count |\n"
    printf "|----------|-------|\n"
    printf "| [High]   | %d    |\n" "$high_count"
    printf "| [Medium] | %d    |\n" "$medium_count"
    printf "| [Low]    | %d    |\n\n" "$low_count"
    printf "## Context\n"
    printf "- **Phase**: %s\n" "$phase"
    printf "- **Iterations Attempted**: %s / %s\n" "$iteration" "$MAX_ITERATIONS"
    printf "- **Timestamp**: %s\n" "$(get_timestamp)"
    printf "- **Status**: FAILED - Issues remain after maximum iterations\n\n"
    printf "## State Information\n"
    printf "- **State File**: %s\n" "$STATE_FILE"
    printf "- **Plan File**: %s\n" "$PLAN"
    printf "- **Coder Output**: %s\n\n" "${CODER_OUT:-N/A}"
    printf "## Git Status\n"
    printf '```\n'
    git status --porcelain 2>/dev/null || printf "(git status unavailable)\n"
    printf '```\n\n'
    printf "## Git Diff Summary\n"
    printf '```\n'
    git diff --stat HEAD 2>/dev/null || printf "(git diff unavailable)\n"
    printf '```\n\n'
    printf "## Remaining Issues\n"
    if [[ -f "$reviews_file" && -r "$reviews_file" ]]; then
      cat "$reviews_file"
    else
      printf "(Reviews file not readable: %s)\n" "$reviews_file"
    fi
    printf "\n## Recommendation\n"
    printf "Human intervention required. Possible causes:\n"
    printf "1. Structural/architectural issues that cannot be auto-fixed\n"
    printf "2. Conflicting requirements\n"
    printf "3. Issues outside the scope of automated fixes\n"
  } > "$report_file"

  log_info "Escalation report generated: $report_file"
  echo "$report_file"
}

# 修正要求プロンプトを生成してCoderに再投入（セッション対応版）
run_fix_iteration() {
  local tmpdir="$1"
  local phase="$2"
  local plan="$3"
  local reviews="$4"
  local iteration="$5"
  local outfile="$tmpdir/${phase}_coder_fix${iteration}.md"

  log_info "Running fix iteration $iteration (fix-until: $FIX_UNTIL)..."

  local new_session_id=""

  # coder.sh の関数を使用してセッション継続で修正実行（7番目のパラメータにFIX_UNTILを追加）
  new_session_id=$(coder_run_fix "$plan" "$phase" "$reviews" "$iteration" "$outfile" "$SESSION_ID" "$FIX_UNTIL")

  # セッションIDを更新
  if [[ -n "$new_session_id" ]]; then
    SESSION_ID="$new_session_id"
    # state.json に記録（修正イテレーションとして）
    coder_record_to_state "$phase" "$new_session_id" "$outfile"
    log_info "Fix session recorded: $new_session_id (iteration: $iteration)"
  fi

  log_info "Fix output saved: $outfile"
  echo "$outfile"
}

# codex実行ラッパー（リダイレクト付き）
# Usage: _run_codex_with_redirect <input_file> <output_file>
# 注意: CODEX_WRAPPER 経由で呼び出すことで、モデル設定が強制的に適用される
# 重要: ラッパーが存在しない場合はエラー終了（直接呼び出しは禁止）
_run_codex_with_redirect() {
  local input_file="$1"
  local output_file="$2"

  # ラッパー存在確認（必須：直接呼び出しは禁止）
  if [[ ! -x "$CODEX_WRAPPER_HIGH" ]]; then
    log_error "codex-wrapper-high.sh not found or not executable: $CODEX_WRAPPER_HIGH"
    log_error "Direct codex calls are not allowed. Please ensure codex-wrapper-high.sh exists."
    echo "[ERROR] codex-wrapper-high.sh not found" > "$output_file"
    return 1
  fi

  "$CODEX_WRAPPER_HIGH" --stdin < "$input_file" > "$output_file" 2>&1
}

# レビュワー実行（reviewer.sh の関数を使用、state.json に記録）
# Usage: run_reviewers <tmpdir> <phase> <coder_out> [suffix] [iteration]
# Returns: aggregated reviews file path (stdout), exit 1 on complete failure
run_reviewers() {
  local tmpdir="$1"
  local phase="$2"
  local coder_out="$3"
  local suffix="${4:-}"
  local iteration="${5:-1}"

  log_info "Running reviewers: $REVIEWERS (fix-until: $FIX_UNTIL)"

  # reviewer.sh の reviewer_run_all() を使用
  # task_tmpdir を渡してセッション継続を有効化
  local agg_file
  local reviewer_exit=0
  agg_file=$(reviewer_run_all "$REVIEWERS" "$coder_out" "$tmpdir" "$phase" "$suffix" "$CODEX_TIMEOUT" "$tmpdir") || reviewer_exit=$?

  # 全レビュワー失敗時はエラー
  if [[ $reviewer_exit -ne 0 ]]; then
    log_error "All reviewers failed. Cannot proceed with review cycle."
    state_set_error "REVIEWER_FAILED" "All reviewers failed" "$phase"
    state_save
    return 1
  fi

  # 集約ファイルの存在確認
  if [[ -z "$agg_file" || ! -f "$agg_file" ]]; then
    log_error "Aggregated reviews file not found: $agg_file"
    state_set_error "REVIEWER_FAILED" "Aggregated reviews file not found" "$phase"
    state_save
    return 1
  fi

  # 重大度別カウントを表示
  show_issue_counts "$agg_file"

  # state.json に記録（reviewer_record_to_stateはstateを変更するが保存しない）
  reviewer_record_to_state "$phase" "$iteration" "$agg_file"
  state_save  # 一括保存

  echo "$agg_file"
}

main() {
  parse_args "$@"

  # --recover モードの処理（他の処理より先に実行）
  if [[ "$RECOVER_MODE" == "true" ]]; then
    if [[ -z "$RESUME_STATE" ]]; then
      die "--recover requires --resume to specify the state file"
    fi

    if [[ ! -f "$RESUME_STATE" ]]; then
      die "State file not found: $RESUME_STATE"
    fi

    recover_stale_state "$RESUME_STATE"
    exit 0
  fi

  # 通常実行時: stale チェック（--resume 指定時のみ）
  if [[ -n "$RESUME_STATE" && -f "$RESUME_STATE" ]]; then
    if is_state_stale "$RESUME_STATE"; then
      die "State file appears stale (not updated for over 1 hour). Use --recover --resume STATE_FILE to cleanup, or delete the state file manually."
    fi
  fi

  local task
  task="$(basename "$PLAN")"
  task="${task%.*}"
  local tmpdir="$TMP_BASE/$task"
  mkdir -p "$tmpdir"

  # ロック取得（同時実行防止）
  acquire_lock "$tmpdir"

  # State 初期化（新規実行時のみ）
  if [[ -z "$RESUME_STATE" ]]; then
    state_init "$PLAN" "$task" "$tmpdir"
    state_upsert_phase "$PHASE" "$MAX_ITERATIONS"
  fi

  # 全体ステータスを running に
  state_set '.status' '"running"'
  state_set_phase_status "$PHASE" "running"
  state_save

  if [[ -z "$CODER_OUT" ]]; then
    CODER_OUT="$tmpdir/${PHASE}_coder.md"
  fi

  # --run-coder が指定されている場合はCoderを起動
  if [[ "$RUN_CODER" == "true" ]] && [[ ! -f "$CODER_OUT" ]]; then
    # 動的エージェント戦略（--agent-strategy dynamic の場合）
    if [[ "$AGENT_STRATEGY" == "dynamic" ]]; then
      log_info "Using dynamic agent strategy..."
      local recommended_coders
      recommended_coders=$(coder_log_strategy "$PLAN" "$MAX_CODERS")

      # Note: 現時点では単一Coderのみサポート
      # 将来の拡張で複数Coderの並列実行をサポート予定
      if [[ $recommended_coders -gt 1 ]]; then
        log_info "Multiple coders recommended ($recommended_coders), but currently using single coder"
        log_info "Parallel coder execution will be available in a future release"
      fi
    fi

    CODER_OUT=$(run_coder "$tmpdir" "$PHASE" "$PLAN")
    # 注: セッション情報は run_coder() 内で coder_record_to_state() により記録済み
    state_save

    # Coder完了後にバッチレビューを実行（キューに蓄積された変更をレビュー）
    if command -v codex >/dev/null 2>&1; then
      local batch_review_result
      batch_review_result=$(run_batch_review "$tmpdir" "$PHASE")
      if [[ -n "$batch_review_result" ]] && [[ -f "$batch_review_result" ]]; then
        log_info "Batch review saved: $batch_review_result"
        # バッチレビュー結果にブロッカーがあればログ出力
        if has_blockers "$batch_review_result"; then
          log_warn "Batch review found blockers. See: $batch_review_result"
        fi
      fi
    fi
  fi

  if [[ ! -f "$CODER_OUT" ]]; then
    cat <<EOF
[HINT] Coder 出力が見つかりません: $CODER_OUT
次のいずれかを実行してください:
  1) --run-coder オプションを追加して自動起動
  2) ClaudeCode に以下を渡し、結果を手動保存:
     - プロンプト: docs/prompts/coder_phase_${PHASE}.md
     - 保存先: $CODER_OUT
EOF
    state_set '.status' '"paused"'
    state_save
    exit 0
  fi

  # Run reviewers
  if ! command -v codex >/dev/null 2>&1; then
    log_warn "codex CLI が見つかりません。レビュー反復をスキップします。"
  else
    local current_coder_out="$CODER_OUT"
    local iteration=0
    local reviews_file
    local phase_idx
    phase_idx=$(state_find_phase "$PHASE")

    log_info "Fix-until level: $FIX_UNTIL (will iterate until no [$FIX_UNTIL] or higher issues remain)"

    # =====================================================
    # レビュー完了保証ループ
    # =====================================================
    # 保証事項:
    #   1. 各イテレーションは必ずレビューで開始
    #   2. 問題がなければ即座にSUCCESS終了
    #   3. 最大イテレーション到達時は最終レビュー後にFAIL
    #   4. 修正は1〜(MAX-1)回目のイテレーション後にのみ実行
    #
    # フロー例 (MAX_ITERATIONS=5):
    #   iter 1: レビュー → 問題あり → 修正
    #   iter 2: レビュー → 問題あり → 修正
    #   iter 3: レビュー → 問題あり → 修正
    #   iter 4: レビュー → 問題あり → 修正
    #   iter 5: レビュー → 問題あり → ESCALATION (FAIL)
    #         or レビュー → 問題なし → SUCCESS
    # =====================================================
    while [[ $iteration -lt $MAX_ITERATIONS ]]; do
      iteration=$((iteration + 1))
      log_info "=== Review Iteration $iteration / $MAX_ITERATIONS (fix-until: $FIX_UNTIL) ==="

      # イテレーション番号を state に記録
      state_set ".phases[$phase_idx].iteration" "$iteration"
      state_set_phase_status "$PHASE" "review"
      state_save

      local suffix=""
      [[ $iteration -gt 1 ]] && suffix="_iter${iteration}"

      # 動的レビュワー選択（--reviewer-strategy auto の場合）
      if [[ "$REVIEWER_STRATEGY" == "auto" ]]; then
        log_info "Using dynamic reviewer selection..."
        REVIEWERS=$(reviewer_select_dynamic "$current_coder_out")
        log_info "Selected reviewers: $REVIEWERS"
      fi

      # イテレーション番号を run_reviewers に渡す
      local run_reviewers_exit=0
      reviews_file=$(run_reviewers "$tmpdir" "$PHASE" "$current_coder_out" "$suffix" "$iteration") || run_reviewers_exit=$?

      # レビュワー実行失敗時はループ終了
      if [[ $run_reviewers_exit -ne 0 ]]; then
        log_error "Reviewers failed. Exiting review cycle."
        state_set_phase_status "$PHASE" "failed"
        state_save
        break
      fi

      # 指定レベルまでの問題がなくなったかチェック
      if ! has_issues "$reviews_file" "$FIX_UNTIL"; then
        log_info "No issues found at level [$FIX_UNTIL] or higher. Review cycle complete."
        state_set_phase_status "$PHASE" "completed"
        state_save
        break
      fi

      if [[ $iteration -ge $MAX_ITERATIONS ]]; then
        log_error "=============================================="
        log_error "ESCALATION: Max iterations ($MAX_ITERATIONS) reached"
        log_error "Issues remain at level [$FIX_UNTIL]"
        log_error "=============================================="

        # エスカレーションレポート生成
        local escalation_report
        escalation_report=$(generate_escalation_report "$tmpdir" "$PHASE" "$reviews_file" "$iteration")

        log_error ""
        log_error ">>> HUMAN INTERVENTION REQUIRED <<<"
        log_error "Escalation report: $escalation_report"
        show_issue_counts "$reviews_file"

        # ステータス更新
        state_set_phase_status "$PHASE" "escalated"
        state_set_error "ESCALATION" "Human intervention required (report: $escalation_report)" "$PHASE"
        state_set ".phases[$(state_find_phase \"$PHASE\")].escalation_report" "\"$escalation_report\""
        state_set '.status' '"failed"'
        state_save
        break
      fi

      # 修正要求を Coder に再投入
      if [[ "$RUN_CODER" == "true" ]]; then
        state_set_phase_status "$PHASE" "fixing"
        state_save

        log_info "Issues found. Running fix iteration..."
        current_coder_out=$(run_fix_iteration "$tmpdir" "$PHASE" "$PLAN" "$reviews_file" "$iteration")

        # 修正後にバッチレビューを実行
        local fix_batch_review
        fix_batch_review=$(run_batch_review "$tmpdir" "$PHASE")
        if [[ -n "$fix_batch_review" ]] && [[ -f "$fix_batch_review" ]]; then
          log_info "Fix batch review saved: $fix_batch_review"
        fi
      else
        log_info "Issues detected at level [$FIX_UNTIL]. Manual fix required."
        log_info "Reviews: $reviews_file"
        state_set '.status' '"paused"'
        state_save
        break
      fi
    done
  fi

  # Quality gate
  if [[ -n "$GATE" ]]; then
    state_set '.quality_gate.level' "\"$GATE\""
    state_set '.quality_gate.status' '"running"'
    state_save
    if [[ -x "$QUALITY_GATE" ]]; then
      log_info "Running quality gate: $GATE"
      if "$QUALITY_GATE" --level "$GATE"; then
        state_set '.quality_gate.status' '"passed"'
      else
        state_set '.quality_gate.status' '"failed"'
      fi
    else
      log_warn "quality_gate.sh not executable or missing: $QUALITY_GATE"
      state_set '.quality_gate.status' '"skipped"'
    fi
    state_save
  fi

  # 完了ステータス設定（paused の場合は上書きしない）
  local current_status
  current_status=$(state_get '.status')
  if [[ "$current_status" != "paused" ]]; then
    local final_status="completed"
    local phase_status
    phase_status=$(state_get ".phases[$(state_find_phase "$PHASE")].status")

    # failed AND escalated を確認
    if [[ "$phase_status" == "failed" || "$phase_status" == "escalated" ]]; then
      final_status="failed"
    fi

    state_set '.status' "\"$final_status\""
    state_save
  fi

  # ロック解放（正常終了時）
  release_lock

  log_info "=== Orchestration Complete ==="
  log_info "Outputs in: $tmpdir"
  log_info "State file: $STATE_FILE"
}

main "$@"
