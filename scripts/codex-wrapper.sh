#!/usr/bin/env bash
#
# codex-wrapper.sh - Codex CLI ラッパー（モデル強制固定）
#
# 目的:
#   ClaudeCode や他のエージェントが誤ったモデルを指定しても、
#   正しいモデル設定が強制的に適用されるようにする。
#
# 使用方法:
#   cat prompt.md | ./scripts/codex-wrapper.sh --stdin > output.md
#   ./scripts/codex-wrapper.sh --stdin < input.md > output.md
#
# 注意:
#   - このラッパー経由でのみ codex を呼び出すこと
#   - 直接 codex exec を呼ぶと、モデル設定が上書きされる可能性がある
#
set -euo pipefail

# =====================================================
# 固定モデル設定（この値が常に適用される）
# =====================================================
readonly FIXED_MODEL="gpt-5.3-codex"
readonly FIXED_REASONING_EFFORT="xhigh"

# =====================================================
# ログ出力
# =====================================================
log_info() {
  echo "[codex-wrapper] INFO: $*" >&2
}

log_warn() {
  echo "[codex-wrapper] WARN: $*" >&2
}

# =====================================================
# 引数から -c model=... と -c model_reasoning_effort=... を除去
# --stdin フラグを検出
# =====================================================
# グローバル配列変数（filter_args の出力先）
FILTERED_ARGS=()
HAS_STDIN_FLAG=false

filter_args() {
  FILTERED_ARGS=()
  HAS_STDIN_FLAG=false
  local skip_next=false

  for arg in "$@"; do
    if [[ "$skip_next" == "true" ]]; then
      # 前の引数が -c だった場合、model= または model_reasoning_effort= をスキップ
      if [[ "$arg" == model=* ]] || [[ "$arg" == model_reasoning_effort=* ]]; then
        log_warn "Blocked override attempt: -c $arg"
        skip_next=false
        continue
      fi
      # それ以外の -c オプションは許可
      FILTERED_ARGS+=("-c" "$arg")
      skip_next=false
      continue
    fi

    if [[ "$arg" == "-c" ]]; then
      skip_next=true
      continue
    fi

    # -c key=value 形式（スペースなし）の場合
    if [[ "$arg" == -c* ]]; then
      local value="${arg#-c}"
      if [[ "$value" == model=* ]] || [[ "$value" == model_reasoning_effort=* ]]; then
        log_warn "Blocked override attempt: $arg"
        continue
      fi
      FILTERED_ARGS+=("$arg")
      continue
    fi

    # --stdin フラグを検出（- に変換してフラグをセット）
    if [[ "$arg" == "--stdin" ]]; then
      FILTERED_ARGS+=("-")
      HAS_STDIN_FLAG=true
      continue
    fi

    FILTERED_ARGS+=("$arg")
  done

  # skip_next が true のまま終わった場合（-c が最後の引数だった）
  if [[ "$skip_next" == "true" ]]; then
    log_warn "Dangling -c option ignored"
  fi
}

# =====================================================
# メイン処理
# =====================================================
main() {
  # codex CLI の存在確認
  if ! command -v codex >/dev/null 2>&1; then
    echo "[codex-wrapper] ERROR: codex CLI not found in PATH" >&2
    exit 1
  fi

  # コマンドの種類を判定（resume or exec）
  local cmd_type="exec"
  local session_id=""
  local resume_prompt=""
  local remaining_args=()

  # 引数をパース
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --resume)
        cmd_type="resume"
        shift
        if [[ $# -gt 0 && "$1" != --* ]]; then
          session_id="$1"
          shift
        fi
        if [[ $# -gt 0 && "$1" != --* ]]; then
          resume_prompt="$1"
          shift
        fi
        ;;
      *)
        remaining_args+=("$1")
        shift
        ;;
    esac
  done

  # 引数をフィルタリング（グローバル配列 FILTERED_ARGS にセット）
  filter_args "${remaining_args[@]}"

  # ログ出力（監査用）
  log_info "Model: ${FIXED_MODEL}"
  log_info "Reasoning Effort: ${FIXED_REASONING_EFFORT}"

  if [[ "$cmd_type" == "resume" ]]; then
    # resume モード
    if [[ -z "$session_id" ]]; then
      echo "[codex-wrapper] ERROR: --resume requires session_id" >&2
      exit 1
    fi
    log_info "Command: resume (session: $session_id)"

    # --stdin が指定されていた場合の警告
    if [[ "$HAS_STDIN_FLAG" == "true" ]]; then
      log_warn "--stdin is ignored in resume mode (codex resume does not support stdin input)"
    fi

    # codex resume 実行（固定設定を強制適用）
    # 注意: FILTERED_ARGS から "-" を除外（resumeモードでは無効）
    local resume_args=()
    for arg in "${FILTERED_ARGS[@]}"; do
      if [[ "$arg" != "-" ]]; then
        resume_args+=("$arg")
      fi
    done

    exec codex resume "$session_id" "$resume_prompt" \
      -c "model=${FIXED_MODEL}" \
      -c "model_reasoning_effort=${FIXED_REASONING_EFFORT}" \
      "${resume_args[@]}"
  else
    # exec モード（デフォルト）
    log_info "Command: exec"

    # codex 実行（固定設定を強制適用）
    exec codex exec \
      -c "model=${FIXED_MODEL}" \
      -c "model_reasoning_effort=${FIXED_REASONING_EFFORT}" \
      "${FILTERED_ARGS[@]}"
  fi
}

main "$@"
