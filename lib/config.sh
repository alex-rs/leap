#!/usr/bin/env bash

config_path() {
  echo ".leap/config"
}

config_read() {
  local path
  path="$(config_path)"
  [[ -f "$path" ]] || return 0
  declare -gA LEAP_CONFIG
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    LEAP_CONFIG["$key"]="$value"
  done < "$path"
}

config_write() {
  local path
  path="$(config_path)"
  mkdir -p "$(dirname "$path")"
  : > "$path"
  for key in "${!LEAP_CONFIG[@]}"; do
    printf '%s=%s\n' "$key" "${LEAP_CONFIG[$key]}" >> "$path"
  done
}

config_get() {
  local key="$1"
  local path
  path="$(config_path)"
  [[ -f "$path" ]] || return 1
  local val
  val="$(grep -m1 "^${key}=" "$path" | cut -d= -f2-)"
  printf '%s' "$val"
}

config_set() {
  local key="$1"
  local value="$2"
  local path
  path="$(config_path)"
  mkdir -p "$(dirname "$path")"
  if [[ -f "$path" ]] && grep -q "^${key}=" "$path"; then
    local tmp
    tmp="$(mktemp "${path}.XXXXXX")"
    while IFS= read -r line; do
      if [[ "$line" == "${key}="* ]]; then
        printf '%s=%s\n' "$key" "$value"
      else
        printf '%s\n' "$line"
      fi
    done < "$path" > "$tmp"
    mv "$tmp" "$path"
  else
    printf '%s=%s\n' "$key" "$value" >> "$path"
  fi
}

config_exists() {
  [[ -f "$(config_path)" ]]
}
