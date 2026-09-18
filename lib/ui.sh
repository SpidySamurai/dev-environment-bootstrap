#!/usr/bin/env bash

# T3: the default path is a single yes/no confirmation, not a multi-select
# menu. All interactive reads come from /dev/tty (never stdin), so
# `curl -fsSL <url> | bash` keeps working: stdin is the piped script, and
# only /dev/tty can carry a real answer.

# Isolated so tests can exercise confirm_full_install without a real
# controlling terminal: /dev/tty is only opened here.
prompt_full_install_confirmation() {
  local answer
  printf '%s' 'Install the complete Spidy environment? [Y/n] ' >/dev/tty
  read -r answer </dev/tty
  printf '%s' "$answer"
}

confirm_full_install() {
  ((ASSUME_YES)) && return 0
  ((NON_INTERACTIVE)) && return 0

  if ! has_readable_tty; then
    printf '%s\n' 'No interactive terminal is available; re-run with --yes or --non-interactive to proceed without a prompt.' >&2
    return 1
  fi

  local answer
  answer=$(prompt_full_install_confirmation)
  [[ -z $answer || $answer =~ ^[Yy]([Ee][Ss])?$ ]]
}

# --- Grouped installation panel ------------------------------------------
#
# Renders the resolved module plan grouped by MODULE_GROUP (lib/modules.sh)
# instead of a flat bullet list. This is presentation only: it never
# changes selection (the whole environment is still one yes/no decision
# via confirm_full_install above) and it draws natively in ANSI/box-drawing
# characters — gum is not available on a fresh host and the panel renders
# before anything is installed.
#
# Fallback group for any module the catalog forgot to assign a group to,
# so a module can never silently disappear from the panel.
UI_FALLBACK_GROUP='Other modules'

# True (0) only when it is safe to draw color/box-drawing: a real TTY,
# NO_COLOR unset, and TERM not "dumb". Otherwise the panel must degrade to
# clean plain text (piped output, redirected to a file, a pager, CI logs).
ui_colors_enabled() {
  [[ -t 1 ]] || return 1
  [[ -z ${NO_COLOR:-} ]] || return 1
  [[ ${TERM:-} != dumb ]] || return 1
  return 0
}

# Terminal width for the panel box, clamped to a sane range so a huge or a
# tiny/unknown COLUMNS/tput value can't produce a broken layout.
ui_panel_width() {
  local cols=${COLUMNS:-}
  if [[ ! $cols =~ ^[0-9]+$ ]] && command -v tput >/dev/null 2>&1; then
    cols=$(tput cols 2>/dev/null || true)
  fi
  [[ $cols =~ ^[0-9]+$ ]] || cols=80
  ((cols < 44)) && cols=44
  ((cols > 100)) && cols=100
  printf '%s' "$cols"
}

module_panel_group() {
  printf '%s' "${MODULE_GROUP[$1]:-$UI_FALLBACK_GROUP}"
}

is_mandatory_module() {
  local module=$1 candidate
  for candidate in "${MANDATORY_MODULES[@]}"; do
    [[ "$candidate" == "$module" ]] && return 0
  done
  return 1
}

# Reflects real, cheaply-known state (the same local checks execution uses
# to decide whether to skip a module) instead of implying every module will
# be freshly installed. module_install_status only does local checks
# (dpkg-query, command -v, file tests) so calling it here is safe. The panel
# only says whether it is already there — the managed-vs-alternate-source
# distinction is provenance detail that belongs to --audit and the
# installation report, not to "here is what you're about to install".
module_panel_marker() {
  local module=$1
  if module_install_status "$module" >/dev/null 2>&1; then
    printf ' ✓ already installed'
  fi
}

module_panel_label() {
  local module=$1 label=${MODULE_TITLE[$module]:-$module}
  is_mandatory_module "$module" && label+=' (mandatory)'
  label+="$(module_panel_marker "$module")"
  printf '%s' "$label"
}

# Locale-safe visible-column count: strips ANSI SGR escapes first, then
# counts characters under a pinned UTF-8 locale. Under an inherited
# LC_ALL=C (byte-oriented) locale, bash's ${#string} counts a multi-byte
# glyph like the bullet (•), the check mark (✓), or the ellipsis (…) by its
# raw byte length instead of its single visible column — that mismatch is
# exactly what let panel lines drift past the box's right border. Pinning
# the locale locally (not exported) fixes the count without leaking outside
# this function.
visible_length() {
  local LC_ALL=C.UTF-8
  local stripped
  stripped=$(printf '%s' "$1" | sed -E $'s/\x1b\\[[0-9;]*m//g')
  printf '%s' "${#stripped}"
}

# Fits plain (uncolored) text to at most $2 visible columns, truncating with
# a single trailing ellipsis when it doesn't fit. Never mid-word-breaks a
# module title into something unreadable — a long title is truncated
# cleanly instead, and the box still lands on the same right-hand column on
# every line.
visible_fit() {
  local LC_ALL=C.UTF-8
  local text=$1 max=$2
  # NOTE: `len=${#text}` must NOT be folded into the `local text=... len=...`
  # declaration above — bash expands every RHS in a compound `local` against
  # the pre-assignment scope, so `${#text}` would see the outer (unset)
  # `text` and always evaluate to 0, silently disabling truncation.
  local len=${#text}
  ((len <= max)) && { printf '%s' "$text"; return 0; }
  ((max <= 1)) && { printf '%s' '…'; return 0; }
  printf '%s%s' "${text:0:max-1}" '…'
}

# Groups RESOLVED_MODULES by module_panel_group, preserving first-appearance
# order, into the globals PANEL_GROUP_ORDER (array of group names) and
# PANEL_GROUP_MODULES (group name -> space-joined module ids).
collect_module_groups() {
  declare -ga PANEL_GROUP_ORDER=()
  declare -gA PANEL_GROUP_MODULES=()
  local module group
  for module in "${RESOLVED_MODULES[@]}"; do
    group=$(module_panel_group "$module")
    if [[ -z ${PANEL_GROUP_MODULES[$group]+x} ]]; then
      PANEL_GROUP_ORDER+=("$group")
      PANEL_GROUP_MODULES[$group]=''
    fi
    PANEL_GROUP_MODULES[$group]+="$module "
  done
}

render_module_panel_plain() {
  collect_module_groups
  local group module_ids module

  printf '\n%s\n' 'Installation summary'
  printf 'Total modules: %d\n' "${#RESOLVED_MODULES[@]}"

  for group in "${PANEL_GROUP_ORDER[@]}"; do
    read -r -a module_ids <<<"${PANEL_GROUP_MODULES[$group]}"
    printf '\n%s (%d)\n' "$group" "${#module_ids[@]}"
    for module in "${module_ids[@]}"; do
      printf '  - %s\n' "$(module_panel_label "$module")"
    done
  done
}

# Prints one box line, padding to the exact content width using the
# locale-safe visible length (never the raw byte/${#} length of a colored
# string). The box must stay rectangular: if a caller ever hands this a
# plain string wider than content_width (it shouldn't — callers pre-fit
# with visible_fit before adding color), this still guarantees the right
# border lands in the same column by falling back to a truncated, uncolored
# rendering of that one line rather than letting it bulge.
panel_fancy_line() {
  local width=$1 colored=$2 plain=$3 content_width plain_len pad
  content_width=$((width - 4))
  plain_len=$(visible_length "$plain")
  if ((plain_len <= content_width)); then
    pad=$((content_width - plain_len))
    printf '│ %s%*s │\n' "$colored" "$pad" ''
  else
    printf '│ %s │\n' "$(visible_fit "$plain" "$content_width")"
  fi
}

render_module_panel_fancy() {
  collect_module_groups
  local width content_width dashes top bottom sep
  width=$(ui_panel_width)
  content_width=$((width - 4))
  dashes=$(printf '─%.0s' $(seq 1 $((width - 2))))
  top="┌${dashes}┐"
  bottom="└${dashes}┘"
  sep="├${dashes}┤"

  local bold=$'\033[1m' reset=$'\033[0m' cyan=$'\033[36m' yellow=$'\033[33m' dim=$'\033[2m'
  local total=${#RESOLVED_MODULES[@]}

  printf '\n%s\n' "$top"
  panel_fancy_line "$width" "${bold}${cyan}Installation summary${reset}" 'Installation summary'
  panel_fancy_line "$width" "Total modules: ${bold}${total}${reset}" "Total modules: $total"

  local group module_ids module header_plain
  local title mandatory_tag marker full no_marker fitted avail bullet_color
  local colored_content colored_line plain_line
  for group in "${PANEL_GROUP_ORDER[@]}"; do
    printf '%s\n' "$sep"
    read -r -a module_ids <<<"${PANEL_GROUP_MODULES[$group]}"
    header_plain=$(visible_fit "$group (${#module_ids[@]})" "$content_width")
    panel_fancy_line "$width" "${bold}${header_plain}${reset}" "$header_plain"

    for module in "${module_ids[@]}"; do
      title=${MODULE_TITLE[$module]:-$module}
      mandatory_tag=''
      is_mandatory_module "$module" && mandatory_tag=' (mandatory)'
      marker=$(module_panel_marker "$module")

      if is_mandatory_module "$module"; then
        bullet_color=$yellow
      else
        bullet_color=$dim
      fi

      # The "  • " prefix is a fixed 4-visible-column constant (never
      # measured with ${#}, so it can never itself drift with the locale).
      avail=$((content_width - 4))
      full="${title}${mandatory_tag}${marker}"
      no_marker="${title}${mandatory_tag}"

      if (($(visible_length "$full") <= avail)); then
        fitted=$full
        colored_content="${no_marker}${dim}${marker}${reset}"
      elif (($(visible_length "$no_marker") <= avail)); then
        # Doesn't fit with the marker: drop the marker rather than truncate
        # it into something unreadable or misleading.
        fitted=$no_marker
        colored_content=$no_marker
      else
        # Even the bare title overflows: truncate it, single ellipsis, so
        # the right border still lands on the same column as every other
        # line (this is what "never break the box" means).
        fitted=$(visible_fit "$no_marker" "$avail")
        colored_content=$fitted
      fi

      colored_line="  ${bullet_color}•${reset} ${colored_content}"
      plain_line="  • ${fitted}"
      panel_fancy_line "$width" "$colored_line" "$plain_line"
    done
  done
  printf '%s\n' "$bottom"
}

# Single entry point install.sh calls: picks fancy vs. plain rendering.
render_module_panel() {
  if ui_colors_enabled; then
    render_module_panel_fancy
  else
    render_module_panel_plain
  fi
}
