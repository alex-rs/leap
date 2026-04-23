#!/usr/bin/env bash

die() {
  echo "[leap] error: $*" >&2
  exit 1
}

info() {
  echo "[leap] $*"
}

warn() {
  echo "[leap] warning: $*" >&2
}

success() {
  echo "[leap] ✓ $*"
}

ask() {
  local prompt="$1"
  local default="${2:-}"
  if [[ -n "$default" ]]; then
    printf "%s [%s]: " "$prompt" "$default"
  else
    printf "%s: " "$prompt"
  fi
  read -r REPLY
  if [[ -z "$REPLY" && -n "$default" ]]; then
    REPLY="$default"
  fi
}

ask_yn() {
  local prompt="$1"
  local default="${2:-n}"
  local display
  if [[ "$default" =~ ^[Yy] ]]; then
    display="Y/n"
  else
    display="y/N"
  fi
  printf "%s [%s]: " "$prompt" "$display"
  read -r REPLY
  if [[ -z "$REPLY" ]]; then
    REPLY="$default"
  fi
  [[ "$REPLY" =~ ^[Yy] ]]
}

ask_choice() {
  local prompt="$1"
  local options_str="$2"
  local -a options
  read -r -a options <<< "$options_str"
  echo "$prompt:"
  local i=1
  for opt in "${options[@]}"; do
    printf "  %d) %s\n" "$i" "$opt"
    ((i++))
  done
  printf "Choice [1]: "
  read -r REPLY
  if [[ -z "$REPLY" ]]; then
    REPLY="${options[0]}"
    return
  fi
  if [[ "$REPLY" =~ ^[0-9]+$ ]]; then
    local idx=$(( REPLY - 1 ))
    if (( idx >= 0 && idx < ${#options[@]} )); then
      REPLY="${options[$idx]}"
      return
    fi
  fi
  for opt in "${options[@]}"; do
    if [[ "$opt" == "$REPLY" ]]; then
      return
    fi
  done
  die "Invalid choice: $REPLY"
}

ask_multi() {
  local prompt="$1"
  local default="${2:-}"
  if [[ -n "$default" ]]; then
    printf "%s [%s]: " "$prompt" "$default"
  else
    printf "%s: " "$prompt"
  fi
  read -r REPLY
  if [[ -z "$REPLY" && -n "$default" ]]; then
    REPLY="$default"
  fi
}

slugify() {
  local input="$1"
  echo "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/-\+/-/g' \
    | sed 's/^-//;s/-$//'
}

_load_config_into_map() {
  local config_file="$1"
  local -n _map="$2"
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    _map["$key"]="$value"
  done < "$config_file"
}

render_template() {
  local template_file="$1"
  local output_file="$2"
  local config_file="${3:-.leap/config}"

  [[ -f "$config_file" ]] || die "Config file not found: $config_file"
  [[ -f "$template_file" ]] || die "Template file not found: $template_file"

  declare -A _cfg
  _load_config_into_map "$config_file" _cfg

  local content
  content="$(< "$template_file")"

  content="$(render_conditional_content "$content" _cfg)"

  # Write content to a temp file so we can use awk for substitution.
  # Bash // replacement treats & and \ as special in the replacement
  # string, corrupting URLs and descriptions with those characters.
  local _tmpfile
  _tmpfile="$(mktemp)"
  printf '%s\n' "$content" > "$_tmpfile"

  for key in "${!_cfg[@]}"; do
    local val="${_cfg[$key]}"
    local pattern="%%${key}%%"
    _LEAP_PAT="$pattern" _LEAP_REP="$val" \
      awk 'BEGIN{p=ENVIRON["_LEAP_PAT"]; r=ENVIRON["_LEAP_REP"]; gsub(/\\/, "\\\\", r); gsub(/&/, "\\\\&", r)} {gsub(p, r); print}' "$_tmpfile" > "${_tmpfile}.out"
    mv "${_tmpfile}.out" "$_tmpfile"
  done

  ensure_dir "$output_file"
  mv "$_tmpfile" "$output_file"
}

render_conditional_content() {
  local content="$1"
  local -n _rcfg="$2"

  local result=""
  local in_block=0
  local block_active=0
  local in_else=0
  local block_content=""
  local else_content=""

  while IFS= read -r line; do
    if [[ "$line" =~ %%IF[[:space:]]([A-Z_]+)%% ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${_rcfg[$key]:-}"
      in_block=1
      in_else=0
      block_content=""
      else_content=""
      if [[ -n "$val" && "$val" != "false" && "$val" != "none" ]]; then
        block_active=1
      else
        block_active=0
      fi
      continue
    fi
    if [[ "$line" =~ %%ELSE%% ]] && (( in_block )); then
      in_else=1
      continue
    fi
    if [[ "$line" =~ %%ENDIF%% ]]; then
      if (( block_active )); then
        result+="$block_content"
      elif (( in_else )); then
        result+="$else_content"
      fi
      in_block=0
      block_active=0
      in_else=0
      block_content=""
      else_content=""
      continue
    fi
    if (( in_block )); then
      if (( in_else )); then
        else_content+="${line}"$'\n'
      else
        block_content+="${line}"$'\n'
      fi
    else
      result+="${line}"$'\n'
    fi
  done <<< "$content"

  printf '%s' "$result"
}

ensure_dir() {
  local file="$1"
  local dir
  dir="$(dirname "$file")"
  mkdir -p "$dir"
}

copy_template() {
  local src="$1"
  local dst="$2"
  local config_file="${3:-.leap/config}"

  ensure_dir "$dst"

  if [[ "$src" == *.tmpl ]]; then
    local dst_stripped="${dst%.tmpl}"
    render_template "$src" "$dst_stripped" "$config_file"
    dst="$dst_stripped"
  else
    cp "$src" "$dst"
  fi

  if file "$dst" 2>/dev/null | grep -q 'shell script\|bash\|sh script'; then
    chmod +x "$dst"
  fi
  if head -1 "$dst" 2>/dev/null | grep -qE '^#!.*(ba)?sh'; then
    chmod +x "$dst"
  fi
}
