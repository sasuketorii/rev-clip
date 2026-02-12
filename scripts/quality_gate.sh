#!/usr/bin/env bash
set -euo pipefail

LEVEL="B"

usage() {
  cat <<'USAGE'
Usage: quality_gate.sh [--level A|B|C]

Level A (Hotfix/小修正): cargo fmt, targeted tests (optional)
Level B (通常): fmt, clippy -D warnings, cargo test, cargo audit
Level C (リリース候補/性能影響): Level B + cargo bench (主要経路)

コマンドが無い場合はスキップし警告します。実行ログで確認してください。
USAGE
}

warn() { echo "[WARN] $*" >&2; }
info() { echo "[INFO] $*"; }

run_if_present() {
  local cmd="$1"; shift
  if command -v "$cmd" >/dev/null 2>&1; then
    info "run: $cmd $*"
    "$cmd" "$@"
  else
    warn "skip: $cmd (not found)"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --level) LEVEL="${2^^}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) warn "unknown arg: $1"; shift ;;
  esac
done

case "$LEVEL" in
  A)
    run_if_present cargo fmt
    info "Level A done (fmt only;テストは任意で実行してください)"
    ;;
  B)
    run_if_present cargo fmt
    run_if_present cargo clippy --all-targets --all-features -D warnings
    run_if_present cargo test
    run_if_present cargo audit
    info "Level B done"
    ;;
  C)
    run_if_present cargo fmt
    run_if_present cargo clippy --all-targets --all-features -D warnings
    run_if_present cargo test
    run_if_present cargo audit
    run_if_present cargo bench
    info "Level C done"
    ;;
  *)
    warn "unknown level: $LEVEL (use A/B/C)"; exit 1 ;;
esac
