<#
.SYNOPSIS
    Claude Code + AWS Bedrock Global Bootstrap Script

.DESCRIPTION
    This script configures Claude Code to use AWS Bedrock as the model provider.
    
    What it does:
      - Creates ~/.claude/settings.json with Bedrock configuration
      - Creates ~/.claude/claude-code-bedrock.env shell snippet
      - Optionally sources the env file in your PowerShell profile
    
    Prerequisites:
      - AWS CLI installed (recommended, not required)
      - Valid AWS credentials configured (SSO, IAM, or environment variables)
      - Bedrock model access enabled in your AWS account

.PARAMETER Region
    AWS region (default: us-east-1)

.PARAMETER Profile
    AWS profile name

.PARAMETER Model
    Primary model ID or Inference Profile ARN

.PARAMETER SmallModel
    Small/fast model ID

.PARAMETER AutoSource
    Automatically add source line to PowerShell profile

.PARAMETER DryRun
    Show what would be done without making changes

.PARAMETER Uninstall
    Remove Claude Code Bedrock configuration

.PARAMETER Help
    Show this help message

.EXAMPLE
    .\setup-claude-code-bedrock.ps1 -AutoSource
    Basic setup with auto-sourcing

.EXAMPLE
    .\setup-claude-code-bedrock.ps1 -Profile my-aws-profile -AutoSource
    Setup with a named AWS profile

.EXAMPLE
    .\setup-claude-code-bedrock.ps1 -Region us-west-2 -AutoSource
    Custom region

.EXAMPLE
    .\setup-claude-code-bedrock.ps1 -Profile my-profile -Model "arn:aws:bedrock:us-east-1:123456789:inference-profile/us.anthropic.claude-opus-4-5-20251101-v1:0"
    Using Inference Profile ARN (recommended for production)

.EXAMPLE
    $env:AWS_REGION = "eu-west-1"; $env:AWS_PROFILE = "my-profile"; .\setup-claude-code-bedrock.ps1
    Using environment variables

.NOTES
    Version: 1.1.0
    
    - Auto credential refresh is always enabled. When AWS credentials expire,
      Claude Code will automatically re-authenticate to preserve your session.
    - Use a named AWS profile (-Profile) if you work with multiple AWS accounts.
    - Claude Code uses the AWS SDK credential chain. Verify with:
        aws sts get-caller-identity
    - If you hit throughput errors, use an Inference Profile ARN instead of
      a foundation model ID
    - Run with -Uninstall to cleanly remove configuration
    
    For more info: https://code.claude.com/docs/en/amazon-bedrock
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "AWS region")]
    [string]$Region = $env:AWS_REGION,
    
    [Parameter(HelpMessage = "AWS profile name")]
    [string]$Profile = $env:AWS_PROFILE,
    
    [Parameter(HelpMessage = "Primary model ID or Inference Profile ARN")]
    [string]$Model = $env:BEDROCK_MODEL_ID,
    
    [Parameter(HelpMessage = "Small/fast model ID")]
    [string]$SmallModel = $env:BEDROCK_SMALL_MODEL_ID,
    
    [Parameter(HelpMessage = "Automatically add source line to PowerShell profile")]
    [switch]$AutoSource,
    
    [Parameter(HelpMessage = "Show what would be done without making changes")]
    [switch]$DryRun,
    
    [Parameter(HelpMessage = "Remove Claude Code Bedrock configuration")]
    [switch]$Uninstall,
    
    [Parameter(HelpMessage = "Show help message")]
    [switch]$Help
)

########################
# Script metadata
########################
$SCRIPT_VERSION = "1.1.0"
$SCRIPT_NAME = $MyInvocation.MyCommand.Name

########################
# Defaults
########################
if (-not $Region) { $Region = "us-east-1" }
if (-not $Model) { $Model = "us.anthropic.claude-opus-4-5-20251101-v1:0" }
if (-not $SmallModel) { $SmallModel = "us.anthropic.claude-haiku-4-5-20251001-v1:0" }

$MaxOutputTokens = if ($env:CLAUDE_CODE_MAX_OUTPUT_TOKENS) { $env:CLAUDE_CODE_MAX_OUTPUT_TOKENS } else { "64000" }
$MaxThinkingTokens = if ($env:MAX_THINKING_TOKENS) { $env:MAX_THINKING_TOKENS } else { "8192" }
$AutoSourceRC = if ($env:AUTO_SOURCE_RC -eq "1") { $true } else { $AutoSource.IsPresent }

########################
# Paths
########################
$ClaudeHome = Join-Path $env:USERPROFILE ".claude"
$SettingsFile = Join-Path $ClaudeHome "settings.json"
$ShellSnippet = Join-Path $ClaudeHome "claude-code-bedrock.env"
$BackupSuffix = ".backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$SettingsBackupPath = $null

########################
# Helper functions
########################
function Write-Error-Message {
    param([string]$Message)
    Write-Host "ERROR: " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Warning-Message {
    param([string]$Message)
    Write-Host "WARNING: " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Info {
    param([string]$Message)
    Write-Host "==> " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Debug-Message {
    param([string]$Message)
    if ($env:DEBUG -eq "1") {
        Write-Host "DEBUG: " -ForegroundColor Blue -NoNewline
        Write-Host $Message
    }
}

function Test-Command {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Show-Help {
    Get-Help $PSCommandPath -Detailed
}

########################
# Configuration writers
########################
function Write-JsonSettings {
    param(
        [string]$FilePath,
        [string]$AwsRegion,
        [string]$AwsProfile,
        [string]$ModelId,
        [string]$SmallModelId,
        [string]$MaxTokens,
        [string]$ThinkTokens
    )
    
    # Determine the auth refresh command
    $authRefreshCmd = if ($AwsProfile) {
        "aws sso login --profile $AwsProfile"
    } else {
        "aws login"
    }
    
    # Build settings object
    $settings = @{
        awsAuthRefresh = $authRefreshCmd
        env = @{
            CLAUDE_CODE_USE_BEDROCK = "1"
            AWS_REGION = $AwsRegion
            ANTHROPIC_MODEL = $ModelId
            ANTHROPIC_SMALL_FAST_MODEL = $SmallModelId
            CLAUDE_CODE_MAX_OUTPUT_TOKENS = $MaxTokens
            MAX_THINKING_TOKENS = $ThinkTokens
        }
    }
    
    # Add AWS_PROFILE if configured
    if ($AwsProfile) {
        $settings.env.AWS_PROFILE = $AwsProfile
    }
    
    $settingsJson = $settings | ConvertTo-Json -Depth 10
    
    if ($DryRun) {
        Write-Info "[DRY RUN] Would write settings to: $FilePath"
        Write-Host $settingsJson
        return
    }
    
    $parentDir = Split-Path $FilePath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    # Backup existing file if present
    if (Test-Path $FilePath) {
        $script:SettingsBackupPath = "$FilePath$BackupSuffix"
        Copy-Item $FilePath $script:SettingsBackupPath
        Write-Info "Backed up existing settings to: $script:SettingsBackupPath"
    }
    
    $settingsJson | Set-Content -Path $FilePath -Encoding UTF8
}

function Write-ShellSnippet {
    param(
        [string]$FilePath,
        [string]$AwsRegion,
        [string]$AwsProfile,
        [string]$ModelId,
        [string]$SmallModelId,
        [string]$MaxTokens,
        [string]$ThinkTokens
    )
    
    if ($DryRun) {
        Write-Info "[DRY RUN] Would write shell snippet to: $FilePath"
        return
    }
    
    $parentDir = Split-Path $FilePath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    $snippet = @"
# Claude Code + Bedrock environment (global)
# Generated by $SCRIPT_NAME v$SCRIPT_VERSION on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
`$env:CLAUDE_CODE_USE_BEDROCK = "1"
`$env:AWS_REGION = "$AwsRegion"
"@
    
    if ($AwsProfile) {
        $snippet += "`n`$env:AWS_PROFILE = ""$AwsProfile"""
    }
    
    $snippet += @"

`$env:ANTHROPIC_MODEL = "$ModelId"
`$env:ANTHROPIC_SMALL_FAST_MODEL = "$SmallModelId"
`$env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = "$MaxTokens"
`$env:MAX_THINKING_TOKENS = "$ThinkTokens"
"@
    
    $snippet | Set-Content -Path $FilePath -Encoding UTF8
}

########################
# PowerShell Profile handling
########################
function Get-PowerShellProfilePath {
    # Use CurrentUserAllHosts profile for maximum compatibility
    # Access the automatic $PROFILE variable which is a string with note properties
    $profileObj = $PROFILE.PSObject.Properties['CurrentUserAllHosts']
    if ($profileObj -and $profileObj.Value) {
        return $profileObj.Value
    } else {
        # Fallback: construct the path manually
        $docsPath = [Environment]::GetFolderPath('MyDocuments')
        return Join-Path $docsPath "WindowsPowerShell\profile.ps1"
    }
}

function Add-SourceLineToProfile {
    param(
        [string]$ProfilePath,
        [string]$SnippetPath
    )
    
    if ($DryRun) {
        Write-Info "[DRY RUN] Would append source line to: $ProfilePath"
        return
    }
    
    $parentDir = Split-Path $ProfilePath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    if (-not (Test-Path $ProfilePath)) {
        New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
    }
    
    $profileContent = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
    if ($profileContent -and $profileContent.Contains($SnippetPath)) {
        Write-Info "PowerShell profile already sources env snippet: $ProfilePath"
        return
    }
    
    $sourceLine = @"

# Claude Code + Bedrock (added by $SCRIPT_NAME on $(Get-Date -Format 'yyyy-MM-dd'))
if (Test-Path "$SnippetPath") {
    . "$SnippetPath"
}
"@
    
    Add-Content -Path $ProfilePath -Value $sourceLine -Encoding UTF8
    Write-Info "Appended source line to: $ProfilePath"
}

function Remove-SourceLineFromProfile {
    param(
        [string]$ProfilePath,
        [string]$SnippetPath
    )
    
    if (-not (Test-Path $ProfilePath)) {
        return
    }
    
    if ($DryRun) {
        Write-Info "[DRY RUN] Would remove source line from: $ProfilePath"
        return
    }
    
    # Create a backup
    Copy-Item $ProfilePath "$ProfilePath$BackupSuffix"
    
    # Read all lines and filter out Claude Code related lines
    $lines = Get-Content $ProfilePath
    $newLines = @()
    $skipNext = 0
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        
        if ($skipNext -gt 0) {
            $skipNext--
            continue
        }
        
        if ($line -match "# Claude Code \+ Bedrock") {
            # Skip this line and the next 3 lines (the if block)
            $skipNext = 3
            continue
        }
        
        $newLines += $line
    }
    
    $newLines | Set-Content -Path $ProfilePath -Encoding UTF8
    Write-Info "Removed source line from: $ProfilePath"
}

########################
# Uninstall
########################
function Invoke-Uninstall {
    Write-Info "Uninstalling Claude Code Bedrock configuration..."
    
    $profilePath = Get-PowerShellProfilePath
    
    if (Test-Path $ShellSnippet) {
        if ($DryRun) {
            Write-Info "[DRY RUN] Would remove: $ShellSnippet"
        } else {
            Remove-Item $ShellSnippet -Force
            Write-Info "Removed: $ShellSnippet"
        }
    }
    
    if (Test-Path $SettingsFile) {
        if ($DryRun) {
            Write-Info "[DRY RUN] Would remove: $SettingsFile"
        } else {
            Remove-Item $SettingsFile -Force
            Write-Info "Removed: $SettingsFile"
        }
    }
    
    Remove-SourceLineFromProfile -ProfilePath $profilePath -SnippetPath $ShellSnippet
    
    Write-Host ""
    Write-Info "Uninstall complete."
    Write-Info "You may need to restart your PowerShell session or run: Remove-Item env:CLAUDE_CODE_USE_BEDROCK"
}

########################
# AWS verification
########################
function Test-AwsAuth {
    if (-not (Test-Command "aws")) {
        Write-Info "AWS CLI not found (optional). Install for easier auth verification."
        return
    }
    
    Write-Info "Checking AWS credentials..."
    
    $awsArgs = @("sts", "get-caller-identity")
    if ($Profile) {
        $awsArgs = @("--profile", $Profile) + $awsArgs
    }
    
    try {
        $identity = & aws $awsArgs 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Info "AWS auth successful!"
            $identity | Where-Object { $_ -match "(Account|Arn)" } | ForEach-Object {
                Write-Host "    $_"
            }
        } else {
            throw "AWS auth failed"
        }
    } catch {
        Write-Warning-Message "AWS auth check failed. This is OK if you haven't logged in yet."
        Write-Host ""
        if ($Profile) {
            Write-Host "  To authenticate with your configured profile:"
            Write-Host "    " -NoNewline
            Write-Host "aws sso login --profile $Profile" -ForegroundColor White
        } else {
            Write-Host "  To authenticate:"
            Write-Host "    " -NoNewline
            Write-Host "aws login" -ForegroundColor White
        }
        Write-Host ""
    }
}

function Test-BedrockAccess {
    if (-not (Test-Command "aws")) {
        return
    }
    
    Write-Info "Checking Bedrock model access..."
    
    try {
        $models = aws bedrock list-foundation-models `
            --region $Region `
            --by-provider anthropic `
            --query "modelSummaries[?contains(modelId, 'claude')].modelId" `
            --output text 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $modelCount = ($models -split '\s+').Count
            Write-Info "Found $modelCount Claude models available in Bedrock"
        } else {
            throw "Failed to list models"
        }
    } catch {
        Write-Warning-Message "Could not list Bedrock models. Check your permissions."
        Write-Host "    Error: $_"
    }
}

########################
# Main
########################
function Main {
    Write-Host ""
    Write-Host "Claude Code + AWS Bedrock Setup " -NoNewline
    Write-Host "v$SCRIPT_VERSION" -ForegroundColor Cyan
    Write-Host ("-" * 60)
    Write-Host ""
    
    if ($Help) {
        Show-Help
        return
    }
    
    if ($DryRun) {
        Write-Warning-Message "Running in DRY RUN mode - no changes will be made"
        Write-Host ""
    }
    
    if ($Uninstall) {
        Invoke-Uninstall
        return
    }
    
    # Display configuration
    Write-Host "Configuration:"
    Write-Host "  AWS Region:    " -NoNewline
    Write-Host $Region -ForegroundColor White
    
    if ($Profile) {
        Write-Host "  AWS Profile:   " -NoNewline
        Write-Host $Profile -ForegroundColor White
        Write-Host "  Auto Refresh:  " -NoNewline
        Write-Host "Enabled" -ForegroundColor Green -NoNewline
        Write-Host " (aws sso login --profile $Profile)"
    } else {
        Write-Host "  AWS Profile:   " -NoNewline
        Write-Host "Not set" -ForegroundColor Yellow -NoNewline
        Write-Host " (using default credentials)"
        Write-Host "  Auto Refresh:  " -NoNewline
        Write-Host "Enabled" -ForegroundColor Green -NoNewline
        Write-Host " (aws login)"
    }
    
    Write-Host "  Primary Model: " -NoNewline
    Write-Host $Model -ForegroundColor White
    Write-Host "  Small Model:   " -NoNewline
    Write-Host $SmallModel -ForegroundColor White
    Write-Host "  Max Tokens:    " -NoNewline
    Write-Host $MaxOutputTokens -ForegroundColor White
    Write-Host "  Think Tokens:  " -NoNewline
    Write-Host $MaxThinkingTokens -ForegroundColor White
    Write-Host ""
    
    # Write configuration files
    Write-Info "Writing settings: $SettingsFile"
    Write-JsonSettings -FilePath $SettingsFile `
        -AwsRegion $Region `
        -AwsProfile $Profile `
        -ModelId $Model `
        -SmallModelId $SmallModel `
        -MaxTokens $MaxOutputTokens `
        -ThinkTokens $MaxThinkingTokens
    
    Write-Info "Writing shell snippet: $ShellSnippet"
    Write-ShellSnippet -FilePath $ShellSnippet `
        -AwsRegion $Region `
        -AwsProfile $Profile `
        -ModelId $Model `
        -SmallModelId $SmallModel `
        -MaxTokens $MaxOutputTokens `
        -ThinkTokens $MaxThinkingTokens
    
    # Handle PowerShell profile
    if ($AutoSourceRC) {
        $profilePath = Get-PowerShellProfilePath
        Add-SourceLineToProfile -ProfilePath $profilePath -SnippetPath $ShellSnippet
    } else {
        Write-Info "Skipping PowerShell profile modification (use -AutoSource to enable)"
    }
    
    Write-Host ""
    
    # AWS checks
    Test-AwsAuth
    
    Write-Host ""
    Write-Host ("-" * 60)
    Write-Host "[OK] Setup complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Files created:"
    Write-Host "  * $SettingsFile"
    Write-Host "  * $ShellSnippet"
    
    if ($SettingsBackupPath) {
        Write-Host ""
        Write-Host "Previous settings backed up to:"
        Write-Host "  * $SettingsBackupPath"
    }
    
    Write-Host ""
    
    # Show auto-refresh status
    if ($Profile) {
        Write-Host "[OK] Auto credential refresh enabled" -ForegroundColor Green
        Write-Host "  When your AWS session expires, Claude Code will automatically"
        Write-Host "  run: aws sso login --profile $Profile"
        Write-Host ""
    } else {
        Write-Host "[OK] Auto credential refresh enabled" -ForegroundColor Green
        Write-Host "  When your AWS session expires, Claude Code will automatically"
        Write-Host "  run: aws login"
        Write-Host ""
        Write-Host "TIP:" -ForegroundColor Yellow -NoNewline
        Write-Host " If you work with multiple AWS accounts, use -Profile to"
        Write-Host "     specify which profile to use for credential refresh."
        Write-Host ""
    }
    
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host ""
    
    if ($Profile) {
        Write-Host "  1. Login to AWS (if not already):"
        Write-Host "     " -NoNewline
        Write-Host "aws sso login --profile $Profile" -ForegroundColor White
        Write-Host ""
        Write-Host "  2. Activate in your current PowerShell session:"
        Write-Host "     " -NoNewline
        Write-Host ". '$ShellSnippet'" -ForegroundColor White
        Write-Host ""
        Write-Host "  3. Or reload your PowerShell session"
        Write-Host ""
        Write-Host "  4. Start Claude Code:"
        Write-Host "     " -NoNewline
        Write-Host "claude" -ForegroundColor White
    } else {
        Write-Host "  1. Activate in your current PowerShell session:"
        Write-Host "     " -NoNewline
        Write-Host ". '$ShellSnippet'" -ForegroundColor White
        Write-Host ""
        Write-Host "  2. Or reload your PowerShell session"
        Write-Host ""
        Write-Host "  3. Start Claude Code:"
        Write-Host "     " -NoNewline
        Write-Host "claude" -ForegroundColor White
    }
    
    Write-Host ""
    
    if (-not $AutoSourceRC) {
        Write-Host "TIP:" -ForegroundColor Yellow -NoNewline
        Write-Host " To auto-load in new PowerShell sessions, run:"
        Write-Host "     .\$SCRIPT_NAME -AutoSource" -ForegroundColor White
        Write-Host ""
    }
    
    Write-Host "If you encounter Bedrock throughput errors, use an Inference Profile ARN:"
    Write-Host "  .\$SCRIPT_NAME -Model ARN" -ForegroundColor White
    Write-Host ""
}

# Run main function
Main
