#!/usr/bin/env bash

# =========================================================
# psysh installer
# run once — never again
#
# usage:
#   bash install.sh
#
# or one-liner:
#   curl -fsSL https://raw.githubusercontent.com/awesomemad/psysh/main/install.sh | bash
# =========================================================

set -e

# =========================================================
# Defaults
# =========================================================

PSYSH_HOME="${PSYSH_HOME:-$HOME/.psysh}"
PSYSH_PLUGIN_DIR="$PSYSH_HOME/plugins"
PSYSH_THEME_DIR="$PSYSH_HOME/themes"
PSYSH_CACHE_DIR="$PSYSH_HOME/cache"
PSYSH_LOG_DIR="$PSYSH_HOME/logs"
PSYSH_ENABLED_PLUGINS="$PSYSH_HOME/enabled_plugins"
PSYSH_ENABLED_THEME="$PSYSH_HOME/enabled_theme"
PSYSH_CORE="$PSYSH_HOME/psy.sh"

PSYSH_GITHUB_USER="${PSYSH_GITHUB_USER:-awesomemad}"
PSYSH_GITHUB_REPO="${PSYSH_GITHUB_REPO:-psysh}"
PSYSH_GITHUB_BRANCH="${PSYSH_GITHUB_BRANCH:-main}"

BASHRC="${BASHRC:-$HOME/.bashrc}"

# =========================================================
# Helpers
# =========================================================

_ok()     { echo "  ✓ $*"; }
_warn()   { echo "  ! $*"; }
_header() { echo; echo "=== $* ==="; echo; }

_require_curl() {
    command -v curl >/dev/null 2>&1 || {
        echo "  curl is required but not found"
        exit 1
    }
}

# =========================================================
# Step 1 — directories
# =========================================================

_header "setting up directories"

mkdir -p \
    "$PSYSH_PLUGIN_DIR" \
    "$PSYSH_THEME_DIR"  \
    "$PSYSH_CACHE_DIR"  \
    "$PSYSH_LOG_DIR"

touch "$PSYSH_ENABLED_PLUGINS"
touch "$PSYSH_ENABLED_THEME"

_ok "~/.psysh/ structure created"

# =========================================================
# Step 2 — fetch psy.sh from GitHub
# =========================================================

_header "fetching core runtime"

_require_curl

PSH_RAW="https://raw.githubusercontent.com/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}/${PSYSH_GITHUB_BRANCH}/psy.sh"

http_code=$(curl -fsSL \
    -w "%{http_code}" \
    -o "$PSYSH_CORE" \
    "$PSH_RAW" 2>/dev/null)

if [[ "$http_code" != "200" ]]; then
    _warn "failed to fetch psy.sh (HTTP $http_code)"
    _warn "url: $PSH_RAW"
    exit 1
fi

chmod +x "$PSYSH_CORE"
_ok "core runtime fetched → $PSYSH_CORE"

# =========================================================
# Step 3 — GitHub config
# =========================================================

_header "GitHub config"

echo "  Registry: github.com/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}"
echo

# Ask for username only if someone else is installing
# (forking the repo, hosting their own registry)
if [[ "$PSYSH_GITHUB_USER" == "awesomemad" ]]; then
    read -rp "  Your GitHub username (for psy upload, or Enter to skip): " _input_user
    [[ -n "$_input_user" ]] && PSYSH_GITHUB_USER="$_input_user"
fi

if [[ -z "$PSYSH_GITHUB_TOKEN" ]]; then
    echo
    echo "  GitHub token — optional"
    echo "  ├ needed for : psy upload, private registry"
    echo "  ├ not needed : public registry fetch/search"
    echo "  ├ type       : fine-grained PAT  (not classic)"
    echo "  ├ repo access: your registry repo only"
    echo "  └ permissions: Contents=Read/Write  Metadata=Read"
    echo
    read -rsp "  Paste token or press Enter to skip: " PSYSH_GITHUB_TOKEN
    echo
fi

_ok "registry:  github.com/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}"
_ok "branch:    $PSYSH_GITHUB_BRANCH"
_ok "token:     $( [[ -n "$PSYSH_GITHUB_TOKEN" ]] && echo "set" || echo "not set (upload disabled)" )"

# =========================================================
# Step 4 — write to .bashrc (idempotent)
# =========================================================

_header "wiring into $BASHRC"

MARKER="# psysh"

if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    _warn "psysh block already exists in $BASHRC — skipping"
    _warn "to reinstall cleanly, remove the psysh block from $BASHRC first"
else
    cat >> "$BASHRC" << EOF

$MARKER
export PSYSH_HOME="$PSYSH_HOME"
export PSYSH_GITHUB_USER="$PSYSH_GITHUB_USER"
export PSYSH_GITHUB_REPO="$PSYSH_GITHUB_REPO"
export PSYSH_GITHUB_BRANCH="$PSYSH_GITHUB_BRANCH"
EOF

    if [[ -n "$PSYSH_GITHUB_TOKEN" ]]; then
        echo "export PSYSH_GITHUB_TOKEN=\"$PSYSH_GITHUB_TOKEN\"" >> "$BASHRC"
    fi

    cat >> "$BASHRC" << 'EOF'
source "$PSYSH_HOME/psy.sh"
psysh_init
EOF

    _ok "psysh block written to $BASHRC"
fi

# =========================================================
# Step 5 — done
# =========================================================

_header "done"

echo "  psysh is installed."
echo
echo "  Restart your shell or run:"
echo "    source ~/.bashrc"
echo
echo "  Verify:"
echo "    psy doctor"
echo
echo "  One-liner for next time:"
echo "    curl -fsSL https://raw.githubusercontent.com/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}/${PSYSH_GITHUB_BRANCH}/install.sh | bash"
echo
