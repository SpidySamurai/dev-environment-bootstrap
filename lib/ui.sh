#!/usr/bin/env bash

ensure_gum() {
  command -v gum >/dev/null 2>&1 && return 0

  log 'Gum is not installed. Continuing with the plain-terminal selector.'
  return 1
}

print_optional_choices() {
  local module index=1
  for module in "${OPTIONAL_MODULES[@]}"; do
    printf '%2d) %-20s %s\n' "$index" "$module" "${MODULE_TITLE[$module]}" >&2
    index=$((index + 1))
  done
}

choose_with_gum() {
  local module line
  local -a choices=()
  for module in "${OPTIONAL_MODULES[@]}"; do
    choices+=("$module: ${MODULE_TITLE[$module]}")
  done
  while IFS= read -r line; do
    printf '%s\n' "${line%%:*}"
  done < <(gum choose --no-limit --header 'Select optional module groups (Space toggles; Enter confirms)' "${choices[@]}")
}

choose_with_terminal() {
  local answer number
  print_optional_choices
  printf '%s' 'Select optional groups by number (comma-separated), or press Enter for mandatory baseline only: ' >&2
  read -r answer
  [[ -z $answer ]] && return 0

  IFS=',' read -r -a _choice_numbers <<< "$answer"
  for number in "${_choice_numbers[@]}"; do
    if [[ ! $number =~ ^[0-9]+$ ]] || ((number < 1 || number > ${#OPTIONAL_MODULES[@]})); then
      printf 'Invalid selection: %s\n' "$number" >&2
      return 2
    fi
    printf '%s\n' "${OPTIONAL_MODULES[number - 1]}"
  done
}

choose_optional_modules() {
  if ensure_gum; then
    choose_with_gum
  else
    choose_with_terminal
  fi
}

confirm_plan() {
  ((DRY_RUN || NON_INTERACTIVE || ASSUME_YES)) && return 0

  if command -v gum >/dev/null 2>&1; then
    gum confirm 'Proceed with this installation plan?'
    return $?
  fi

  local answer
  printf '%s' 'Proceed with this installation plan? [y/N] ' >&2
  read -r answer
  [[ $answer =~ ^[Yy]([Ee][Ss])?$ ]]
}
