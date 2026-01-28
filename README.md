# Claude Code + AWS Bedrock Setup

A simple setup script to configure [Claude Code](https://code.claude.com/docs/en/overview) to use AWS Bedrock as the model provider.

## Prerequisites

1. **AWS CLI** installed ([install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
2. **AWS Account** with Bedrock access enabled
3. **Model Access** - Enable Claude models in the [Bedrock console](https://console.aws.amazon.com/bedrock/home#/modelaccess)
4. **Claude Code** installed (`npm install -g @anthropic-ai/claude-code`)

## AWS Authentication

This script configures **automatic credential refresh** for both authentication methods. When your AWS session expires, Claude Code will automatically re-authenticate to preserve your conversation context.

### Option 1: Named Profile (Recommended)

```bash
# Login with your named profile
aws sso login --profile your-profile-name

# Verify your credentials
aws sts get-caller-identity --profile your-profile-name
```

### Option 2: Default Credentials

```bash
# Login to AWS
aws login

# Verify your credentials
aws sts get-caller-identity
```

## Quick Start

```bash
# 1. Clone or download the script
git clone <this-repo>
cd claude-code-bedrock-setup

# 2. Login to AWS with your named profile
aws sso login --profile your-profile-name

# 3. Run setup with your profile (enables auto credential refresh)
./setup-claude-code-bedrock.sh --profile your-profile-name --auto-source

# 4. Activate in current shell (or restart your terminal)
source ~/.claude/claude-code-bedrock.env

# 5. Verify AWS credentials
aws sts get-caller-identity

# 6. Start Claude Code
claude

# 7. Verify
# After starting Claude Code, run /config, then left-arrow over to Status.
# You should see "API provider: AWS Bedrock"
```

### Why Use a Named Profile?

Both methods support automatic credential refresh, but **named profiles are recommended** because:

- **Explicit account control** - You know exactly which AWS account and role you're using
- **Multiple accounts** - Essential if you work with multiple AWS accounts
- **Team consistency** - Easier to document and share setup instructions
- **Predictable behavior** - `aws sso login --profile <name>` is more deterministic than `aws login`

Without a profile, the script uses `aws login` for auto-refresh, which works but may be less predictable if you have multiple AWS configurations.

## Installation Options

### Recommended: Named Profile with Auto-Source

```bash
./setup-claude-code-bedrock.sh --profile your-profile-name --auto-source
source ~/.claude/claude-code-bedrock.env
```

This:
- Configures automatic credential refresh via `awsAuthRefresh` using `aws sso login --profile <name>`
- Sets `AWS_PROFILE` in your environment
- Appends a source line to your shell rc file (`~/.zshrc` or `~/.bashrc`)

### Basic Setup (Default Credentials)

```bash
./setup-claude-code-bedrock.sh --auto-source
source ~/.claude/claude-code-bedrock.env
```

This:
- Configures automatic credential refresh via `awsAuthRefresh` using `aws login`
- Uses your default AWS credentials
- Appends a source line to your shell rc file

### Custom Region

```bash
./setup-claude-code-bedrock.sh --profile your-profile --region us-west-2
```

### Custom Model (Inference Profile)

For production use or to avoid throughput limits, use an [Inference Profile ARN](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles.html):

```bash
./setup-claude-code-bedrock.sh --profile your-profile \
  --model "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.anthropic.claude-opus-4-5-20251101-v1:0"
```

### Environment Variables

All options can be set via environment variables:

```bash
AWS_REGION=eu-west-1 \
AWS_PROFILE=your-profile \
BEDROCK_MODEL_ID="us.anthropic.claude-sonnet-4-5-20250929-v1:0" \
BEDROCK_SMALL_MODEL_ID="us.anthropic.claude-haiku-4-5-20251001-v1:0" \
./setup-claude-code-bedrock.sh
```

## Command Reference

```
Usage: ./setup-claude-code-bedrock.sh [OPTIONS]

Options:
  -h, --help              Show help message
  -r, --region REGION     AWS region (default: us-east-1)
  -p, --profile PROFILE   AWS profile name (highly recommended for SSO users)
  -m, --model MODEL       Primary model ID or Inference Profile ARN
  -s, --small-model MODEL Small/fast model ID
  --auto-source           Add source line to shell rc
  --dry-run               Show what would be done
  --uninstall             Remove configuration
```

## What Gets Created

| File | Purpose |
|------|---------|
| `~/.claude/settings.json` | Claude Code configuration (env vars + `awsAuthRefresh` for auto credential refresh) |
| `~/.claude/claude-code-bedrock.env` | Shell snippet for manual sourcing |

### Example settings.json

**With named profile (recommended):**

```json
{
  "awsAuthRefresh": "aws sso login --profile your-profile",
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "us-east-1",
    "AWS_PROFILE": "your-profile",
    "ANTHROPIC_MODEL": "us.anthropic.claude-opus-4-5-20251101-v1:0",
    "ANTHROPIC_SMALL_FAST_MODEL": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "4096",
    "MAX_THINKING_TOKENS": "1024"
  }
}
```

**Without profile (default credentials):**

```json
{
  "awsAuthRefresh": "aws login",
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "us-east-1",
    "ANTHROPIC_MODEL": "us.anthropic.claude-opus-4-5-20251101-v1:0",
    "ANTHROPIC_SMALL_FAST_MODEL": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "4096",
    "MAX_THINKING_TOKENS": "1024"
  }
}
```

The `awsAuthRefresh` setting tells Claude Code to automatically run the specified command when AWS credentials expire, keeping your session alive.

## Uninstall

```bash
./setup-claude-code-bedrock.sh --uninstall
```

This removes the configuration files and any source lines added to your shell rc.

## Troubleshooting

### Credentials Expire Mid-Session (Context Lost)

If you're losing context when credentials expire, check that `awsAuthRefresh` is configured in your settings:

```bash
cat ~/.claude/settings.json | grep awsAuthRefresh
```

If it's missing, re-run the setup script:

```bash
./setup-claude-code-bedrock.sh --auto-source
# Or with a named profile (recommended):
./setup-claude-code-bedrock.sh --profile your-profile-name --auto-source
```

### "Could not authenticate with AWS"

Verify your credentials:

```bash
# With named profile
aws sts get-caller-identity --profile your-profile

# With default credentials
aws sts get-caller-identity
```

To re-authenticate:

```bash
# With named profile
aws sso login --profile your-profile

# With default credentials
aws login
```

### "Access denied" for Bedrock

1. Check model access is enabled in [Bedrock console](https://console.aws.amazon.com/bedrock/home#/modelaccess)
2. Verify IAM permissions include `bedrock:InvokeModel`

### Throughput Errors

Switch from a foundation model ID to an Inference Profile ARN:

```bash
./setup-claude-code-bedrock.sh --profile your-profile \
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

## Resources

- [Claude Code on Amazon Bedrock](https://code.claude.com/docs/en/amazon-bedrock) - Official documentation
- [Bedrock Inference Profiles](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html) - AWS documentation
- [Bedrock Model Access](https://console.aws.amazon.com/bedrock/home#/modelaccess) - Enable models in your account
