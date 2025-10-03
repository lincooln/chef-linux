#!/bin/bash
# chef.sh — Minimal recipe executor for Linux pros
# Usage:
#   ./chef.sh <recipe>    → cook recipe
#   ./chef.sh list [q]    → list recipes (optional search)
# Format: .inf files with [section], ingredients=..., cleanups=...

set -euo pipefail

SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPE_PATHS=("$SELF_PATH/рецепты" "$SELF_PATH/книги_рецептов" "$SELF_PATH")
CLIENT=""
RECIPE_FILE=""
declare -A RECIPE_INGREDIENTS RECIPE_CLEANUPS

# === SUPPORTED DISTROS ===
declare -A DISTRO_MAPPING=(
    ["debian"]="apt" ["ubuntu"]="apt" ["linuxmint"]="apt" ["astra"]="apt" ["kali"]="apt"
    ["alt"]="alt" ["altlinux"]="alt" ["simply"]="apt"
    ["redos"]="dnf" ["fedora"]="dnf" ["rhel"]="dnf" ["centos"]="dnf"
    ["arch"]="pacman" ["manjaro"]="pacman" ["endeavouros"]="pacman"
    ["opensuse"]="zypper" ["suse"]="zypper"
)
declare -A PKGMGR=(
    ["apt"]="apt-get install -y"
    ["alt"]="apt-get install -y"
    ["dnf"]="dnf install -y"
    ["pacman"]="pacman -S --noconfirm"
    ["zypper"]="zypper install -y"
)
declare -A PKGREM=(
    ["apt"]="apt-get remove -y --purge"
    ["alt"]="apt-get remove -y --purge"
    ["dnf"]="dnf remove -y"
    ["pacman"]="pacman -Rns --noconfirm"
    ["zypper"]="zypper remove -y"
)

# === CORE FUNCTIONS ===
detect_client() {
    [[ -f /etc/os-release ]] || { echo "error: /etc/os-release not found" >&2; exit 1; }
    source /etc/os-release
    CLIENT="${ID,,}"
    [[ -n "${DISTRO_MAPPING[$CLIENT]:-}" ]] || { echo "error: unsupported distro '$CLIENT'" >&2; exit 1; }
}

find_recipe() {
    local pattern="*${CLIENT}*.inf"
    for path in "${RECIPE_PATHS[@]}"; do
        [[ -d "$path" ]] || continue
        while IFS= read -rd '' f; do
            RECIPE_FILE="$f"
            return 0
        done < <(find "$path" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
    done
    echo "error: no recipe for '$CLIENT'" >&2
    exit 1
}

load_recipes() {
    local sec=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            sec="${BASH_REMATCH[1]}"
        elif [[ -n "$sec" && "$line" =~ ^ingredients[[:space:]]*=[[:space:]]*(.*) ]]; then
            RECIPE_INGREDIENTS["$sec"]="${BASH_REMATCH[1]}"
        elif [[ -n "$sec" && "$line" =~ ^cleanups[[:space:]]*=[[:space:]]*(.*) ]]; then
            RECIPE_CLEANUPS["$sec"]="${BASH_REMATCH[1]}"
        fi
    done < "$RECIPE_FILE"
}

run_with_privileges() {
    if [[ $EUID -eq 0 ]]; then "$@"; return; fi
    if command -v sudo >/dev/null; then sudo "$@"; return; fi
    echo "error: root required, sudo not found" >&2
    exit 1
}

install_pkgs() {
    local pkgs="$1"
    [[ -z "$pkgs" ]] && return
    local mgr="${PKGMGR[${DISTRO_MAPPING[$CLIENT]}]}"
    run_with_privileges ${mgr} $pkgs
}

remove_pkgs() {
    local pkgs="$1"
    [[ -z "$pkgs" ]] && return
    local mgr="${PKGREM[${DISTRO_MAPPING[$CLIENT]}]}"
    run_with_privileges ${mgr} $pkgs
}

# === LIST COMMAND ===
cmd_list() {
    local search="${1:-}"
    detect_client
    find_recipe
    load_recipes

    local found=()
    for key in "${!RECIPE_INGREDIENTS[@]}" "${!RECIPE_CLEANUPS[@]}"; do
        [[ -n "${RECIPE_INGREDIENTS[$key]:-}${RECIPE_CLEANUPS[$key]:-}" ]] && found+=("$key")
    done

    # Уникальные ключи
    readarray -t unique < <(printf '%s\n' "${found[@]}" | sort -u)

    if [[ -n "$search" ]]; then
        readarray -t unique < <(printf '%s\n' "${unique[@]}" | grep -i "$search")
    fi

    if [[ ${#unique[@]} -eq 0 ]]; then
        echo "no recipes found"
        return
    fi

    for r in "${unique[@]}"; do
        echo "$r"
    done
}

# === COOK COMMAND ===
cmd_cook() {
    local query="$1"
    [[ -z "$query" ]] && { echo "usage: $0 <recipe> | list [search]" >&2; exit 1; }

    detect_client
    find_recipe
    load_recipes

    if [[ -z "${RECIPE_INGREDIENTS[$query]:-}" && -z "${RECIPE_CLEANUPS[$query]:-}" ]]; then
        echo "error: recipe '$query' not found" >&2
        exit 2
    fi

    remove_pkgs "${RECIPE_CLEANUPS[$query]:-}"
    install_pkgs "${RECIPE_INGREDIENTS[$query]:-}"
}

# === MAIN ===
case "${1:-}" in
    list)
        cmd_list "$2"
        ;;
    *)
        cmd_cook "$1"
        ;;
esac
