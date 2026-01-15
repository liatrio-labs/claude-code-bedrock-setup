#!/usr/bin/env bash
#
# Claude Code + AWS Bedrock Global Bootstrap Script
# ==================================================
#
# This script configures Claude Code to use AWS Bedrock as the model provider.
#
# What it does:
#   - Creates ~/.claude/settings.json with Bedrock configuration
#   - Creates ~/.claude/claude-code-bedrock.env shell snippet
#   - Optionally sources the env file in your shell rc (~/.zshrc or ~/.bashrc)
#
# Prerequisites:
#   - AWS CLI installed (recommended, not required)
#   - Valid AWS credentials configured (SSO, IAM, or environment variables)
#   - Bedrock model access enabled in your AWS account
#
# Usage:
#   ./setup-claude-code-bedrock.sh [OPTIONS]
#
# Options:
#   -h, --help              Show this help message
#   -r, --region REGION     AWS region (default: us-east-1)
#   -m, --model MODEL       Primary model ID or Inference Profile ARN
#   -s, --small-model MODEL Small/fast model ID
#   --auto-source           Automatically add source line to shell rc
#   --dry-run               Show what would be done without making changes
#   --uninstall             Remove Claude Code Bedrock configuration
#
# Environment Variables (alternative to options):
#   AWS_REGION                    - AWS region
#   BEDROCK_MODEL_ID              - Primary model ID or Inference Profile ARN
#   BEDROCK_SMALL_MODEL_ID        - Small/fast model ID
#   CLAUDE_CODE_MAX_OUTPUT_TOKENS - Max output tokens (default: 16000)
#   MAX_THINKING_TOKENS           - Max thinking tokens (default: 10000)
#   AUTO_SOURCE_RC                - Set to 1 to auto-source in shell rc
#
# Examples:
#   # Basic setup with defaults
#   ./setup-claude-code-bedrock.sh
#
#   # Custom region and auto-source
#   ./setup-claude-code-bedrock.sh --region us-west-2 --auto-source
#
#   # Using Inference Profile ARN (recommended for production)
#   ./setup-claude-code-bedrock.sh \
#     --model "arn:aws:bedrock:us-east-1:123456789:inference-profile/us.anthropic.claude-opus-4-5-20251101-v1:0"
#
#   # Using environment variables
#   AWS_REGION=eu-west-1 BEDROCK_MODEL_ID="us.anthropic.claude-sonnet-4-5-20250929-v1:0" \
#     ./setup-claude-code-bedrock.sh
#
# Notes:
#   - Claude Code uses the AWS SDK credential chain. Verify with:
#       aws sts get-caller-identity
#   - If you hit throughput errors, use an Inference Profile ARN instead of
#     a foundation model ID
#   - Run with --uninstall to cleanly remove configuration
#
# For more info: https://docs.anthropic.com/en/docs/build-with-claude/claude-code
#
set -euo pipefail

########################
# Script metadata
########################
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"

########################
# Color output (if terminal supports it)
########################
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1 2>/dev/null || echo "")
    GREEN=$(tput setaf 2 2>/dev/null || echo "")
    YELLOW=$(tput setaf 3 2>/dev/null || echo "")
    BLUE=$(tput setaf 4 2>/dev/null || echo "")
    BOLD=$(tput bold 2>/dev/null || echo "")
    RESET=$(tput sgr0 2>/dev/null || echo "")
else
    RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
fi

########################
# Defaults
########################
DEFAULT_AWS_REGION="${AWS_REGION:-us-east-1}"
DEFAULT_BEDROCK_MODEL_ID="${BEDROCK_MODEL_ID:-us.anthropic.claude-opus-4-5-20251101-v1:0}"
DEFAULT_BEDROCK_SMALL_MODEL_ID="${BEDROCK_SMALL_MODEL_ID:-us.anthropic.claude-haiku-4-5-20251001-v1:0}"
DEFAULT_MAX_OUTPUT_TOKENS="${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-16000}"
DEFAULT_MAX_THINKING_TOKENS="${MAX_THINKING_TOKENS:-10000}"
AUTO_SOURCE_RC="${AUTO_SOURCE_RC:-0}"
DRY_RUN=0
UNINSTALL=0

########################
# Paths
########################
CLAUDE_HOME="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_HOME}/settings.json"
SHELL_SNIPPET="${CLAUDE_HOME}/claude-code-bedrock.env"
BACKUP_SUFFIX=".backup.$(date +%Y%m%d-%H%M%S)"

########################
# Helper functions
########################
err() {
    echo "${RED}${BOLD}ERROR:${RESET} $*" >&2
}

warn() {
    echo "${YELLOW}${BOLD}WARNING:${RESET} $*" >&2
}

info() {
    echo "${GREEN}==>${RESET} $*"
}

debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "${BLUE}DEBUG:${RESET} $*" >&2
    fi
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        err "Missing required command: $1"
        exit 1
    }
}

show_help() {
    # Extract and display the header comment block
    sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \?//'
    echo ""
    echo "Version: ${SCRIPT_VERSION}"
}

########################
# Configuration writers
########################
write_json_settings() {
    local file="$1"
    
    if [[ "$DRY_RUN" == "1" ]]; then
        info "[DRY RUN] Would write settings to: $file"
        cat <<EOF
{
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "${DEFAULT_AWS_REGION}",
    "ANTHROPIC_MODEL": "${DEFAULT_BEDROCK_MODEL_ID}",
    "ANTHROPIC_SMALL_FAST_MODEL": "${DEFAULT_BEDROCK_SMALL_MODEL_ID}",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "${DEFAULT_MAX_OUTPUT_TOKENS}",
    "MAX_THINKING_TOKENS": "${DEFAULT_MAX_THINKING_TOKENS}"
  }
}
EOF
        return
    fi

    mkdir -p "$(dirname "$file")"

    # Backup existing file if present
    if [[ -f "$file" ]]; then
        cp "$file" "${file}${BACKUP_SUFFIX}"
        info "Backed up existing settings to: ${file}${BACKUP_SUFFIX}"
    fi

    cat > "$file" <<EOF
{
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "${DEFAULT_AWS_REGION}",
    "ANTHROPIC_MODEL": "${DEFAULT_BEDROCK_MODEL_ID}",
    "ANTHROPIC_SMALL_FAST_MODEL": "${DEFAULT_BEDROCK_SMALL_MODEL_ID}",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "${DEFAULT_MAX_OUTPUT_TOKENS}",
    "MAX_THINKING_TOKENS": "${DEFAULT_MAX_THINKING_TOKENS}"
  }
}
EOF
}

write_shell_snippet() {
    local file="$1"
    
    if [[ "$DRY_RUN" == "1" ]]; then
        info "[DRY RUN] Would write shell snippet to: $file"
        return
    fi

    mkdir -p "$(dirname "$file")"

    cat > "$file" <<EOF
# Claude Code + Bedrock environment (global)
# Generated by ${SCRIPT_NAME} v${SCRIPT_VERSION} on $(date)
export CLAUDE_CODE_USE_BEDROCK=1
export AWS_REGION="${DEFAULT_AWS_REGION}"
export ANTHROPIC_MODEL="${DEFAULT_BEDROCK_MODEL_ID}"
export ANTHROPIC_SMALL_FAST_MODEL="${DEFAULT_BEDROCK_SMALL_MODEL_ID}"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS="${DEFAULT_MAX_OUTPUT_TOKENS}"
export MAX_THINKING_TOKENS="${DEFAULT_MAX_THINKING_TOKENS}"
EOF
}

########################
# Shell RC handling
########################
detect_shell_rc() {
    local shell_path="${SHELL:-}"
    
    if [[ "$shell_path" == *"zsh" ]]; then
        echo "$HOME/.zshrc"
        return
    fi
    if [[ "$shell_path" == *"bash" ]]; then
        # On macOS, .bash_profile is preferred for login shells
        if [[ "$(uname)" == "Darwin" ]] && [[ -f "$HOME/.bash_profile" ]]; then
            echo "$HOME/.bash_profile"
        else
            echo "$HOME/.bashrc"
        fi
        return
    fi
    if [[ "$shell_path" == *"fish" ]]; then
        echo "$HOME/.config/fish/config.fish"
        return
    fi

    # Fallbacks
    [[ -f "$HOME/.zshrc" ]] && { echo "$HOME/.zshrc"; return; }
    [[ -f "$HOME/.bashrc" ]] && { echo "$HOME/.bashrc"; return; }
    [[ -f "$HOME/.bash_profile" ]] && { echo "$HOME/.bash_profile"; return; }

    echo "$HOME/.bashrc"
}

append_source_line_if_needed() {
    local rc_file="$1"
    local snippet="$2"
    local source_line="source \"${snippet}\""

    if [[ "$DRY_RUN" == "1" ]]; then
        info "[DRY RUN] Would append source line to: $rc_file"
        return
    fi

    mkdir -p "$(dirname "$rc_file")"
    touch "$rc_file"

    # Check for various forms of the source line
    if grep -Fq "$snippet" "$rc_file"; then
        info "Shell rc already sources env snippet: $rc_file"
        return
    fi

    {
        echo ""
        echo "# Claude Code + Bedrock (added by ${SCRIPT_NAME} on $(date +%Y-%m-%d))"
        echo "$source_line"
    } >> "$rc_file"

    info "Appended source line to: $rc_file"
}

remove_source_line() {
    local rc_file="$1"
    local snippet="$2"

    if [[ ! -f "$rc_file" ]]; then
        return
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        info "[DRY RUN] Would remove source line from: $rc_file"
        return
    fi

    # Create a backup before modifying
    cp "$rc_file" "${rc_file}${BACKUP_SUFFIX}"

    # Remove the source line and the comment above it
    grep -v "source.*claude-code-bedrock.env" "$rc_file" | \
        grep -v "# Claude Code + Bedrock" > "${rc_file}.tmp" || true
    mv "${rc_file}.tmp" "$rc_file"

    info "Removed source line from: $rc_file"
}

########################
# Uninstall
########################
do_uninstall() {
    info "Uninstalling Claude Code Bedrock configuration..."

    local rc_file
    rc_file="$(detect_shell_rc)"

    if [[ -f "$SHELL_SNIPPET" ]]; then
        if [[ "$DRY_RUN" == "1" ]]; then
            info "[DRY RUN] Would remove: $SHELL_SNIPPET"
        else
            rm -f "$SHELL_SNIPPET"
            info "Removed: $SHELL_SNIPPET"
        fi
    fi

    if [[ -f "$SETTINGS_FILE" ]]; then
        if [[ "$DRY_RUN" == "1" ]]; then
            info "[DRY RUN] Would remove: $SETTINGS_FILE"
        else
            rm -f "$SETTINGS_FILE"
            info "Removed: $SETTINGS_FILE"
        fi
    fi

    remove_source_line "$rc_file" "$SHELL_SNIPPET"

    echo ""
    info "Uninstall complete."
    info "You may need to restart your shell or run: unset CLAUDE_CODE_USE_BEDROCK"
}

########################
# AWS verification
########################
check_aws_auth() {
    if ! command -v aws >/dev/null 2>&1; then
        info "AWS CLI not found (optional). Install for easier auth verification."
        return
    fi

    info "Checking AWS credentials..."
    
    set +e
    local identity
    identity=$(aws sts get-caller-identity 2>&1)
    local aws_ok=$?
    set -e

    if [[ $aws_ok -ne 0 ]]; then
        warn "AWS auth check failed. This is OK if you haven't logged in yet."
        echo ""
        echo "  To authenticate, try one of:"
        echo "    ${BOLD}aws sso login --profile <your-profile>${RESET}"
        echo "    ${BOLD}export AWS_PROFILE=<your-profile>${RESET}"
        echo "    ${BOLD}aws configure${RESET}"
        echo ""
    else
        info "AWS auth successful!"
        echo "$identity" | grep -E "(Account|Arn)" | sed 's/^/    /'
    fi
}

check_bedrock_access() {
    if ! command -v aws >/dev/null 2>&1; then
        return
    fi

    info "Checking Bedrock model access..."
    
    set +e
    local models
    models=$(aws bedrock list-foundation-models \
        --region "${DEFAULT_AWS_REGION}" \
        --by-provider anthropic \
        --query "modelSummaries[?contains(modelId, 'claude')].modelId" \
        --output text 2>&1)
    local bedrock_ok=$?
    set -e

    if [[ $bedrock_ok -ne 0 ]]; then
        warn "Could not list Bedrock models. Check your permissions."
        echo "    Error: $models"
    else
        local model_count
        model_count=$(echo "$models" | wc -w | tr -d ' ')
        info "Found ${model_count} Claude models available in Bedrock"
    fi
}

########################
# Argument parsing
########################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -r|--region)
                DEFAULT_AWS_REGION="$2"
                shift 2
                ;;
            -m|--model)
                DEFAULT_BEDROCK_MODEL_ID="$2"
                shift 2
                ;;
            -s|--small-model)
                DEFAULT_BEDROCK_SMALL_MODEL_ID="$2"
                shift 2
                ;;
            --auto-source)
                AUTO_SOURCE_RC=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --uninstall)
                UNINSTALL=1
                shift
                ;;
            *)
                err "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

########################
# Main
########################
main() {
    parse_args "$@"

    echo ""
    echo "${BOLD}Claude Code + AWS Bedrock Setup${RESET} v${SCRIPT_VERSION}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ "$DRY_RUN" == "1" ]]; then
        warn "Running in DRY RUN mode - no changes will be made"
        echo ""
    fi

    if [[ "$UNINSTALL" == "1" ]]; then
        do_uninstall
        exit 0
    fi

    # Preflight checks
    info "Preflight checks"
    need_cmd mkdir
    need_cmd cat
    need_cmd grep
    need_cmd touch

    # Display configuration
    echo ""
    echo "Configuration:"
    echo "  ${BOLD}AWS Region:${RESET}    ${DEFAULT_AWS_REGION}"
    echo "  ${BOLD}Primary Model:${RESET} ${DEFAULT_BEDROCK_MODEL_ID}"
    echo "  ${BOLD}Small Model:${RESET}   ${DEFAULT_BEDROCK_SMALL_MODEL_ID}"
    echo "  ${BOLD}Max Tokens:${RESET}    ${DEFAULT_MAX_OUTPUT_TOKENS}"
    echo "  ${BOLD}Think Tokens:${RESET}  ${DEFAULT_MAX_THINKING_TOKENS}"
    echo ""

    # Write configuration files
    info "Writing settings: ${SETTINGS_FILE}"
    write_json_settings "$SETTINGS_FILE"

    info "Writing shell snippet: ${SHELL_SNIPPET}"
    write_shell_snippet "$SHELL_SNIPPET"

    # Handle shell rc
    if [[ "$AUTO_SOURCE_RC" == "1" ]]; then
        local rc_file
        rc_file="$(detect_shell_rc)"
        append_source_line_if_needed "$rc_file" "$SHELL_SNIPPET"
    else
        info "Skipping shell rc modification (use --auto-source to enable)"
    fi

    echo ""

    # AWS checks
    check_aws_auth

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "${GREEN}${BOLD}✓ Setup complete!${RESET}"
    echo ""
    echo "Files created:"
    echo "  • ${SETTINGS_FILE}"
    echo "  • ${SHELL_SNIPPET}"
    echo ""
    echo "${BOLD}Next steps:${RESET}"
    echo ""
    echo "  1. Activate in your current shell:"
    echo "     ${BOLD}source \"${SHELL_SNIPPET}\"${RESET}"
    echo ""
    echo "  2. Or reload your shell:"
    echo "     ${BOLD}exec \$SHELL${RESET}"
    echo ""
    echo "  3. Start Claude Code:"
    echo "     ${BOLD}claude${RESET}"
    echo ""
    
    if [[ "$AUTO_SOURCE_RC" != "1" ]]; then
        echo "${YELLOW}TIP:${RESET} To auto-load in new terminals, run:"
        echo "     ${BOLD}$0 --auto-source${RESET}"
        echo ""
    fi

    echo "If you encounter Bedrock throughput errors, use an Inference Profile ARN:"
    echo "  ${BOLD}$0 --model \"arn:aws:bedrock:REGION:ACCOUNT:inference-profile/...\"${RESET}"
    echo ""
}

main "$@"
