#!/usr/bin/env bash
# lib/agents.sh — leap agents command implementation
# Sourced by bin/leap after lib/utils.sh is loaded.

source "${LEAP_HOME}/lib/config.sh"

# File-level variable so the EXIT trap can always reference it safely.
_LEAP_AGENTS_MERGED_CONFIG=""
trap 'rm -f "$_LEAP_AGENTS_MERGED_CONFIG"' EXIT

leap_agents() {
  local TMPL="${LEAP_HOME}/templates"
  local AGENTS_DIR=".claude/agents"

  # ── 1. Check prerequisites ────────────────────────────────────────────────────

  config_exists || die ".leap/config not found. Run 'leap init' first."

  # ── 2. Interview ──────────────────────────────────────────────────────────────

  info "Configuring agent definitions for this project..."
  echo ""

  # Load previous answers as defaults
  local agents_config=".leap/agents-config"

  _agents_get() {
    local key="$1"
    if [[ -f "$agents_config" ]]; then
      grep -m1 "^${key}=" "$agents_config" 2>/dev/null | cut -d= -f2- || true
    fi
  }

  local existing_desc
  existing_desc="$(_agents_get PROJECT_DESCRIPTION_LONG)"

  local existing_components
  existing_components="$(_agents_get COMPONENTS)"

  local existing_has_frontend
  existing_has_frontend="$(_agents_get HAS_FRONTEND)"
  local frontend_default="n"
  [[ "$existing_has_frontend" == "true" ]] && frontend_default="y"

  local existing_frontend_fw
  existing_frontend_fw="$(_agents_get FRONTEND_FRAMEWORK)"
  [[ -z "$existing_frontend_fw" ]] && existing_frontend_fw="nextjs"

  local existing_has_backend
  existing_has_backend="$(_agents_get HAS_BACKEND)"
  local backend_default="y"
  [[ "$existing_has_backend" == "false" ]] && backend_default="n"

  local existing_has_infra
  existing_has_infra="$(_agents_get HAS_INFRA)"
  local infra_default="n"
  [[ "$existing_has_infra" == "true" ]] && infra_default="y"

  local existing_infra_provider
  existing_infra_provider="$(_agents_get INFRA_PROVIDER)"
  [[ -z "$existing_infra_provider" ]] && existing_infra_provider="hetzner"

  local existing_has_billing
  existing_has_billing="$(_agents_get HAS_BILLING)"
  local billing_default="n"
  [[ "$existing_has_billing" == "true" ]] && billing_default="y"

  local existing_billing_provider
  existing_billing_provider="$(_agents_get BILLING_PROVIDER)"
  [[ -z "$existing_billing_provider" ]] && existing_billing_provider="stripe"

  local existing_has_gtm
  existing_has_gtm="$(_agents_get HAS_GTM)"
  local gtm_default="n"
  [[ "$existing_has_gtm" == "true" ]] && gtm_default="y"

  local existing_custom
  existing_custom="$(_agents_get CUSTOM_AGENTS)"

  # Project description
  ask "What does this project do? (one line)" "$existing_desc"
  local PROJECT_DESCRIPTION_LONG="$REPLY"

  # Components
  ask_multi "What are the main components/services? (comma-separated)" "$existing_components"
  local COMPONENTS="$REPLY"

  echo ""

  # Frontend
  local HAS_FRONTEND FRONTEND_FRAMEWORK
  if ask_yn "Do you need a frontend agent?" "$frontend_default"; then
    HAS_FRONTEND="true"
    ask_choice "Frontend framework" "nextjs remix astro sveltekit other"
    FRONTEND_FRAMEWORK="$REPLY"
  else
    HAS_FRONTEND="false"
    FRONTEND_FRAMEWORK="$existing_frontend_fw"
  fi

  # Backend
  local HAS_BACKEND
  if ask_yn "Do you need a backend/API agent?" "$backend_default"; then
    HAS_BACKEND="true"
  else
    HAS_BACKEND="false"
  fi

  # Infra
  local HAS_INFRA INFRA_PROVIDER
  if ask_yn "Do you need an infrastructure agent?" "$infra_default"; then
    HAS_INFRA="true"
    ask_choice "Cloud provider" "aws gcp hetzner digitalocean fly other"
    INFRA_PROVIDER="$REPLY"
  else
    HAS_INFRA="false"
    INFRA_PROVIDER="$existing_infra_provider"
  fi

  # Billing
  local HAS_BILLING BILLING_PROVIDER
  if ask_yn "Do you need a billing/payments agent?" "$billing_default"; then
    HAS_BILLING="true"
    ask_choice "Payment provider" "stripe paddle polar other"
    BILLING_PROVIDER="$REPLY"
  else
    HAS_BILLING="false"
    BILLING_PROVIDER="$existing_billing_provider"
  fi

  # GTM
  local HAS_GTM
  if ask_yn "Do you need a GTM/analytics agent?" "$gtm_default"; then
    HAS_GTM="true"
  else
    HAS_GTM="false"
  fi

  echo ""

  # Custom agents — show previous value but don't auto-fill on empty input,
  # so pressing Enter with no input actually clears the list.
  if [[ -n "$existing_custom" ]]; then
    printf "Custom agents (comma-separated names, or empty) [previous: %s]: " "$existing_custom"
  else
    printf "Custom agents (comma-separated names, or empty): "
  fi
  read -r REPLY
  local CUSTOM_AGENTS="$REPLY"

  # For each custom agent, ask for a description
  declare -A custom_descriptions
  if [[ -n "$CUSTOM_AGENTS" ]]; then
    local IFS_save="$IFS"
    IFS=',' read -r -a custom_agent_names <<< "$CUSTOM_AGENTS"
    IFS="$IFS_save"
    for agent_name in "${custom_agent_names[@]}"; do
      agent_name="${agent_name#"${agent_name%%[![:space:]]*}"}"  # ltrim
      agent_name="${agent_name%"${agent_name##*[![:space:]]}"}"  # rtrim
      [[ -z "$agent_name" ]] && continue
      local desc_key="CUSTOM_${agent_name}_DESCRIPTION"
      local existing_agent_desc
      existing_agent_desc="$(_agents_get "$desc_key")"
      ask "Describe the role of '${agent_name}'" "$existing_agent_desc"
      custom_descriptions["$agent_name"]="$REPLY"
    done
  fi

  # ── 3. Save agent config ──────────────────────────────────────────────────────

  echo ""
  info "Writing agent config to ${agents_config}..."

  # Write KEY=VALUE pairs to agents-config
  : > "$agents_config"
  printf 'PROJECT_DESCRIPTION_LONG=%s\n' "$PROJECT_DESCRIPTION_LONG" >> "$agents_config"
  printf 'COMPONENTS=%s\n'               "$COMPONENTS"               >> "$agents_config"
  printf 'HAS_FRONTEND=%s\n'            "$HAS_FRONTEND"              >> "$agents_config"
  printf 'FRONTEND_FRAMEWORK=%s\n'      "$FRONTEND_FRAMEWORK"        >> "$agents_config"
  printf 'HAS_BACKEND=%s\n'             "$HAS_BACKEND"               >> "$agents_config"
  printf 'HAS_INFRA=%s\n'              "$HAS_INFRA"                  >> "$agents_config"
  printf 'INFRA_PROVIDER=%s\n'          "$INFRA_PROVIDER"            >> "$agents_config"
  printf 'HAS_BILLING=%s\n'             "$HAS_BILLING"               >> "$agents_config"
  printf 'BILLING_PROVIDER=%s\n'        "$BILLING_PROVIDER"          >> "$agents_config"
  printf 'HAS_GTM=%s\n'                "$HAS_GTM"                    >> "$agents_config"
  printf 'CUSTOM_AGENTS=%s\n'           "$CUSTOM_AGENTS"             >> "$agents_config"
  for agent_name in "${!custom_descriptions[@]}"; do
    printf 'CUSTOM_%s_DESCRIPTION=%s\n' "$agent_name" "${custom_descriptions[$agent_name]}" >> "$agents_config"
  done

  # ── 4. Build merged config ────────────────────────────────────────────────────

  # Create a temp file that merges .leap/config + .leap/agents-config
  # plus runtime vars (BOT_USERNAME alias, AGENT_NAME, AGENT_DESCRIPTION, etc.)
  _LEAP_AGENTS_MERGED_CONFIG="$(mktemp /tmp/leap-agents-merged.XXXXXX)"
  local merged_config="$_LEAP_AGENTS_MERGED_CONFIG"

  # Base: .leap/config
  cat ".leap/config" > "$merged_config"
  echo "" >> "$merged_config"
  # Agents-specific config
  cat "$agents_config" >> "$merged_config"

  # BOT_USERNAME alias — ci-gatekeeper template uses %%BOT_USERNAME%%
  local cto_bot
  cto_bot="$(config_get CTO_BOT_USERNAME)"
  printf 'BOT_USERNAME=%s\n' "$cto_bot" >> "$merged_config"

  # ── 5. Generate agent files ───────────────────────────────────────────────────

  info "Generating agent definitions..."
  mkdir -p "$AGENTS_DIR"

  # Clean previously generated agents so deselected ones don't linger.
  # Only remove files that match known leap-generated names or were listed
  # in the previous agents-config. Custom files the user added manually
  # (not matching any known pattern) are left alone.
  local _known_agents="ci-gatekeeper devex-engineer task-planner security-engineer frontend-engineer backend-engineer infra-engineer billing-engineer gtm-analyst"
  for _name in $_known_agents; do
    rm -f "${AGENTS_DIR}/${_name}.md"
  done
  # Also clean previously generated custom agents (use existing_custom
  # captured before the config was overwritten, not _agents_get which
  # would read the already-written new value).
  if [[ -n "$existing_custom" ]]; then
    local _prev_custom="$existing_custom"
    local _IFS_save="$IFS"
    IFS=',' read -r -a _prev_names <<< "$_prev_custom"
    IFS="$_IFS_save"
    for _pname in "${_prev_names[@]}"; do
      _pname="${_pname#"${_pname%%[![:space:]]*}"}"
      _pname="${_pname%"${_pname##*[![:space:]]}"}"
      [[ -z "$_pname" ]] && continue
      rm -f "${AGENTS_DIR}/$(slugify "$_pname").md"
    done
  fi

  local generated_agents=()

  # Core agents — always generated
  copy_template "$TMPL/agents/ci-gatekeeper.md.tmpl"   "$AGENTS_DIR/ci-gatekeeper.md"   "$merged_config"
  generated_agents+=("ci-gatekeeper")

  copy_template "$TMPL/agents/devex-engineer.md.tmpl"  "$AGENTS_DIR/devex-engineer.md"  "$merged_config"
  generated_agents+=("devex-engineer")

  copy_template "$TMPL/agents/task-planner.md.tmpl"    "$AGENTS_DIR/task-planner.md"    "$merged_config"
  generated_agents+=("task-planner")

  copy_template "$TMPL/agents/security-engineer.md.tmpl" "$AGENTS_DIR/security-engineer.md" "$merged_config"
  generated_agents+=("security-engineer")

  # Conditional agents
  if [[ "$HAS_FRONTEND" == "true" ]]; then
    copy_template "$TMPL/agents/frontend-engineer.md.tmpl" "$AGENTS_DIR/frontend-engineer.md" "$merged_config"
    generated_agents+=("frontend-engineer")
  fi

  if [[ "$HAS_BACKEND" == "true" ]]; then
    copy_template "$TMPL/agents/backend-engineer.md.tmpl" "$AGENTS_DIR/backend-engineer.md" "$merged_config"
    generated_agents+=("backend-engineer")
  fi

  if [[ "$HAS_INFRA" == "true" ]]; then
    copy_template "$TMPL/agents/infra-engineer.md.tmpl" "$AGENTS_DIR/infra-engineer.md" "$merged_config"
    generated_agents+=("infra-engineer")
  fi

  if [[ "$HAS_BILLING" == "true" ]]; then
    copy_template "$TMPL/agents/billing-engineer.md.tmpl" "$AGENTS_DIR/billing-engineer.md" "$merged_config"
    generated_agents+=("billing-engineer")
  fi

  if [[ "$HAS_GTM" == "true" ]]; then
    copy_template "$TMPL/agents/gtm-analyst.md.tmpl" "$AGENTS_DIR/gtm-analyst.md" "$merged_config"
    generated_agents+=("gtm-analyst")
  fi

  # Custom agents
  if [[ -n "$CUSTOM_AGENTS" ]]; then
    local IFS_save="$IFS"
    IFS=',' read -r -a custom_agent_names <<< "$CUSTOM_AGENTS"
    IFS="$IFS_save"
    for agent_name in "${custom_agent_names[@]}"; do
      agent_name="${agent_name#"${agent_name%%[![:space:]]*}"}"  # ltrim
      agent_name="${agent_name%"${agent_name##*[![:space:]]}"}"  # rtrim
      [[ -z "$agent_name" ]] && continue

      local desc="${custom_descriptions[$agent_name]:-}"
      local slug
      slug="$(slugify "$agent_name")"

      # Write agent-specific vars into merged config (overwrite if already there)
      # Use a fresh temp file with the agent vars appended
      local agent_config
      agent_config="$(mktemp /tmp/leap-agents-custom.XXXXXX)"
      cat "$merged_config" > "$agent_config"
      printf 'AGENT_NAME=%s\n'        "$slug"  >> "$agent_config"
      printf 'AGENT_DESCRIPTION=%s\n' "$desc"  >> "$agent_config"
      printf 'AGENT_EXPERTISE=%s\n'   "- Expertise specific to the ${agent_name} domain for this project." >> "$agent_config"

      copy_template "$TMPL/agents/custom-agent.md.tmpl" "$AGENTS_DIR/${slug}.md" "$agent_config"
      rm -f "$agent_config"
      generated_agents+=("$slug")
    done
  fi

  # ── 6. Generate opencode agents (if enabled) ──────────────────────────────────

  local has_opencode
  has_opencode="$(config_get HAS_OPENCODE)"

  if [[ "$has_opencode" == "true" ]]; then
    info "Mirroring agents to .opencode/agents/ (opencode tier)..."
    mkdir -p ".opencode/agents"
    # Clean stale opencode mirrors before regenerating
    rm -f .opencode/agents/*.md
    for agent_slug in "${generated_agents[@]}"; do
      local src="${AGENTS_DIR}/${agent_slug}.md"
      [[ -f "$src" ]] || continue
      sed '/^tools:/d' "$src" > ".opencode/agents/${agent_slug}.md"
    done
  else
    # Opencode disabled — clean up any previously generated mirrors
    if [[ -d ".opencode/agents" ]]; then
      rm -f .opencode/agents/*.md
      rmdir .opencode/agents 2>/dev/null || true
    fi
  fi

  # ── 7. Update CLAUDE.md routing table and escalation matrix ──────────────────

  if [[ -f "CLAUDE.md" ]]; then
    info "Updating CLAUDE.md routing table and escalation matrix..."
    _update_claude_md \
      "$HAS_FRONTEND" "$FRONTEND_FRAMEWORK" \
      "$HAS_BACKEND"  \
      "$HAS_INFRA"    "$INFRA_PROVIDER"    \
      "$HAS_BILLING"  "$BILLING_PROVIDER"  \
      "$HAS_GTM"      "$CUSTOM_AGENTS"
  else
    warn "CLAUDE.md not found — skipping routing table update."
  fi

  # ── 8. Print summary ──────────────────────────────────────────────────────────

  echo ""
  echo "✓ Generated ${#generated_agents[@]} agent definitions"
  echo ""
  echo "Agents:"
  echo "  ${AGENTS_DIR}/ci-gatekeeper.md     — CI enforcement, never writes product code"
  echo "  ${AGENTS_DIR}/devex-engineer.md    — CI pipeline, lint, coverage"
  echo "  ${AGENTS_DIR}/task-planner.md      — plan drafting"
  echo "  ${AGENTS_DIR}/security-engineer.md — threat modeling, has veto"
  if [[ "$HAS_FRONTEND" == "true" ]]; then
    echo "  ${AGENTS_DIR}/frontend-engineer.md — ${FRONTEND_FRAMEWORK} UI, components, routing"
  fi
  if [[ "$HAS_BACKEND" == "true" ]]; then
    echo "  ${AGENTS_DIR}/backend-engineer.md  — API routes, DB, background jobs"
  fi
  if [[ "$HAS_INFRA" == "true" ]]; then
    echo "  ${AGENTS_DIR}/infra-engineer.md    — ${INFRA_PROVIDER} cloud, Docker, deployment"
  fi
  if [[ "$HAS_BILLING" == "true" ]]; then
    echo "  ${AGENTS_DIR}/billing-engineer.md  — ${BILLING_PROVIDER} integration, subscriptions"
  fi
  if [[ "$HAS_GTM" == "true" ]]; then
    echo "  ${AGENTS_DIR}/gtm-analyst.md       — AARRR funnel, pricing, activation"
  fi
  if [[ -n "$CUSTOM_AGENTS" ]]; then
    local IFS_save="$IFS"
    IFS=',' read -r -a custom_agent_names <<< "$CUSTOM_AGENTS"
    IFS="$IFS_save"
    for agent_name in "${custom_agent_names[@]}"; do
      agent_name="${agent_name#"${agent_name%%[![:space:]]*}"}"
      agent_name="${agent_name%"${agent_name##*[![:space:]]}"}"
      [[ -z "$agent_name" ]] && continue
      local slug
      slug="$(slugify "$agent_name")"
      echo "  ${AGENTS_DIR}/${slug}.md — ${custom_descriptions[$agent_name]:-custom agent}"
    done
  fi
  echo ""
  if [[ "$has_opencode" == "true" ]]; then
    echo "Also mirrored to .opencode/agents/"
    echo ""
  fi
  echo "CLAUDE.md updated with routing table and escalation matrix."
  echo ""
}

# _update_claude_md — replaces content between marker comments in CLAUDE.md
_update_claude_md() {
  local has_frontend="$1"
  local frontend_fw="$2"
  local has_backend="$3"
  local has_infra="$4"
  local infra_provider="$5"
  local has_billing="$6"
  local billing_provider="$7"
  local has_gtm="$8"
  local custom_agents_csv="$9"

  # ── Build routing block ───────────────────────────────────────────────────────
  local routing
  routing="$(cat <<'ROUTING_EOF'
- CI pipeline / GitHub Actions / lefthook / lint configs → `ci-gatekeeper`
- CI config / dev environment / coverage baselines → `devex-engineer`
- Plan drafting / task breakdown → `task-planner`
- Threat modeling / secrets / dependency hygiene → `security-engineer`
ROUTING_EOF
)"

  if [[ "$has_frontend" == "true" ]]; then
    routing="${routing}"$'\n'"- ${frontend_fw} UI / components / routing / styling / accessibility → \`frontend-engineer\`"
  fi

  if [[ "$has_backend" == "true" ]]; then
    routing="${routing}"$'\n'"- API routes / database / authentication / background jobs → \`backend-engineer\`"
  fi

  if [[ "$has_infra" == "true" ]]; then
    routing="${routing}"$'\n'"- ${infra_provider} cloud / Docker / deployment / server provisioning / TLS → \`infra-engineer\`"
  fi

  if [[ "$has_billing" == "true" ]]; then
    routing="${routing}"$'\n'"- ${billing_provider} integration / subscriptions / invoices / webhooks → \`billing-engineer\`"
  fi

  if [[ "$has_gtm" == "true" ]]; then
    routing="${routing}"$'\n'"- JTBD / AARRR funnel / activation / pricing experiments / channel attribution → \`gtm-analyst\`"
  fi

  if [[ -n "$custom_agents_csv" ]]; then
    local IFS_save="$IFS"
    IFS=',' read -r -a custom_names <<< "$custom_agents_csv"
    IFS="$IFS_save"
    for agent_name in "${custom_names[@]}"; do
      agent_name="${agent_name#"${agent_name%%[![:space:]]*}"}"
      agent_name="${agent_name%"${agent_name##*[![:space:]]}"}"
      [[ -z "$agent_name" ]] && continue
      local slug
      slug="$(slugify "$agent_name")"
      routing="${routing}"$'\n'"- ${agent_name} domain work → \`${slug}\`"
    done
  fi

  # ── Build escalation matrix block ─────────────────────────────────────────────
  local escalation
  escalation="$(cat <<'ESC_EOF'
| Trigger | Primary owner | Must also review | Has veto |
|---|---|---|---|
| CI pipeline change | `devex-engineer` | `ci-gatekeeper` | `ci-gatekeeper` |
| Protected path change | `ci-gatekeeper` | `security-engineer` | `ci-gatekeeper` + human |
| New secret type or key-handling path | `security-engineer` | — | `security-engineer` |
| Waiver addition or renewal | author agent | `ci-gatekeeper` | `ci-gatekeeper` |
| Required `approved` check posted on PR | `ci-gatekeeper` (sole authority) | — | `ci-gatekeeper` |
| Retry circuit-breaker freeze | `ci-gatekeeper` | `devex-engineer` or human | `ci-gatekeeper` |
ESC_EOF
)"

  if [[ "$has_frontend" == "true" ]]; then
    escalation="${escalation}"$'\n'"| Onboarding or auth UI change | \`frontend-engineer\` | \`security-engineer\` | \`security-engineer\` |"
  fi

  if [[ "$has_infra" == "true" ]]; then
    escalation="${escalation}"$'\n'"| Abuse response posture change | \`infra-engineer\` | \`security-engineer\` | \`security-engineer\` |"
    escalation="${escalation}"$'\n'"| Deployment pipeline change | \`infra-engineer\` | \`devex-engineer\` | — |"
  fi

  if [[ "$has_billing" == "true" ]]; then
    escalation="${escalation}"$'\n'"| Pricing tier change | \`billing-engineer\` | — | — |"
    escalation="${escalation}"$'\n'"| Refund, chargeback, or ledger correction | \`billing-engineer\` | \`security-engineer\` | — |"
    escalation="${escalation}"$'\n'"| Customer payment data at rest | \`security-engineer\` | \`billing-engineer\` | \`security-engineer\` |"
  fi

  if [[ "$has_gtm" == "true" ]]; then
    escalation="${escalation}"$'\n'"| Activation event / funnel definition change | \`gtm-analyst\` | \`backend-engineer\` | — |"
    escalation="${escalation}"$'\n'"| Pricing experiment | \`gtm-analyst\` | \`billing-engineer\`, \`security-engineer\` | \`security-engineer\` |"
  fi

  # ── Inject into CLAUDE.md using sed range-delete + insert ─────────────────────
  # We replace the content between the BEGIN/END markers (inclusive of the markers).
  # Strategy: build a temp file via awk.

  local tmp_claude
  tmp_claude="$(mktemp /tmp/leap-claude.XXXXXX)"

  awk -v routing="$routing" -v escalation="$escalation" '
    BEGIN {
      in_routing    = 0
      in_escalation = 0
      skip          = 0
    }

    /<!-- BEGIN routing -->/ {
      print "<!-- BEGIN routing -->"
      print routing
      print "<!-- END routing -->"
      in_routing = 1
      skip = 1
      next
    }
    /<!-- END routing -->/ {
      in_routing = 0
      skip = 0
      next
    }

    /<!-- BEGIN escalation -->/ {
      print "<!-- BEGIN escalation -->"
      print escalation
      print "<!-- END escalation -->"
      in_escalation = 1
      skip = 1
      next
    }
    /<!-- END escalation -->/ {
      in_escalation = 0
      skip = 0
      next
    }

    skip == 0 { print }
  ' "CLAUDE.md" > "$tmp_claude"

  mv "$tmp_claude" "CLAUDE.md"
}

leap_agents
