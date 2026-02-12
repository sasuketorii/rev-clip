#!/usr/bin/env bash
#
# codex-wrapper-xhigh.sh - Codex CLI ラッパー（Reviewer用: xhigh effort）
#
# 目的:
#   Reviewerタスク用のCodex呼び出し。reasoning effort = xhigh で実行。
#   レビューの品質を最大化するため、最高の推論レベルを使用。
#
# 使用方法:
#   cat prompt.md | ./scripts/codex-wrapper-xhigh.sh --stdin > output.md
#
# 使い分け:
#   - Coder（実装）: codex-wrapper-high.sh
#   - Reviewer（レビュー）: codex-wrapper-xhigh.sh (このファイル)
#
set -euo pipefail

# =====================================================
# 固定モデル設定
# =====================================================
readonly FIXED_MODEL="gpt-5.3-codex"
readonly FIXED_REASONING_EFFORT="xhigh"  # Reviewer用: xhigh

# =====================================================
# ログ出力
# =====================================================
log_info() {
  echo "[codex-wrapper-xhigh] INFO: $*" >&2
}

log_warn() {
  echo "[codex-wrapper-xhigh] WARN: $*" >&2
}

# =====================================================
# 引数から -c model=... と -c model_reasoning_effort=... を除去
# --stdin フラグを検出
# リダイレクト文字列の混入を検出（呼び出し側の bash -c ラップ忘れ防御）
# =====================================================
FILTERED_ARGS=()
HAS_STDIN_FLAG=false

filter_args() {
  FILTERED_ARGS=()
  HAS_STDIN_FLAG=false
  local skip_next=false

  for arg in "$@"; do
    # リダイレクト文字列の混入検出
    # bash -c でラップせずにバックグラウンド実行すると、
    # 2> や >> がシェル構文ではなく codex の引数として渡されることがある
    if [[ "$arg" =~ ^(2?\>\>?|2\>\&1)$ ]]; then
      log_warn "Redirect operator detected as argument: '$arg'"
      log_warn "This likely means the caller forgot to wrap the command with 'bash -c \"...\"'"
      log_warn "Skipping this argument to prevent codex misinterpretation"
      continue
    fi

    if [[ "$skip_next" == "true" ]]; then
      if [[ "$arg" == model=* ]] || [[ "$arg" == model_reasoning_effort=* ]]; then
        log_warn "Blocked override attempt: -c $arg"
        skip_next=false
        continue
      fi
      FILTERED_ARGS+=("-c" "$arg")
      skip_next=false
      continue
    fi

    if [[ "$arg" == "-c" ]]; then
      skip_next=true
      continue
    fi

    if [[ "$arg" == -c* ]]; then
      local value="${arg#-c}"
      if [[ "$value" == model=* ]] || [[ "$value" == model_reasoning_effort=* ]]; then
        log_warn "Blocked override attempt: $arg"
        continue
      fi
      FILTERED_ARGS+=("$arg")
      continue
    fi

    if [[ "$arg" == "--stdin" ]]; then
      FILTERED_ARGS+=("-")
      HAS_STDIN_FLAG=true
      continue
    fi

    FILTERED_ARGS+=("$arg")
  done

  if [[ "$skip_next" == "true" ]]; then
    log_warn "Dangling -c option ignored"
  fi
}

# =====================================================
# メイン処理
# =====================================================
main() {
  if ! command -v codex >/dev/null 2>&1; then
    echo "[codex-wrapper-xhigh] ERROR: codex CLI not found in PATH" >&2
    exit 1
  fi

  local cmd_type="exec"
  local session_id=""
  local resume_prompt=""
  local remaining_args=()

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

  filter_args "${remaining_args[@]}"

  log_info "Model: ${FIXED_MODEL}"
  log_info "Reasoning Effort: ${FIXED_REASONING_EFFORT}"

  if [[ "$cmd_type" == "resume" ]]; then
    if [[ -z "$session_id" ]]; then
      echo "[codex-wrapper-xhigh] ERROR: --resume requires session_id" >&2
      exit 1
    fi
    log_info "Command: resume (session: $session_id)"

    if [[ "$HAS_STDIN_FLAG" == "true" ]]; then
      log_warn "--stdin is ignored in resume mode"
    fi

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
    log_info "Command: exec"

    exec codex exec \
      -c "model=${FIXED_MODEL}" \
      -c "model_reasoning_effort=${FIXED_REASONING_EFFORT}" \
      "${FILTERED_ARGS[@]}"
  fi
}

main "$@"
