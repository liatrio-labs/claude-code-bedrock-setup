# Claude Code + AWS Bedrock Setup

A simple setup script to configure [Claude Code](https://docs.anthropic.com/en/docs/build-with-claude/claude-code) to use AWS Bedrock as the model provider.

## Prerequisites

1. **AWS CLI** installed ([install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
2. **AWS Account** with Bedrock access enabled
3. **Model Access** - Enable Claude models in the [Bedrock console](https://console.aws.amazon.com/bedrock/home#/modelaccess)
4. **Claude Code** installed (`npm install -g @anthropic-ai/claude-code`)

## AWS Authentication

Before using Claude Code with Bedrock, authenticate with AWS:

```bash
# Login to AWS
aws login

# Verify your credentials
aws sts get-caller-identity
```

If you use a named profile:

```bash
# Login with specific profile
aws login --profile your-profile

# Set the profile for your session
export AWS_PROFILE=your-profile

# Verify
aws sts get-caller-identity
```

## Quick Start

```bash
# 1. Login to AWS
aws login

# 2. Clone or download the script
git clone <this-repo>
cd claude-code-bedrock-setup

# 3. Run setup with defaults
./setup-claude-code-bedrock.sh

# 4. Activate in current shell
source ~/.claude/claude-code-bedrock.env

# 5. Verify AWS credentials
aws sts get-caller-identity

# 6. Start Claude Code
claude

# 7. Verify
# After starting Claude Code, run /config, then left-arrow over to Status.
# You should see "API provider: AWS Bedrock"
```

## Installation Options

### Basic Setup (Interactive Activation)

```bash
./setup-claude-code-bedrock.sh
source ~/.claude/claude-code-bedrock.env
```

### Auto-load in New Terminals

```bash
./setup-claude-code-bedrock.sh --auto-source
```

This appends a source line to your shell rc file (`~/.zshrc` or `~/.bashrc`).

### Custom Region

```bash
./setup-claude-code-bedrock.sh --region us-west-2
```

### Custom Model (Inference Profile)

For production use or to avoid throughput limits, use an [Inference Profile ARN](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles.html):

```bash
./setup-claude-code-bedrock.sh \
  --model "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.anthropic.claude-opus-4-5-20251101-v1:0"
```

### Environment Variables

All options can be set via environment variables:

```bash
AWS_REGION=eu-west-1 \
BEDROCK_MODEL_ID="us.anthropic.claude-sonnet-4-5-20250929-v1:0" \
BEDROCK_SMALL_MODEL_ID="us.anthropic.claude-haiku-4-5-20251001-v1:0" \
CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192 \
./setup-claude-code-bedrock.sh
```

## Command Reference

```
Usage: ./setup-claude-code-bedrock.sh [OPTIONS]

Options:
  -h, --help              Show help message
  -r, --region REGION     AWS region (default: us-east-1)
  -m, --model MODEL       Primary model ID or Inference Profile ARN
  -s, --small-model MODEL Small/fast model ID
  --auto-source           Add source line to shell rc
  --dry-run               Show what would be done
  --uninstall             Remove configuration
```

## What Gets Created

| File | Purpose |
|------|---------|
| `~/.claude/settings.json` | Claude Code reads env vars from here |
| `~/.claude/claude-code-bedrock.env` | Shell snippet for manual sourcing |

## Uninstall

```bash
./setup-claude-code-bedrock.sh --uninstall
```

This removes the configuration files and any source lines added to your shell rc.

## Troubleshooting

### "Could not authenticate with AWS"

Verify your credentials:

```bash
aws sts get-caller-identity
```

To re-authenticate:

```bash
aws login --profile your-profile
export AWS_PROFILE=your-profile
```

### "Access denied" for Bedrock

1. Check model access is enabled in [Bedrock console](https://console.aws.amazon.com/bedrock/home#/modelaccess)
2. Verify IAM permissions include `bedrock:InvokeModel`

### Throughput Errors

Switch from a foundation model ID to an Inference Profile ARN:

```bash
./setup-claude-code-bedrock.sh \
  --model "arn:aws:bedrock:REGION:ACCOUNT:inference-profile/MODEL"
```

### Check Current Configuration

```bash
cat ~/.claude/settings.json
echo $ANTHROPIC_MODEL
```

## Available Models

### Model IDs

| Model | Model ID |
|-------|----------|
| **Claude Opus 4.5** (default) | `us.anthropic.claude-opus-4-5-20251101-v1:0` |
| **Claude Sonnet 4.5** | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` |
| **Claude Haiku 4.5** (fast) | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |

### Inference Profile IDs (US region)

These models require inference profiles (not foundation model IDs):

```
us.anthropic.claude-opus-4-5-20251101-v1:0
us.anthropic.claude-sonnet-4-5-20250929-v1:0
us.anthropic.claude-haiku-4-5-20251001-v1:0
```
