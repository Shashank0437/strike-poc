#!/usr/bin/env bash
# Report OK / MISSING for the tools that often lack an apt package.
# Run from anywhere; uses repo-relative git_tools/optional/ if present.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPT_BIN="${ROOT_DIR}/git_tools/optional/bin"
OPT_EA="${ROOT_DIR}/git_tools/optional/eaphammer"
OPT_HC="${ROOT_DIR}/git_tools/optional/hashcat-utils/src"
GOBIN=""
[[ -d "${HOME}/go/bin" ]] && GOBIN="${HOME}/go/bin"
if command -v go &>/dev/null; then
  g="$(go env GOPATH 2>/dev/null)/bin"
  [[ -d "$g" ]] && GOBIN="${g}"
fi
export PATH="${PATH}:${OPT_BIN}:${OPT_EA}:${OPT_HC}:${GOBIN}:${HOME}/.local/bin"
# Optional hint file from install-nyxstrike-optional-tools.sh
[[ -f "${HOME}/.config/nyxstrike-optional-path.sh" ]] && \
  # shellcheck source=/dev/null
  source "${HOME}/.config/nyxstrike-optional-path.sh" 2>/dev/null || true

check_one() {
  local name="$1" ok=false
  shift
  for cmd in "$@"; do
    if command -v "${cmd%% *}" &>/dev/null; then
      local p
      p="$(command -v "${cmd%% *}" 2>/dev/null || true)"
      echo "  OK  ${name}  ->  ${p}"
      ok=true
      return 0
    fi
  done
  echo "  ** MISSING **  ${name}  (look for: $*)"
  return 1
}

echo "NyxStrike optional / non-apt tools (PATH includes optional dirs + ~/.local/bin + go bin)"
echo "----"
missing=0
check_one amass amass || ((missing++)) || true
check_one arjun arjun || ((missing++)) || true
check_one bulk-extractor bulk_extractor bulk-extractor || ((missing++)) || true
check_one enum4linux enum4linux || ((missing++)) || true
check_one enum4linux-ng enum4linux-ng || ((missing++)) || true
check_one eaphammer eaphammer || ((missing++)) || true
check_one feroxbuster feroxbuster || ((missing++)) || true
check_one hashcat-utils cap2hccapx.pl cap2hccapx || ((missing++)) || true
check_one kismet kismet || ((missing++)) || true
check_one paramspider paramspider || ((missing++)) || true
check_one radare2 r2 radare2 || ((missing++)) || true
check_one responder responder Responder || ((missing++)) || true
check_one subfinder subfinder || ((missing++)) || true
check_one wpscan wpscan || ((missing++)) || true
check_one commix commix || ((missing++)) || true
check_one theharvester theHarvester theharvester || ((missing++)) || true
check_one sublist3r sublist3r || ((missing++)) || true
check_one joomscan joomscan || ((missing++)) || true
echo "----"
if ((missing == 0)); then
  echo "All 18 found on PATH."
  exit 0
fi
echo "Missing: ${missing} tool(s). Run: ${ROOT_DIR}/scripts/install-nyxstrike-optional-tools.sh"
echo "(The \"No apt install candidate (skipped)\" lines from nyxstrike.sh -t are normal; they do not use this check.)"
exit 1

