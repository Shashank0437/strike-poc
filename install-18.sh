#!/usr/bin/env bash
# Install the ~18 common security tools that often have no default apt package.
# Idempotent: skips steps when the tool is already on PATH.
#
# Usage:
#   ./scripts/install-nyxstrike-optional-tools.sh
#   ./scripts/install-nyxstrike-optional-tools.sh --skip-snap
#   ./scripts/install-nyxstrike-optional-tools.sh --skip-gem
#
# Requires: curl or wget, git, python3, sudo (for snap/radare2 system install by default).
# Go / Ruby / Rust are only needed for some paths; the script will tell you if missing.
#
# Afterward, ensure ~/.local/bin (pip --user) and `go env GOPATH`/bin are on your PATH.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(basename "${SCRIPT_DIR}")" == "scripts" ]]; then
  ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
  ROOT_DIR="${SCRIPT_DIR}"
fi
OPT_DIR="${ROOT_DIR}/git_tools/optional"
PYTHON="${PYTHON:-python3}"
SKIP_SNAP=false
SKIP_GEM=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-snap)  SKIP_SNAP=true ;;
    --skip-gem)   SKIP_GEM=true ;;
    --dry-run)    DRY_RUN=true ;;
    -h|--help)
      sed -n '1,25p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

have() { command -v "$1" &>/dev/null; }

run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

sudo_run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] sudo $*"
    return 0
  fi
  sudo -n true 2>/dev/null && sudo "$@" || sudo "$@"
}

ensure_dir() { mkdir -p "$1"; }

# Py/Perl entrypoints: fixed paths so a single PATH add works.
write_shim_py() {
  local name="$1" script="$2"
  cat > "${OPT_DIR}/bin/${name}" <<SHIM
#!/bin/sh
exec $PYTHON "$script" "\$@"
SHIM
  run chmod +x "${OPT_DIR}/bin/${name}"
}
write_shim_pl() {
  local name="$1" script="$2"
  cat > "${OPT_DIR}/bin/${name}" <<SHIM
#!/bin/sh
exec perl "$script" "\$@"
SHIM
  run chmod +x "${OPT_DIR}/bin/${name}"
}

append_path_hint() {
  # shellcheck disable=SC1091
  local f="${HOME}/.config/nyxstrike-optional-path.sh"
  if ! grep -qs 'git_tools/optional' "$f" 2>/dev/null; then
    {
      echo "# Added by install-nyxstrike-optional-tools.sh"
      echo "export PATH=\"\${PATH}:${OPT_DIR}/bin\""
      echo "export PATH=\"\${PATH}:${OPT_DIR}/eaphammer\""
      echo "export PATH=\"\${PATH}:${OPT_DIR}/hashcat-utils/src\""
      echo "export PATH=\"\${PATH}:${OPT_DIR}/hashcat-utils/bin\""
      echo "export PATH=\"\${PATH}:${ROOT_DIR}/nyxstrike-env/bin\""
    } >>"$f" 2>/dev/null || true
  fi
}

# Prefer nyxstrike-env: its pip is not subject to Debian's "system python has no pip" policy.
# Do not call the venv "pip" stub; use python3 -m pip. Never run ensurepip on /usr/bin/python3 on Debian
# (it is disabled and prints noise); use: sudo apt-get install -y python3-pip
VENV_PY="${ROOT_DIR}/nyxstrike-env/bin/python3"
pip_user_install() {
  if [[ -x "${VENV_PY}" ]]; then
    if ! "${VENV_PY}" -m pip --version &>/dev/null; then
      echo "  (nyxstrike-env: bootstrapping pip with ensurepip)..."
      run "${VENV_PY}" -m ensurepip --upgrade 2>/dev/null || true
    fi
    if "${VENV_PY}" -m pip --version &>/dev/null; then
      if run "${VENV_PY}" -m pip install --progress-bar off -q "$@"; then
        return 0
      fi
    fi
  fi
  if ! "$PYTHON" -m pip --version &>/dev/null; then
    echo "  (system ${PYTHON} has no pip. On Debian/Ubuntu: sudo apt-get install -y python3-pip)" >&2
    return 1
  fi
  run "$PYTHON" -m pip install --user --progress-bar off -q "$@" || return 1
}

echo "NyxStrike optional tools -> ${OPT_DIR}"
ensure_dir "${OPT_DIR}/bin"
# One-time venv fix so we never rely on a broken ${ROOT}/nyxstrike-env/bin/pip script.
if [[ -x "${VENV_PY}" ]] && ! "${VENV_PY}" -m pip --version &>/dev/null; then
  echo "Bootstrapping pip in nyxstrike-env (python3 -m ensurepip)..."
  run "${VENV_PY}" -m ensurepip --upgrade 2>/dev/null || true
fi

# --- 1) Snap (optional)
if [[ "$SKIP_SNAP" != true ]] && have snap; then
  for s in amass commix enum4linux feroxbuster; do
    if have "$s"; then
      continue
    fi
    echo "[snap] $s..."
    if [[ "$DRY_RUN" == true ]]; then
      echo "[dry-run] sudo snap install $s"
    else
      sudo snap install "$s" 2>/dev/null || echo "  snap install $s failed (try manual or --skip-snap + go/git)"
    fi
  done
  if ! have kismet; then
    echo "[snap] kismet..."
    if [[ "$DRY_RUN" == true ]]; then
      echo "[dry-run] sudo snap install kismet"
    else
      sudo snap install kismet 2>/dev/null || \
        echo "  kismet: snap not available; see https://www.kismetwireless.net/docs/packages/"
    fi
  fi
elif [[ "$SKIP_SNAP" != true ]]; then
  echo "snap not found; skipping amass, commix, enum4linux, feroxbuster (use --skip-snap; go + git will still run)."
fi

# --- 2) Go tools (subfinder; amass if snap failed)
if have go; then
  gbin="$(go env GOPATH 2>/dev/null)/bin"
  export PATH="${PATH}:${gbin}"
  if ! have subfinder; then
    echo "[go] subfinder..."
    run go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
  fi
  if ! have amass; then
    echo "[go] amass (if snap did not provide it)..."
    run go install -v "github.com/owasp-amass/amass/v4/cmd/amass@latest"
  fi
else
  if ! have subfinder || ! have amass; then
    echo "go not in PATH; install golang for subfinder and amass (or use snap for amass)."
  fi
fi

# --- 3) pip
if ! have arjun; then
  echo "[pip] arjun..."
  pip_user_install arjun || echo "  arjun: use nyxstrike-env pip, or: sudo apt-get install -y python3-pip && $PYTHON -m pip install --user arjun"
fi
if ! have paramspider; then
  # There is no PyPI dist named "paramspider"; use Git + editable install (venv pip only on Debian).
  if [[ -d "${OPT_DIR}/ParamSpider/.git" ]]; then
    run git -C "${OPT_DIR}/ParamSpider" pull --ff-only 2>/dev/null || true
  else
    echo "[git] ParamSpider (clone + pip install -e into nyxstrike-env)..."
    run git clone --depth 1 https://github.com/devanshbatham/ParamSpider.git "${OPT_DIR}/ParamSpider" || true
  fi
  if [[ -f "${OPT_DIR}/ParamSpider/setup.py" ]]; then
    if [[ -x "${VENV_PY}" ]]; then
      if "${VENV_PY}" -m pip --version &>/dev/null; then
        ( cd "${OPT_DIR}/ParamSpider" && run "${VENV_PY}" -m pip install --progress-bar off -q -e . ) 2>/dev/null || true
      else
        echo "  paramspider: no pip in nyxstrike-env; run: ${VENV_PY} -m ensurepip --upgrade" >&2
      fi
    fi
  fi
  if ! have paramspider; then
    if [[ -f "${OPT_DIR}/ParamSpider/paramspider/main.py" ]]; then
      {
        echo '#!/bin/sh'
        echo "cd \"${OPT_DIR}/ParamSpider\" && exec ${VENV_PY} -m paramspider.main \"\$@\""
      } > "${OPT_DIR}/bin/paramspider"
      run chmod +x "${OPT_DIR}/bin/paramspider"
    elif [[ -f "${OPT_DIR}/ParamSpider/paramspider.py" ]]; then
      write_shim_py paramspider "${OPT_DIR}/ParamSpider/paramspider.py"
    fi
  fi
fi

# enum4linux-ng (git often more current than pypi on some distros)
if ! have enum4linux-ng; then
  if ! pip_user_install enum4linux-ng 2>/dev/null; then
    ensure_dir "${OPT_DIR}/enum4linux-ng"
    if [[ -d "${OPT_DIR}/enum4linux-ng/.git" ]]; then
      run git -C "${OPT_DIR}/enum4linux-ng" pull --ff-only 2>/dev/null || true
    else
      run git clone --depth 1 https://github.com/cddmp/enum4linux-ng.git "${OPT_DIR}/enum4linux-ng" || true
    fi
    if [[ -f "${OPT_DIR}/enum4linux-ng/enum4linux-ng.py" ]]; then
      write_shim_py enum4linux-ng "${OPT_DIR}/enum4linux-ng/enum4linux-ng.py"
    fi
  fi
fi

# theHarvester
if ! have theHarvester 2>/dev/null && ! have theharvester 2>/dev/null; then
  echo "[pip] theHarvester..."
  if pip_user_install theHarvester 2>/dev/null || pip_user_install theharvester 2>/dev/null; then
    :
  else
    ensure_dir "${OPT_DIR}/theHarvester"
    if [[ -d "${OPT_DIR}/theHarvester/.git" ]]; then
      run git -C "${OPT_DIR}/theHarvester" pull --ff-only 2>/dev/null || true
    else
      run git clone --depth 1 https://github.com/laramies/theHarvester.git "${OPT_DIR}/theHarvester" || true
    fi
    if [[ -d "${OPT_DIR}/theHarvester" ]]; then
      if [[ -x "${VENV_PY}" ]]; then
        if "${VENV_PY}" -m pip --version &>/dev/null; then
          ( cd "${OPT_DIR}/theHarvester" && run "${VENV_PY}" -m pip install --progress-bar off -q -e . ) 2>/dev/null || true
        fi
      fi
      if ! have theHarvester 2>/dev/null && ! have theharvester 2>/dev/null; then
        ( cd "${OPT_DIR}/theHarvester" && run "$PYTHON" -m pip install --user --progress-bar off -q -e . ) 2>/dev/null || true
      fi
    fi
  fi
fi

# commix (if snap skipped)
if ! have commix; then
  if pip_user_install commix 2>/dev/null; then
    :
  else
    ensure_dir "${OPT_DIR}/commix"
    if [[ ! -d "${OPT_DIR}/commix/.git" ]]; then
      run git clone --depth 1 https://github.com/commixproject/commix.git "${OPT_DIR}/commix" || true
    else
      run git -C "${OPT_DIR}/commix" pull --ff-only 2>/dev/null || true
    fi
    if [[ -f "${OPT_DIR}/commix/commix.py" ]]; then
      write_shim_py commix "${OPT_DIR}/commix/commix.py"
    fi
  fi
fi

# --- 4) wpscan (gem)
if ! have wpscan; then
  if [[ "$SKIP_GEM" == true ]]; then
    echo "skipping wpscan (--skip-gem)"
  elif have gem; then
    echo "[gem] wpscan..."
    run gem install wpscan --user-install 2>/dev/null || run sudo gem install wpscan 2>/dev/null || echo "  gem wpscan failed; see https://github.com/wpscanteam/wpscan"
  else
    echo "ruby gem not found; install ruby-dev and gem, or use Docker for wpscan"
  fi
fi

# --- 5) Git: responder, eaphammer, sublist3r, joomscan, hashcat-utils
clone_install() {
  local name="$1" url="$2" req="${3:-}"
  local target="${OPT_DIR}/${name}"
  if [[ -d "${target}/.git" ]]; then
    run git -C "${target}" pull --ff-only 2>/dev/null || true
  else
    run git clone --depth 1 "$url" "${target}" || return 1
  fi
  if [[ -n "$req" && -f "${target}/${req}" ]]; then
    if [[ -x "${VENV_PY}" ]]; then
      if "${VENV_PY}" -m pip --version &>/dev/null; then
        run "${VENV_PY}" -m pip install -q -r "${target}/${req}" 2>/dev/null || true
      else
        run "$PYTHON" -m pip install --user -q -r "${target}/${req}" 2>/dev/null || true
      fi
    else
      run "$PYTHON" -m pip install --user -q -r "${target}/${req}" 2>/dev/null || true
    fi
  fi
}

# Responder
if ! have Responder 2>/dev/null && ! have responder 2>/dev/null; then
  if clone_install "Responder" "https://github.com/lgandx/Responder.git" "requirements.txt" &&
    [[ -f "${OPT_DIR}/Responder/Responder.py" ]]; then
    write_shim_py responder "${OPT_DIR}/Responder/Responder.py"
  fi
fi

# eaphammer
if ! have eaphammer; then
  clone_install "eaphammer" "https://github.com/s0lst1c3/eaphammer.git" "requirements.txt" || true
  if [[ -f "${OPT_DIR}/eaphammer/eaphammer" ]]; then
    run chmod +x "${OPT_DIR}/eaphammer/eaphammer" 2>/dev/null || true
  fi
fi

# sublist3r
if ! have sublist3r; then
  if clone_install "sublist3r" "https://github.com/aboul3la/Sublist3r.git" "requirements.txt" &&
    [[ -f "${OPT_DIR}/sublist3r/sublist3r.py" ]]; then
    write_shim_py sublist3r "${OPT_DIR}/sublist3r/sublist3r.py"
  fi
fi

# joomscan
if ! have joomscan; then
  if clone_install "joomscan" "https://github.com/OWASP/joomscan.git" "" &&
    [[ -f "${OPT_DIR}/joomscan/joomscan.pl" ]]; then
    write_shim_pl joomscan "${OPT_DIR}/joomscan/joomscan.pl"
  fi
fi

# hashcat-utils (C sources: need `make` → binaries in bin/)
if ! have cap2hccapx 2>/dev/null; then
  if [[ -d "${OPT_DIR}/hashcat-utils/.git" ]]; then
    run git -C "${OPT_DIR}/hashcat-utils" pull --ff-only 2>/dev/null || true
  else
    run git clone --depth 1 https://github.com/hashcat/hashcat-utils.git "${OPT_DIR}/hashcat-utils" || true
  fi
  if [[ -f "${OPT_DIR}/hashcat-utils/Makefile" ]]; then
    echo "[make] hashcat-utils..."
    ( cd "${OPT_DIR}/hashcat-utils" && run make clean 2>/dev/null; run make ) 2>/dev/null || \
      echo "  hashcat-utils: make failed (install build-essential gcc) or get binaries from GitHub releases"
  fi
fi

# --- 6) radare2
if ! have r2; then
  if [[ -x "${OPT_DIR}/radare2/binr/r2" ]]; then
    run ln -sf "${OPT_DIR}/radare2/binr/r2" "${OPT_DIR}/bin/r2" 2>/dev/null || true
  else
    echo "[radare2] cloning and running sys/install.sh (needs sudo)..."
    if [[ ! -d "${OPT_DIR}/radare2/.git" ]]; then
      run git clone --depth 1 https://github.com/radareorg/radare2.git "${OPT_DIR}/radare2" || true
    fi
    if [[ -f "${OPT_DIR}/radare2/sys/install.sh" ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] (cd ${OPT_DIR}/radare2 && sudo ./sys/install.sh)"
      else
        ( cd "${OPT_DIR}/radare2" && sudo ./sys/install.sh ) || \
          echo "  radare2 build failed; try: https://github.com/radareorg/radare2/wiki"
      fi
    fi
  fi
fi

# --- 7) bulk-extractor: build is heavy; try one apt retry then leave instructions
if ! have bulk_extract 2>/dev/null && ! have bulk_extractor 2>/dev/null; then
  if have apt-get; then
    if [[ "$DRY_RUN" == true ]]; then
      echo "[dry-run] apt-get install bulk-extractor"
    else
      sudo_run apt-get update -qq 2>/dev/null || true
    fi
    if sudo_run apt-get install -y -qq bulk-extractor 2>/dev/null; then
      echo "[apt] bulk-extractor ok"
    else
      echo "bulk-extractor: still unavailable via apt. Build: https://github.com/simsong/bulk_extractor"
    fi
  else
    echo "bulk-extractor: not found; see https://github.com/simsong/bulk_extractor"
  fi
fi

append_path_hint
echo
echo "Done. Add optional PATH entries if needed:"
echo "  export PATH=\"\${PATH}:${OPT_DIR}/bin\""
echo "  export PATH=\"\${PATH}:${ROOT_DIR}/nyxstrike-env/bin\""
echo "  export PATH=\"\${PATH}:${OPT_DIR}/eaphammer\""
echo "  export PATH=\"\${PATH}:${OPT_DIR}/hashcat-utils/bin\""
echo "  export PATH=\"\${PATH}:${OPT_DIR}/hashcat-utils/src\""
echo "  (hint file may exist: ~/.config/nyxstrike-optional-path.sh )"
if have go; then
  echo "  export PATH=\"\${PATH}:$(go env GOPATH 2>/dev/null)/bin\""
fi
echo "  export PATH=\"\${PATH}:\$HOME/.local/bin\""
echo
if [[ -x "${VENV_PY}" ]] && ! "${VENV_PY}" -m pip --version &>/dev/null; then
  echo "If pip in nyxstrike-env is still broken, run (once):"
  echo "  ${VENV_PY} -m ensurepip --upgrade && ${VENV_PY} -m pip install -U pip"
fi
echo "Re-check: install-nyxstrike-optional-tools.sh (this script) is safe to re-run."

