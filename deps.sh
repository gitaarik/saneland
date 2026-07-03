#!/usr/bin/env bash
#
# deps.sh — install saneland's runtime dependencies for your distro.
#
# Detects the distro from /etc/os-release, maps the canonical dependency
# manifest (deps/manifest.sh) to real package names via the matching
# deps/<distro>.sh module, prints the plan, and offers to install the
# repo-available packages.
#
# Usage:
#   ./deps.sh              detect, show the plan, prompt to install core deps
#   ./deps.sh --print      show the plan only (no install)
#   ./deps.sh --optional   include the optional deps (hyprlock, hyprshot, …)
#
# AUR packages and "build from source" items are listed but never auto-run —
# you install those yourself.

set -euo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/deps/manifest.sh"

PRINT=0; WITH_OPTIONAL=0
for a in "$@"; do
  case $a in
    --print)    PRINT=1 ;;
    --optional) WITH_OPTIONAL=1 ;;
    -h|--help)  sed -n '2,/^set /p' "$0" | sed 's/^# \?//; $d'; exit 0 ;;
    *) echo "unknown argument: $a (try --help)" >&2; exit 1 ;;
  esac
done

# --- detect distro (ID, then the ID_LIKE family) ---------------------------
ID=""; ID_LIKE=""
[[ -r /etc/os-release ]] && . /etc/os-release
distro=""
for cand in "${ID:-}" ${ID_LIKE:-}; do
  case $cand in
    arch)          distro=arch;     break ;;
    fedora|rhel)   distro=fedora;   break ;;
    debian|ubuntu) distro=debian;   break ;;
    opensuse*|suse|sles) distro=opensuse; break ;;
  esac
done

if [[ -z $distro ]]; then
  echo "Couldn't map your distro (ID='${ID:-?}', ID_LIKE='${ID_LIKE:-}')."
  echo "Install the deps manually — see the canonical list in deps/manifest.sh"
  echo "and the README dependency table."
  exit 1
fi
module="$DIR/deps/$distro.sh"
if [[ ! -f $module ]]; then
  echo "No deps module for '$distro' yet — contributions welcome (copy deps/arch.sh)."
  echo "Meanwhile, deps/manifest.sh lists everything saneland needs."
  exit 1
fi
source "$module"

# --- resolve IDs to packages ----------------------------------------------
ids=("${CORE_DEPS[@]}")
[[ $WITH_OPTIONAL == 1 ]] && ids+=("${OPTIONAL_DEPS[@]}")

repo_pkgs=(); aur_pkgs=(); manual=()
for id in "${ids[@]}"; do
  if [[ -n ${PKG[$id]:-} ]]; then
    if [[ " ${AUR_DEPS[*]:-} " == *" $id "* ]]; then
      aur_pkgs+=( ${PKG[$id]} )
    else
      repo_pkgs+=( ${PKG[$id]} )
    fi
  else
    manual+=( "$id — ${DEP_DESC[$id]:-}" )
  fi
done

echo "Distro: $distro"
echo
echo "Repo packages ($PM_INSTALL):"
printf '  %s\n' "${repo_pkgs[@]}"
if [[ ${#aur_pkgs[@]} -gt 0 ]]; then
  echo; echo "AUR packages (${AUR_INSTALL:-<AUR helper>}):"
  printf '  %s\n' "${aur_pkgs[@]}"
fi
if [[ ${#manual[@]} -gt 0 ]]; then
  echo; echo "Build from source / not packaged on $distro:"
  printf '  %s\n' "${manual[@]}"
fi
if [[ ${#MIN_VERSION[@]} -gt 0 ]]; then
  echo; echo "Mind the minimum versions (older packaged builds can break configs):"
  for id in "${!MIN_VERSION[@]}"; do
    printf '  %-22s >= %s\n' "${DEP_DESC[$id]:-$id}" "${MIN_VERSION[$id]}"
  done
fi

echo
echo "Install command:"
echo "  $PM_INSTALL ${repo_pkgs[*]}"
[[ ${#aur_pkgs[@]} -gt 0 ]] && echo "  ${AUR_INSTALL:-<AUR helper>} ${aur_pkgs[*]}"

[[ $PRINT == 1 ]] && exit 0

echo
read -rp "Run the repo install command now? [y/N] " ans
if [[ ${ans,,} == y* ]]; then
  # shellcheck disable=SC2086
  $PM_INSTALL "${repo_pkgs[@]}"
else
  echo "Skipped. Copy the commands above when you're ready."
fi
