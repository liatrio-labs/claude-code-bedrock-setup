# Claude Code + AWS Bedrock Setup

A simple setup script to configure [Claude Code](https://code.claude.com/docs/en/overview) to use AWS Bedrock as the model provider.

## Prerequisites

1. **AWS SSO** Configured per [Workstation Setup Guide](https://github.com/liatrio/flywheel-infrastructure/edit/main/docs/onboarding/workstation.md)
2. Access to liatrio-llm ( Use step one of the [Workstation Setup Guide](https://github.com/liatrio/flywheel-infrastructure/edit/main/docs/onboarding/workstation.md) to see if you have access). If you do not have access, ask for it in `#liatrio-tools-support`
5. **Claude Code** installed (`npm install -g @anthropic-ai/claude-code`)

> **Note:** This guide assumes you are using the new AWS CLI config file format with an `sso-session` block and one or more `profile` blocks. This is the recommended format since aws cli v2.9.0 (released in 2022) and documented in [Configuring IAM Identity Center authentication with the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html).

## AWS CLI Profile setup

Add the following to ~/.aws/config

```bash
[profile liatro-llm]
sso_session = <your sso session name> (look for [sso-session xxxxxxx])
sso_account_id = 381492021279
sso_role_name = AWSPowerUserAccess
region = us-east-1
```

If you do not have an sso-session block, add this one 

```bash
[sso-session liatro-sso]
sso_start_url = https://d-906787324a.awsapps.com/start/#/?tab=accounts
sso_region = us-east-1
sso_registration_scopes = sso:account:access
```

## AWS Authentication

This script configures **automatic credential refresh**. When your AWS session expires, Claude Code will automatically re-authenticate to preserve your conversation context.

```bash
export AWS_REGION=us-east-1
export AWS_PROFILE-liatrio-llm
aws login

# Verify your credentials
aws sts get-caller-identity
```

> **Note:** If you haven't configured AWS SSO yet, see the [AWS SSO configuration guide](https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html). Using a named profile is helpful when working with multiple AWS accounts.

## Quick Start

```bash
# 1. Clone or download the script
git clone <this-repo>
cd claude-code-bedrock-setup

# 2. Login to AWS
aws login

# 3. Run setup
./setup-claude-code-bedrock.sh --auto-source

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

Or with a named profile:

```bash
# 1. Clone or download the script
git clone <this-repo>
cd claude-code-bedrock-setup

# 2. Login to AWS with your profile
aws sso login --profile your-profile-name

# 3. Run setup with your profile
./setup-claude-code-bedrock.sh --profile your-profile-name --auto-source

# 4. Activate in current shell (or restart your terminal)
source ~/.claude/claude-code-bedrock.env

# 5. Start Claude Code
claude
```

## Installation Options

### Basic Setup (Interactive Activation)

```bash
./setup-claude-code-bedrock.sh
source ~/.claude/claude-code-bedrock.env
```

This configures automatic credential refresh using the `aws login` command.

### Auto-load in New Terminals

```bash
./setup-claude-code-bedrock.sh --auto-source
```

This configures automatic credential refresh using the `aws login` command and appends a source line to your shell rc file (`~/.zshrc` or `~/.bashrc`).

### With Named Profile

```bash
./setup-claude-code-bedrock.sh --profile your-profile-name --auto-source
source ~/.claude/claude-code-bedrock.env
```

This configures automatic credential refresh using the `aws sso login --profile your-profile-name` command and appends a source line to your shell rc file (`~/.zshrc` or `~/.bashrc`). This also sets `AWS_PROFILE` in your environment so credentials refresh using your specific profile.

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
  -p, --profile PROFILE   AWS profile name
  -m, --model MODEL       Primary model ID or Inference Profile ARN
  -s, --small-model MODEL Small/fast model ID
  --auto-source           Add source line to shell rc
  --dry-run               Show what would be done
  --uninstall             Remove configuration
```

## What Gets Created

| File                                | Purpose                                                                            |
|-------------------------------------|------------------------------------------------------------------------------------|
| `~/.claude/settings.json`           | Claude Code configuration (env vars + `awsAuthRefresh` for auto credential refresh) |
| `~/.claude/claude-code-bedrock.env` | Shell snippet for manual sourcing                                                  |

### Example settings.json

```json
{
  "awsAuthRefresh": "aws sso login --profile your-profile",
  "env": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "us-east-1",
    "AWS_PROFILE": "your-profile",
    "ANTHROPIC_MODEL": "us.anthropic.claude-opus-4-5-20251101-v1:0",
    "ANTHROPIC_SMALL_FAST_MODEL": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "64000",
    "MAX_THINKING_TOKENS": "8192"
  }
}
```

The `awsAuthRefresh` setting tells Claude Code to automatically run the specified command when AWS credentials expire, keeping your session alive. If no profile is configured, it uses `aws login` instead.

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
```

### "Could not authenticate with AWS"

Verify your credentials:

```bash
aws sts get-caller-identity
```

To re-authenticate:

```bash
aws sso login --profile your-profile
```

### "Access denied" for Bedrock

1. Check model access is enabled in [Bedrock console](https://console.aws.amazon.com/bedrock/home#/modelaccess)
2. Verify IAM permissions include `bedrock:InvokeModel`

### "API Error: Could not load credentials from any provider"
1. Ensure you are using the new config file format and have `region = us-east-1` in the profile

```bash
[profile liatro-llm]
sso_session = liatro-sso
sso_account_id = 381492021279
sso_role_name = AWSPowerUserAccess
region = us-east-1
[sso-session liatrio-sso]
sso_start_url = https://d-906787324a.awsapps.com/start/#/?tab=accounts
sso_region = us-east-1
sso_registration_scopes = sso:account:access

```

2. Login to aws sso again

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
- [AWS SSO Configuration Guide](https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html) - Set up AWS SSO profiles
- [Bedrock Inference Profiles](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html) - AWS documentation
- [Bedrock Model Access](https://console.aws.amazon.com/bedrock/home#/modelaccess) - Enable models in your account
