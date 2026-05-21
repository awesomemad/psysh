#!/usr/bin/env bash

# =========================================================
# psysh — lightweight bash plugin and theme manager
# named after ψ — the wave function
# =========================================================

export PSYSH_HOME="${PSYSH_HOME:-$HOME/.psysh}"
export PSYSH_PLUGIN_DIR="$PSYSH_HOME/plugins"
export PSYSH_THEME_DIR="$PSYSH_HOME/themes"
export PSYSH_CACHE_DIR="$PSYSH_HOME/cache"
export PSYSH_LOG_DIR="$PSYSH_HOME/logs"
export PSYSH_ENABLED_PLUGINS="$PSYSH_HOME/enabled_plugins"
export PSYSH_ENABLED_THEME="$PSYSH_HOME/enabled_theme"

export PSYSH_GITHUB_USER="${PSYSH_GITHUB_USER:-awesomemad}"
export PSYSH_GITHUB_REPO="${PSYSH_GITHUB_REPO:-psysh-reg-official}"
export PSYSH_GITHUB_BRANCH="${PSYSH_GITHUB_BRANCH:-main}"

# dep bloat thresholds — only used at psy enable time, never at startup
PSYSH_DEP_LINE_LIMIT="${PSYSH_DEP_LINE_LIMIT:-137}"
PSYSH_DEP_COUNT_LIMIT="${PSYSH_DEP_COUNT_LIMIT:-4}"

# =========================================================
# Init — the ONLY thing that runs at shell startup
# reads two files, sources them, nothing else
# no dep checks, no compatibility, no calculations
# =========================================================

psysh_init() {
    [[ -f "$PSYSH_ENABLED_PLUGINS" ]] && \
    while IFS= read -r _psy_name; do
        [[ -z "$_psy_name" ]] && continue
        # shellcheck source=/dev/null
        source "$PSYSH_PLUGIN_DIR/$_psy_name.sh" 2>/dev/null \
            || echo "psysh: missing plugin: $_psy_name" >&2
    done < "$PSYSH_ENABLED_PLUGINS"

    [[ -f "$PSYSH_ENABLED_THEME" ]] && {
        local _psy_theme
        _psy_theme=$(< "$PSYSH_ENABLED_THEME")
        [[ -n "$_psy_theme" ]] && \
            # shellcheck source=/dev/null
            source "$PSYSH_THEME_DIR/$_psy_theme.sh" 2>/dev/null \
                || echo "psysh: missing theme: $_psy_theme" >&2
    }
}

# =========================================================
# Internal helpers — only called by psy commands
# =========================================================

_psy_require_curl() {
    command -v curl >/dev/null 2>&1 || {
        echo "psy: curl is required but not found"
        return 1
    }
}

_psy_get_meta() {
    grep "^# psysh-$2:" "$1" | head -n1 | sed "s/^# psysh-$2:[ ]*//"
}

_psy_find_local() {
    if [[ -f "$PSYSH_PLUGIN_DIR/$1.sh" ]]; then
        echo "$PSYSH_PLUGIN_DIR/$1.sh"
    elif [[ -f "$PSYSH_THEME_DIR/$1.sh" ]]; then
        echo "$PSYSH_THEME_DIR/$1.sh"
    fi
}

_psy_is_plugin_enabled() {
    grep -qx "$1" "$PSYSH_ENABLED_PLUGINS" 2>/dev/null
}

_psy_logical_lines() {
    grep -cvE '^\s*(#|$|\{|\}|;;|esac|fi|done|then|do|else)\s*$' "$1" 2>/dev/null || echo 0
}

_psy_raw_url()  { echo "https://raw.githubusercontent.com/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}/${PSYSH_GITHUB_BRANCH}/$1"; }
_psy_api_url()  { echo "https://api.github.com/repos/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}/contents/$1"; }

_psy_print_header() {
    echo
    echo "=========================================="
    echo "            psysh runtime"
    echo "=========================================="
    echo
}

# =========================================================
# List
# =========================================================

_psy_list_plugins() {
    echo
    echo "Plugins"
    echo "-------"
    for f in "$PSYSH_PLUGIN_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f" .sh)
        _psy_is_plugin_enabled "$name" \
            && echo "  [enabled]  $name" \
            || echo "  [disabled] $name"
    done
}

_psy_list_themes() {
    echo
    echo "Themes"
    echo "------"
    local active=""
    [[ -f "$PSYSH_ENABLED_THEME" ]] && active=$(< "$PSYSH_ENABLED_THEME")
    for f in "$PSYSH_THEME_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f" .sh)
        [[ "$name" == "$active" ]] \
            && echo "  [enabled]  $name" \
            || echo "  [disabled] $name"
    done
}

# =========================================================
# Enable — ALL intelligence lives here, never at startup
# resolves deps, checks sizes, writes ordered list, done
# =========================================================

_psy_enable() {
    local target="$1"
    local file
    file=$(_psy_find_local "$target")

    if [[ -z "$file" ]]; then
        echo "psy: not found locally: $target (try: psy fetch $target)"
        return 1
    fi

    local type
    type=$(_psy_get_meta "$file" "type")
    [[ -z "$type" ]] && type="plugin"

    # ── resolve deps ──────────────────────────────────────
    local raw_deps
    raw_deps=$(_psy_get_meta "$file" "dependencies")

    local deps_needed=()
    local deps_missing=()

    if [[ -n "$raw_deps" ]]; then
        local dep
        for dep in ${raw_deps//,/ }; do
            dep="${dep// /}"
            [[ -z "$dep" ]] && continue
            _psy_is_plugin_enabled "$dep" && continue
            local dep_file
            dep_file=$(_psy_find_local "$dep")
            if [[ -z "$dep_file" ]]; then
                deps_missing+=("$dep")
            else
                deps_needed+=("$dep")
            fi
        done
    fi

    # hard stop — missing deps must be fetched first
    if (( ${#deps_missing[@]} > 0 )); then
        echo "psy: missing dependencies (not on disk):"
        local m
        for m in "${deps_missing[@]}"; do
            echo "    psy fetch $m"
        done
        return 1
    fi

    # ── decide auto or ask ────────────────────────────────
    if (( ${#deps_needed[@]} > 0 )); then
        local heavy=0

        # too many deps?
        (( ${#deps_needed[@]} >= PSYSH_DEP_COUNT_LIMIT )) && heavy=1

        # any dep too large?
        if (( heavy == 0 )); then
            local dep
            for dep in "${deps_needed[@]}"; do
                local dep_file lines
                dep_file=$(_psy_find_local "$dep")
                lines=$(_psy_logical_lines "$dep_file")
                (( lines >= PSYSH_DEP_LINE_LIMIT )) && { heavy=1; break; }
            done
        fi

        if (( heavy == 0 )); then
            # lightweight — auto enable and report
            local dep
            for dep in "${deps_needed[@]}"; do
                echo "  → pulled in dependency: $dep"
                echo "$dep" >> "$PSYSH_ENABLED_PLUGINS"
            done
        else
            # heavy — show sizes and ask
            echo
            echo "  Dependencies required:"
            local dep
            for dep in "${deps_needed[@]}"; do
                local dep_file lines
                dep_file=$(_psy_find_local "$dep")
                lines=$(_psy_logical_lines "$dep_file")
                printf "    %-20s  %s logical lines\n" "$dep" "$lines"
            done
            echo
            read -rp "  Enable all of the above? [y/N] " answer
            if [[ "${answer,,}" != "y" ]]; then
                echo "psy: aborted"
                return 1
            fi
            local dep
            for dep in "${deps_needed[@]}"; do
                echo "  → pulled in dependency: $dep"
                echo "$dep" >> "$PSYSH_ENABLED_PLUGINS"
            done
        fi
    fi

    # ── write target to the list ──────────────────────────
    case "$type" in
        plugin)
            if _psy_is_plugin_enabled "$target"; then
                echo "psy: already enabled: $target"
            else
                echo "$target" >> "$PSYSH_ENABLED_PLUGINS"
                echo "enabled plugin: $target"
            fi
            ;;
        theme)
            echo "$target" > "$PSYSH_ENABLED_THEME"
            echo "enabled theme: $target"
            ;;
        *)
            echo "psy: unknown type '$type' in $file"
            return 1
            ;;
    esac

    echo "→ run 'psy reload' to apply"
}

# =========================================================
# Disable
# =========================================================

_psy_disable() {
    local target="$1"

    if _psy_is_plugin_enabled "$target"; then
        grep -vx "$target" "$PSYSH_ENABLED_PLUGINS" > "$PSYSH_ENABLED_PLUGINS.tmp" \
            && mv "$PSYSH_ENABLED_PLUGINS.tmp" "$PSYSH_ENABLED_PLUGINS"
        echo "disabled plugin: $target"
        echo "→ run 'psy reload' to apply"
        return
    fi

    if [[ -f "$PSYSH_ENABLED_THEME" ]] && [[ "$(< "$PSYSH_ENABLED_THEME")" == "$target" ]]; then
        rm -f "$PSYSH_ENABLED_THEME"
        echo "disabled theme: $target"
        echo "→ run 'psy reload' to apply"
        return
    fi

    echo "psy: not currently enabled: $target"
}

# =========================================================
# Info
# =========================================================

_psy_info() {
    local file
    file=$(_psy_find_local "$1")
    if [[ -z "$file" ]]; then
        echo "psy: not found locally: $1"
        return 1
    fi
    echo
    echo "  Name:         $(_psy_get_meta "$file" "name")"
    echo "  Type:         $(_psy_get_meta "$file" "type")"
    echo "  Version:      $(_psy_get_meta "$file" "version")"
    echo "  Author:       $(_psy_get_meta "$file" "author")"
    echo "  Description:  $(_psy_get_meta "$file" "description")"
    echo "  Dependencies: $(_psy_get_meta "$file" "dependencies")"
    echo "  Tags:         $(_psy_get_meta "$file" "tags")"
    echo
}

# =========================================================
# Create
# =========================================================

_psy_create() {
    local type="$1" name="$2"
    if [[ -z "$type" || -z "$name" ]]; then
        echo "Usage: psy create {plugin|theme} <name>"
        return 1
    fi

    local dir
    case "$type" in
        plugin) dir="$PSYSH_PLUGIN_DIR" ;;
        theme)  dir="$PSYSH_THEME_DIR"  ;;
        *)      echo "psy: invalid type (use 'plugin' or 'theme')"; return 1 ;;
    esac

    local file="$dir/$name.sh"
    [[ -f "$file" ]] && { echo "psy: already exists: $file"; return 1; }

    cat > "$file" << EOF
# psysh-name: $name
# psysh-type: $type
# psysh-version: 0.1.0
# psysh-author: $USER
# psysh-description:
# psysh-dependencies:
# psysh-tags:

EOF
    echo "created: $file"
}

# =========================================================
# Reload
# =========================================================

_psy_reload() {
    # shellcheck source=/dev/null
    source "${BASH_SOURCE[0]}"
    psysh_init
    echo "psysh reloaded"
}

# =========================================================
# Doctor
# =========================================================

_psy_doctor() {
    echo
    echo "psysh diagnostics"
    echo "------------------"
    echo "  PSYSH_HOME:          $PSYSH_HOME"
    echo "  PSYSH_GITHUB_USER:   ${PSYSH_GITHUB_USER:-<not set>}"
    echo "  PSYSH_GITHUB_REPO:   $PSYSH_GITHUB_REPO"
    echo "  PSYSH_GITHUB_BRANCH: $PSYSH_GITHUB_BRANCH"
    echo "  Token set:           $( [[ -n "$PSYSH_GITHUB_TOKEN" ]] && echo yes || echo no )"
    echo "  Plugins installed:   $(find "$PSYSH_PLUGIN_DIR" -name '*.sh' 2>/dev/null | wc -l)"
    echo "  Themes installed:    $(find "$PSYSH_THEME_DIR"  -name '*.sh' 2>/dev/null | wc -l)"
    echo "  Enabled plugins:     $(grep -c . "$PSYSH_ENABLED_PLUGINS" 2>/dev/null || echo 0)"
    echo "  Active theme:        $( [[ -f "$PSYSH_ENABLED_THEME" ]] && cat "$PSYSH_ENABLED_THEME" || echo none )"
    echo "  Shell:               $SHELL"
    echo "  MSYSTEM:             ${MSYSTEM:-<not set>}"
    echo "  curl:                $(command -v curl 2>/dev/null || echo NOT FOUND)"
    echo
}

# =========================================================
# Fetch
# =========================================================

_psy_fetch() {
    local target="$1"
    _psy_require_curl || return 1

    local auth=()
    [[ -n "$PSYSH_GITHUB_TOKEN" ]] && auth=(-H "Authorization: Bearer $PSYSH_GITHUB_TOKEN")

    local raw_url dest http_code

    raw_url=$(_psy_raw_url "plugins/$target.sh")
    dest="$PSYSH_PLUGIN_DIR/$target.sh"
    http_code=$(curl -fsSL "${auth[@]}" -w "%{http_code}" -o "$dest" "$raw_url" 2>/dev/null)
    if [[ "$http_code" == "200" ]]; then
        echo "fetched plugin: $target  →  $dest"
        return
    fi
    rm -f "$dest"

    raw_url=$(_psy_raw_url "themes/$target.sh")
    dest="$PSYSH_THEME_DIR/$target.sh"
    http_code=$(curl -fsSL "${auth[@]}" -w "%{http_code}" -o "$dest" "$raw_url" 2>/dev/null)
    if [[ "$http_code" == "200" ]]; then
        echo "fetched theme: $target  →  $dest"
        return
    fi
    rm -f "$dest"

    echo "psy: '$target' not found in registry (${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO})"
    return 1
}

# =========================================================
# Search
# =========================================================

_psy_search() {
    local term="$1"
    _psy_require_curl || return 1
    if [[ -z "$term" ]]; then
        echo "Usage: psy search <term>"
        return 1
    fi

    local auth=()
    [[ -n "$PSYSH_GITHUB_TOKEN" ]] && auth=(-H "Authorization: Bearer $PSYSH_GITHUB_TOKEN")

    local api_url="https://api.github.com/repos/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}/git/trees/${PSYSH_GITHUB_BRANCH}?recursive=1"
    local result
    result=$(curl -fsSL "${auth[@]}" "$api_url" 2>/dev/null)

    if [[ -z "$result" ]]; then
        echo "psy: registry unavailable"
        return 1
    fi

    echo
    echo "Searching registry for: $term"

    local kind
    for kind in plugins themes; do
        echo
        echo "$kind"
        echo "-------"
        echo "$result" \
            | grep -o '"path": *"[^"]*"' \
            | sed 's/"path": *"//;s/"//' \
            | grep "^$kind/" \
            | sed "s|^$kind/||;s|\.sh$||" \
            | grep -i "$term" \
            | while IFS= read -r name; do
                [[ -f "$PSYSH_PLUGIN_DIR/$name.sh" || -f "$PSYSH_THEME_DIR/$name.sh" ]] \
                    && echo "  $name  [installed]" \
                    || echo "  $name"
            done
    done
    echo
}

# =========================================================
# Upload
# =========================================================

_psy_upload() {
    local target="$1"
    _psy_require_curl || return 1

    if [[ -z "$PSYSH_GITHUB_TOKEN" ]]; then
        echo "psy: PSYSH_GITHUB_TOKEN is required for upload"
        return 1
    fi

    local file
    file=$(_psy_find_local "$target")
    if [[ -z "$file" ]]; then
        echo "psy: not found locally: $target"
        return 1
    fi

    local type
    type=$(_psy_get_meta "$file" "type")
    [[ -z "$type" ]] && type="plugin"

    local remote_path="${type}s/$target.sh"
    local api_url
    api_url=$(_psy_api_url "$remote_path")

    local content
    content=$(base64 < "$file" | tr -d '\n')

    local sha=""
    local existing
    existing=$(curl -fsSL \
        -H "Authorization: Bearer $PSYSH_GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "$api_url" 2>/dev/null)
    echo "$existing" | grep -q '"sha"' && \
        sha=$(echo "$existing" | grep -o '"sha":"[^"]*"' | head -n1 | sed 's/"sha":"//;s/"//')

    local payload
    if [[ -n "$sha" ]]; then
        payload="{\"message\":\"update $remote_path\",\"content\":\"$content\",\"sha\":\"$sha\",\"branch\":\"$PSYSH_GITHUB_BRANCH\"}"
    else
        payload="{\"message\":\"add $remote_path\",\"content\":\"$content\",\"branch\":\"$PSYSH_GITHUB_BRANCH\"}"
    fi

    local http_code
    http_code=$(curl -fsSL \
        -X PUT \
        -H "Authorization: Bearer $PSYSH_GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        -w "%{http_code}" -o /dev/null \
        "$api_url" 2>/dev/null)

    [[ "$http_code" == "200" || "$http_code" == "201" ]] \
        && echo "uploaded: $remote_path  →  github.com/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}" \
        || { echo "psy: upload failed (HTTP $http_code)"; return 1; }
}

# =========================================================
# Main
# =========================================================

psy() {
    local cmd="$1"
    shift

    case "$cmd" in
        list)    _psy_print_header; _psy_list_plugins; _psy_list_themes ;;
        enable)  _psy_enable  "$1" ;;
        disable) _psy_disable "$1" ;;
        info)    _psy_info    "$1" ;;
        create)  _psy_create  "$1" "$2" ;;
        reload)  _psy_reload ;;
        doctor)  _psy_doctor ;;
        fetch)   _psy_fetch  "$1" ;;
        upload)  _psy_upload "$1" ;;
        search)  _psy_search "$1" ;;
        *)
            echo
            echo "psysh runtime manager"
            echo
            echo "Commands"
            echo "--------"
            echo "  psy list"
            echo "  psy enable  <name>"
            echo "  psy disable <name>"
            echo "  psy info    <name>"
            echo "  psy create  <plugin|theme> <name>"
            echo "  psy reload"
            echo "  psy doctor"
            echo "  psy fetch   <name>"
            echo "  psy upload  <name>"
            echo "  psy search  <term>"
            echo
            echo "Environment"
            echo "-----------"
            echo "  PSYSH_HOME           default: ~/.psysh"
            echo "  PSYSH_GITHUB_USER    registry owner       (default: awesomemad)"
            echo "  PSYSH_GITHUB_REPO    registry repo        (default: psysh-reg-official)"
            echo "  PSYSH_GITHUB_BRANCH  registry branch      (default: main)"
            echo "  PSYSH_GITHUB_TOKEN   fine-grained PAT     (upload only)"
            echo "  PSYSH_DEP_LINE_LIMIT logical line limit   (default: 137)"
            echo "  PSYSH_DEP_COUNT_LIMIT dep count limit     (default: 4)"
            echo
            ;;
    esac
}
