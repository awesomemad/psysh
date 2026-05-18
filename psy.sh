#!/usr/bin/env bash

# =========================================================
# psysh Core Runtime Manager
# =========================================================

export PSYSH_HOME="${PSYSH_HOME:-$HOME/.psysh}"
export PSYSH_PLUGIN_DIR="$PSYSH_HOME/plugins"
export PSYSH_THEME_DIR="$PSYSH_HOME/themes"
export PSYSH_CACHE_DIR="$PSYSH_HOME/cache"
export PSYSH_LOG_DIR="$PSYSH_HOME/logs"

# Plain-text lists of enabled names (one name per line)
export PSYSH_ENABLED_PLUGINS="$PSYSH_HOME/enabled_plugins"
export PSYSH_ENABLED_THEME="$PSYSH_HOME/enabled_theme"

# GitHub registry settings — set these in your environment or ~/.bashrc
# PSYSH_GITHUB_USER   → your GitHub username
# PSYSH_GITHUB_REPO   → registry repo name (default: psysh-registry)
# PSYSH_GITHUB_TOKEN  → personal access token (needed for upload)
export PSYSH_GITHUB_USER="${PSYSH_GITHUB_USER:-awesomemad}"
export PSYSH_GITHUB_REPO="${PSYSH_GITHUB_REPO:-psysh-reg-official}"
export PSYSH_GITHUB_BRANCH="${PSYSH_GITHUB_BRANCH:-main}"

# =========================================================
# Init — source enabled components (call this from .bashrc)
# =========================================================

psysh_init() {
    # Track what has already been sourced this session (avoid double-sourcing deps)
    declare -A _psy_sourced 2>/dev/null || true

    # Source a single plugin by name, respecting deps. Internal use only.
    _psy_source_plugin() {
        local name="$1"

        # Already sourced this session — skip
        [[ -n "${_psy_sourced[$name]}" ]] && return

        local file=""

        # Resolve plugin OR theme (plugin has priority here, you can swap if needed)
        if [[ -f "$PSYSH_PLUGIN_DIR/$name.sh" ]]; then
            file="$PSYSH_PLUGIN_DIR/$name.sh"
        elif [[ -f "$PSYSH_THEME_DIR/$name.sh" ]]; then
            file="$PSYSH_THEME_DIR/$name.sh"
        else
            echo "psysh: plugin/theme not found (skipping): $name" >&2
            return
        fi

        # Resolve dependencies first (comma or space separated)
        local deps dep
        deps=$(_psy_get_meta "$file" "dependencies")

        if [[ -n "$deps" ]]; then
            for dep in ${deps//,/ }; do
                dep="${dep// /}"   # trim spaces
                [[ -z "$dep" ]] && continue

                if [[ -z "${_psy_sourced[$dep]}" ]]; then
                    if [[ -f "$PSYSH_PLUGIN_DIR/$dep.sh" ]] || [[ -f "$PSYSH_THEME_DIR/$dep.sh" ]]; then
                        _psy_source_plugin "$dep"
                    else
                        echo "psysh: missing dependency '$dep' for '$name' (skipping $name)" >&2
                        return
                    fi
                fi
            done
        fi

        # shellcheck source=/dev/null
        source "$file"

        _psy_sourced["$name"]=1
    }
    # Source enabled plugins (list is already dep-ordered from psy enable,
    # but _psy_source_plugin enforces it again at runtime to be safe)
    if [[ -f "$PSYSH_ENABLED_PLUGINS" ]]; then
        while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            _psy_source_plugin "$name"
        done < "$PSYSH_ENABLED_PLUGINS"
    fi

    # Source enabled theme (only one, same dep logic)
    if [[ -f "$PSYSH_ENABLED_THEME" ]]; then
        local theme_name
        theme_name=$(< "$PSYSH_ENABLED_THEME")
        if [[ -n "$theme_name" ]]; then
            local theme_file="$PSYSH_THEME_DIR/$theme_name.sh"
            if [[ -f "$theme_file" ]]; then
                # Check theme deps too
                local deps
                deps=$(_psy_get_meta "$theme_file" "dependencies")
                if [[ -n "$deps" ]]; then
                    local dep
                    for dep in ${deps//,/ }; do
                        dep="${dep// /}"
                        [[ -z "$dep" ]] && continue
                        [[ -z "${_psy_sourced[$dep]}" ]] && _psy_source_plugin "$dep"
                    done
                fi
                # shellcheck source=/dev/null
                source "$theme_file"
            else
                echo "psysh: theme not found (skipping): $theme_name" >&2
            fi
        fi
    fi

    unset -f _psy_source_plugin
}

# =========================================================
# Internal Helpers
# =========================================================

_psy_require_curl() {
    command -v curl >/dev/null 2>&1 || {
        echo "psy: curl is required but not found"
        return 1
    }
}

_psy_api_url() {
    # $1 = path within repo, e.g. "plugins/myplugin.sh"
    echo "https://api.github.com/repos/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}/contents/$1"
}

_psy_raw_url() {
    echo "https://raw.githubusercontent.com/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}/${PSYSH_GITHUB_BRANCH}/$1"
}

_psy_get_meta() {
    local file="$1"
    local key="$2"
    grep "^# psysh-$key:" "$file" | head -n1 | sed "s/^# psysh-$key:[ ]*//"
}

_psy_find_local() {
    local name="$1"
    if [[ -f "$PSYSH_PLUGIN_DIR/$name.sh" ]]; then
        echo "$PSYSH_PLUGIN_DIR/$name.sh"
    elif [[ -f "$PSYSH_THEME_DIR/$name.sh" ]]; then
        echo "$PSYSH_THEME_DIR/$name.sh"
    fi
}

_psy_is_plugin_enabled() {
    grep -qx "$1" "$PSYSH_ENABLED_PLUGINS" 2>/dev/null
}

_psy_auth_header() {
    if [[ -n "$PSYSH_GITHUB_TOKEN" ]]; then
        echo "-H" "Authorization: Bearer $PSYSH_GITHUB_TOKEN"
    fi
}

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
        if _psy_is_plugin_enabled "$name"; then
            echo "  [enabled]  $name"
        else
            echo "  [disabled] $name"
        fi
    done
}

_psy_list_themes() {
    echo
    echo "Themes"
    echo "------"
    local active_theme=""
    [[ -f "$PSYSH_ENABLED_THEME" ]] && active_theme=$(< "$PSYSH_ENABLED_THEME")

    for f in "$PSYSH_THEME_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f" .sh)
        if [[ "$name" == "$active_theme" ]]; then
            echo "  [enabled]  $name"
        else
            echo "  [disabled] $name"
        fi
    done
}

# =========================================================
# Enable / Disable
# =========================================================

# Thresholds for dep bloat detection (logical lines — comments, blanks, structural lines excluded)
PSYSH_DEP_LINE_LIMIT="${PSYSH_DEP_LINE_LIMIT:-137}"
PSYSH_DEP_COUNT_LIMIT="${PSYSH_DEP_COUNT_LIMIT:-4}"

_psy_logical_lines() {
    grep -cvE '^\s*(#|$|\{|\}|;;|esac|fi|done|then|do|else)\s*$' "$1" 2>/dev/null || echo 0
}

# Resolve dependencies for a given file.
# Populates two arrays in the caller's scope:
#   _deps_needed  — dep names not yet enabled (need to be added)
#   _deps_missing — dep names not on disk (must be fetched first)
_psy_resolve_deps() {
    local file="$1"
    _deps_needed=()
    _deps_missing=()

    local raw
    raw=$(_psy_get_meta "$file" "dependencies")
    [[ -z "$raw" ]] && return

    local dep
    for dep in ${raw//,/ }; do
        dep="${dep// /}"
        [[ -z "$dep" ]] && continue
        if _psy_is_plugin_enabled "$dep"; then
            continue   # already in the list — nothing to do
        fi
        local dep_file
        dep_file=$(_psy_find_local "$dep")
        if [[ -z "$dep_file" ]]; then
            _deps_missing+=("$dep")
        else
            _deps_needed+=("$dep")
        fi
    done
}

# Decide whether the dep set is lightweight (auto) or heavy (ask).
# Returns 0 = auto, 1 = ask
_psy_deps_are_heavy() {
    local -n needed="$1"   # nameref to _deps_needed array

    # Too many deps → ask
    if (( ${#needed[@]} >= PSYSH_DEP_COUNT_LIMIT )); then
        return 1
    fi

    # Any dep file is large → ask
    local dep
    for dep in "${needed[@]}"; do
        local dep_file
        dep_file=$(_psy_find_local "$dep")
        local lines
        lines=$(_psy_logical_lines "$dep_file")
        if (( lines >= PSYSH_DEP_LINE_LIMIT )); then
            return 1
        fi
    done

    return 0   # lightweight — auto is fine
}

# Print dep summary and ask [y/N]. Returns 0 if user said yes.
_psy_ask_deps() {
    local -n needed="$1"

    echo
    echo "  Dependencies required:"
    local dep
    for dep in "${needed[@]}"; do
        local dep_file lines
        dep_file=$(_psy_find_local "$dep")
        lines=$(_psy_logical_lines "$dep_file")
        printf "    %-20s  %s lines\n" "$dep" "$lines"
    done
    echo
    read -rp "  Enable all of the above? [y/N] " answer
    [[ "${answer,,}" == "y" ]]
}

_psy_do_enable_deps() {
    local -n needed="$1"
    local dep
    for dep in "${needed[@]}"; do
        echo "  → pulled in dependency: $dep"
        echo "$dep" >> "$PSYSH_ENABLED_PLUGINS"
    done
}

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

    # Resolve deps — populates _deps_needed and _deps_missing
    local _deps_needed=() _deps_missing=()
    _psy_resolve_deps "$file"

    # Hard stop — missing deps must be fetched first
    if (( ${#_deps_missing[@]} > 0 )); then
        echo "psy: missing dependencies (not on disk):"
        local m
        for m in "${_deps_missing[@]}"; do
            echo "    psy fetch $m"
        done
        return 1
    fi

    # Handle deps that need enabling
    if (( ${#_deps_needed[@]} > 0 )); then
        if _psy_deps_are_heavy _deps_needed; then
            # Lightweight — just do it and report
            _psy_do_enable_deps _deps_needed
        else
            # Heavy — ask first
            if ! _psy_ask_deps _deps_needed; then
                echo "psy: aborted"
                return 1
            fi
            _psy_do_enable_deps _deps_needed
        fi
    fi

    # Now enable the target itself
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

    echo "→ run 'psy reload' to apply (some plugins may require reloading your shell directly)"
}

_psy_disable() {
    local target="$1"

    # Try plugin list first
    if _psy_is_plugin_enabled "$target"; then
        grep -vx "$target" "$PSYSH_ENABLED_PLUGINS" > "$PSYSH_ENABLED_PLUGINS.tmp" \
            && mv "$PSYSH_ENABLED_PLUGINS.tmp" "$PSYSH_ENABLED_PLUGINS"
        echo "disabled plugin: $target"
        echo "→ run 'psy reload' to apply (some plugins may require reloading your shell directly)"
        return
    fi

    # Try theme
    if [[ -f "$PSYSH_ENABLED_THEME" ]] && [[ "$(cat "$PSYSH_ENABLED_THEME")" == "$target" ]]; then
        rm -f "$PSYSH_ENABLED_THEME"
        echo "disabled theme: $target"
        echo "→ run 'psy reload' to apply (some plugins may require reloading your shell directly)"
        return
    fi

    echo "psy: not currently enabled: $target"
}

# =========================================================
# Info
# =========================================================

_psy_info() {
    local target="$1"
    local file
    file=$(_psy_find_local "$target")

    if [[ -z "$file" ]]; then
        echo "psy: not found locally: $target"
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
    local type="$1"
    local name="$2"

    if [[ -z "$type" || -z "$name" ]]; then
        echo "Usage: psy create {plugin|theme} <name>"
        return 1
    fi

    local dir
    case "$type" in
        plugin) dir="$PSYSH_PLUGIN_DIR" ;;
        theme)  dir="$PSYSH_THEME_DIR"  ;;
        *)
            echo "psy: invalid type (use 'plugin' or 'theme')"
            return 1
            ;;
    esac

    local file="$dir/$name.sh"
    if [[ -f "$file" ]]; then
        echo "psy: already exists: $file"
        return 1
    fi

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
# Reload — re-source this file + re-run init
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
    echo "  PSYSH_HOME:         $PSYSH_HOME"
    echo "  PSYSH_GITHUB_USER:  ${PSYSH_GITHUB_USER:-<not set>}"
    echo "  PSYSH_GITHUB_REPO:  $PSYSH_GITHUB_REPO"
    echo "  PSYSH_GITHUB_BRANCH:$PSYSH_GITHUB_BRANCH"
    echo "  Token set:          $( [[ -n "$PSYSH_GITHUB_TOKEN" ]] && echo yes || echo no )"
    echo "  Plugins installed:  $(find "$PSYSH_PLUGIN_DIR" -name '*.sh' 2>/dev/null | wc -l)"
    echo "  Themes installed:   $(find "$PSYSH_THEME_DIR"  -name '*.sh' 2>/dev/null | wc -l)"
    echo "  Enabled plugins:    $(grep -c . "$PSYSH_ENABLED_PLUGINS" 2>/dev/null || echo 0)"
    echo "  Active theme:       $( [[ -f "$PSYSH_ENABLED_THEME" ]] && cat "$PSYSH_ENABLED_THEME" || echo none )"
    echo "  Shell:              $SHELL"
    echo "  MSYSTEM:            ${MSYSTEM:-<not set>}"
    echo "  curl:               $(command -v curl 2>/dev/null || echo NOT FOUND)"
    echo
}

# =========================================================
# Fetch — download a single file via GitHub raw URL
# =========================================================

_psy_fetch() {
    local target="$1"
    _psy_require_curl || return 1

    local dest http_code

    # Try plugin first
    local raw_url
    raw_url=$(_psy_raw_url "plugins/$target.sh")
    dest="$PSYSH_PLUGIN_DIR/$target.sh"

    http_code=$(curl -fsSL \
        $( [[ -n "$PSYSH_GITHUB_TOKEN" ]] && echo "-H" && echo "Authorization: Bearer $PSYSH_GITHUB_TOKEN" ) \
        -w "%{http_code}" -o "$dest" "$raw_url" 2>/dev/null)

    if [[ "$http_code" == "200" ]]; then
        echo "fetched plugin: $target  →  $dest"
        return
    fi
    rm -f "$dest"

    # Try theme
    raw_url=$(_psy_raw_url "themes/$target.sh")
    dest="$PSYSH_THEME_DIR/$target.sh"

    http_code=$(curl -fsSL \
        $( [[ -n "$PSYSH_GITHUB_TOKEN" ]] && echo "-H" && echo "Authorization: Bearer $PSYSH_GITHUB_TOKEN" ) \
        -w "%{http_code}" -o "$dest" "$raw_url" 2>/dev/null)

    if [[ "$http_code" == "200" ]]; then
        echo "fetched theme: $target  →  $dest"
        return
    fi
    rm -f "$dest"

    echo "psy: '$target' not found in registry (${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO})"
    return 1
}

# =========================================================
# Search — query GitHub API for matching files (no clone)
# =========================================================

_psy_search() {
    local term="$1"
    _psy_require_curl || return 1

    if [[ -z "$term" ]]; then
        echo "Usage: psy search <term>"
        return 1
    fi

    local auth_args=()
    [[ -n "$PSYSH_GITHUB_TOKEN" ]] && auth_args=(-H "Authorization: Bearer $PSYSH_GITHUB_TOKEN")

    echo
    echo "Searching registry for: $term"

    for kind in plugins themes; do
        echo
        echo "$kind"
        echo "-------"

        # List files in the folder via GitHub Trees API (single request, no clone)
        local api_url="https://api.github.com/repos/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}/git/trees/${PSYSH_GITHUB_BRANCH}?recursive=1"
        local result

        result=$(curl -fsSL "${auth_args[@]}" "$api_url" 2>/dev/null)

        if [[ -z "$result" ]]; then
            echo "  (registry unavailable)"
            continue
        fi

        # Extract file names from JSON, filter by folder and search term
        echo "$result" \
            | grep -o '"path": *"[^"]*"' \
            | sed 's/"path": *"//;s/"//' \
            | grep "^$kind/" \
            | sed "s|^$kind/||;s|\.sh$||" \
            | grep -i "$term" \
            | while read -r name; do
                if [[ -f "$PSYSH_PLUGIN_DIR/$name.sh" || -f "$PSYSH_THEME_DIR/$name.sh" ]]; then
                    echo "  $name  [installed]"
                else
                    echo "  $name"
                fi
            done
    done

    echo
}

# =========================================================
# Upload — push a single local file to GitHub via API
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

    # Base64-encode the file content
    local content
    content=$(base64 < "$file" | tr -d '\n')

    # Check if the file already exists (to get its SHA for update)
    local sha=""
    local existing
    existing=$(curl -fsSL \
        -H "Authorization: Bearer $PSYSH_GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "$api_url" 2>/dev/null)

    if echo "$existing" | grep -q '"sha"'; then
        sha=$(echo "$existing" | grep -o '"sha":"[^"]*"' | head -n1 | sed 's/"sha":"//;s/"//')
    fi

    # Build JSON payload
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

    if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
        echo "uploaded: $remote_path  →  github.com/${PSYSH_GITHUB_USER}/${PSYSH_GITHUB_REPO}"
    else
        echo "psy: upload failed (HTTP $http_code)"
        return 1
    fi
}

# =========================================================
# Main Command
# =========================================================

psy() {
    local cmd="$1"
    shift

    case "$cmd" in
        list)
            _psy_print_header
            _psy_list_plugins
            _psy_list_themes
            ;;
        enable)   _psy_enable  "$1" ;;
        disable)  _psy_disable "$1" ;;
        info)     _psy_info    "$1" ;;
        create)   _psy_create  "$1" "$2" ;;
        reload)   _psy_reload ;;
        doctor)   _psy_doctor ;;
        fetch)    _psy_fetch  "$1" ;;
        upload)   _psy_upload "$1" ;;
        search)   _psy_search "$1" ;;
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
            echo "  PSYSH_HOME          default: ~/.psysh"
            echo "  PSYSH_GITHUB_USER   your GitHub username (required)"
            echo "  PSYSH_GITHUB_REPO   registry repo        (default: psysh-registry)"
            echo "  PSYSH_GITHUB_BRANCH branch               (default: main)"
            echo "  PSYSH_GITHUB_TOKEN  PAT for upload/private repos"
            echo
            ;;
    esac
}
