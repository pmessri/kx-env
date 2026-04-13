# =============================================================================
#  gen-cheatsheet.ps1  —  AI-agentic cheatsheet generator
#  ~/dev/pwsh-env/gen-cheatsheet.ps1
#
#  Reads your PowerShell profile + config, strips secrets per .cheatsheet-ignore,
#  sends to Claude API, and writes a clean CHEATSHEET.md you can query anytime.
#
#  Usage:
#    .\gen-cheatsheet.ps1                    # full regeneration
#    .\gen-cheatsheet.ps1 -Section git       # regenerate only one section
#    .\gen-cheatsheet.ps1 -Dry               # preview what gets sent (no API call)
#    .\gen-cheatsheet.ps1 -Query "aws"       # query existing cheatsheet
# =============================================================================

param(
    [string]$Section = "",
    [switch]$Dry,
    [string]$Query = ""
)

$script:Root          = $PSScriptRoot
$script:ProfilePath   = $PROFILE
$script:ConfigFile    = Join-Path $script:Root ".config"
$script:IgnoreFile    = Join-Path $script:Root ".cheatsheet-ignore"
$script:OutputFile    = Join-Path $script:Root "CHEATSHEET.md"
$script:EnvManager    = Join-Path $script:Root "env-manager.ps1"

# =============================================================================
# QUERY MODE — search existing cheatsheet without regenerating
# =============================================================================
if ($Query) {
    if (-not (Test-Path $script:OutputFile)) {
        Write-Host "  No CHEATSHEET.md yet. Run gen-cheatsheet.ps1 first." -ForegroundColor Yellow
        exit
    }
    Write-Host ""
    Write-Host "  Searching cheatsheet for: $Query" -ForegroundColor Cyan
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    $lines = Get-Content $script:OutputFile
    $inSection = $false
    $results   = @()

    foreach ($line in $lines) {
        if ($line -match "^#{1,3}.*$Query" -or $line -imatch $Query) {
            $results += $line
        }
    }

    if ($results.Count -eq 0) {
        Write-Host "  No matches found for '$Query'" -ForegroundColor Yellow
    } else {
        $results | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    }
    Write-Host ""
    exit
}

# =============================================================================
# LOAD API KEY
# =============================================================================
function _Get-AnthropicKey {
    # Try session env first
    if ($env:ANTHROPIC_API_KEY) { return $env:ANTHROPIC_API_KEY }

    # Try loading from env-manager
    if (Test-Path $script:EnvManager) {
        . $script:EnvManager 2>$null
        if ($env:ANTHROPIC_API_KEY) { return $env:ANTHROPIC_API_KEY }
    }

    Write-Host "  ANTHROPIC_API_KEY not found. Run: env-set ANTHROPIC_API_KEY sk-ant-..." -ForegroundColor Red
    exit 1
}

# =============================================================================
# IGNORE RULES
# =============================================================================
function _Load-IgnorePatterns {
    if (-not (Test-Path $script:IgnoreFile)) { return @() }
    return Get-Content $script:IgnoreFile |
        Where-Object { $_ -and -not $_.StartsWith("#") } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
}

function _Sanitize-Content {
    param([string]$content, [string[]]$patterns)

    $lines  = $content -split "`n"
    $output = @()
    $skip   = $false

    foreach ($line in $lines) {
        # Check if this line starts a section to skip
        $sectionSkip = $patterns | Where-Object {
            $_ -notmatch '[\*\?]' -and $line -match [regex]::Escape($_) -and $line -match "^#"
        }
        if ($sectionSkip) { $skip = $true }

        # Check if this line starts a new section (stops skipping)
        if ($skip -and $line -match "^# =+$" -and $output.Count -gt 0) { $skip = $false }

        if ($skip) {
            $output += "# [SECTION REDACTED — contains sensitive config]"
            continue
        }

        # Line-level redaction
        $redacted = $false
        foreach ($pattern in $patterns) {
            if ($line -match [regex]::Escape($pattern) -or
                ($pattern -match '[\*\?\+\^]' -and $line -match $pattern)) {
                $output += "# [REDACTED]"
                $redacted = $true
                break
            }
        }

        if (-not $redacted) { $output += $line }
    }

    return ($output -join "`n")
}

# =============================================================================
# COLLECT SOURCE FILES
# =============================================================================
function _Collect-Sources {
    $sources = [System.Collections.Generic.List[hashtable]]::new()
    $patterns = _Load-IgnorePatterns

    # 1. Main PowerShell profile
    if (Test-Path $script:ProfilePath) {
        $raw  = Get-Content $script:ProfilePath -Raw
        $clean = _Sanitize-Content $raw $patterns
        $sources.Add(@{ name = "PowerShell Profile"; content = $clean })
    }

    # 2. .config file
    if (Test-Path $script:ConfigFile) {
        $raw  = Get-Content $script:ConfigFile -Raw
        $sources.Add(@{ name = "Project Config (.config)"; content = $raw })
    }

    # 3. Any other .ps1 files in the project dir (except env-manager secrets)
    $skipFiles = @("env-manager.ps1", "gen-cheatsheet.ps1")
    Get-ChildItem $script:Root -Filter "*.ps1" | Where-Object {
        $_.Name -notin $skipFiles
    } | ForEach-Object {
        $raw   = Get-Content $_.FullName -Raw
        $clean = _Sanitize-Content $raw $patterns
        $sources.Add(@{ name = $_.Name; content = $clean })
    }

    return $sources
}

# =============================================================================
# BUILD PROMPT
# =============================================================================
function _Build-Prompt {
    param($sources)

    $sectionFilter = if ($Section) { "Focus only on the '$Section' section." } else { "" }

    $sourceDump = ($sources | ForEach-Object {
        "### $($_.name)`n`n$($_.content)"
    }) -join "`n`n---`n`n"

    return @"
You are a technical documentation generator. Analyze the following PowerShell dev environment source code and configuration files, then produce a comprehensive, well-structured CHEATSHEET.md in Markdown format.

$sectionFilter

Requirements for the cheatsheet:
- Use clear Markdown with ## section headers matching the logical groupings in the code
- For each command/alias/function, show: the command name, a one-line description, and a usage example
- Use tables where appropriate (command | description | example)
- Include a quick-reference summary table at the top with the most commonly used commands
- Group by category: Navigation, Git, Editors, Cloud (AWS/Azure/GCP), AI Tools, GitHub CLI, Node/Python, Docker, Utilities
- Do NOT include any API keys, secrets, or sensitive values
- Include the WSL2 bridge commands
- Keep it practical — this is a living reference a developer will query daily
- At the bottom, include a "Configuration" section explaining the .config file and env-manager
- Format must be clean GitHub-flavored Markdown

Source files to analyze:

$sourceDump
"@
}

# =============================================================================
# CALL CLAUDE API
# =============================================================================
function _Call-Claude {
    param([string]$prompt, [string]$apiKey)

    $body = @{
        model      = "claude-opus-4-5"
        max_tokens = 4096
        messages   = @(@{ role = "user"; content = $prompt })
    } | ConvertTo-Json -Depth 5

    $headers = @{
        "x-api-key"         = $apiKey
        "anthropic-version" = "2023-06-01"
        "content-type"      = "application/json"
    }

    Write-Host "  Calling Claude API..." -ForegroundColor Yellow -NoNewline
    $resp = Invoke-RestMethod `
        -Uri "https://api.anthropic.com/v1/messages" `
        -Method POST `
        -Headers $headers `
        -Body $body

    Write-Host " done" -ForegroundColor Green
    return $resp.content[0].text
}

# =============================================================================
# WRITE OUTPUT
# =============================================================================
function _Write-Cheatsheet {
    param([string]$content)

    $header = @"
<!--
  CHEATSHEET.md — Auto-generated by gen-cheatsheet.ps1
  Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm")
  DO NOT EDIT MANUALLY — run gen-cheatsheet.ps1 to regenerate
-->

"@
    ($header + $content) | Set-Content $script:OutputFile -Force
    Write-Host "  ✓ Written to: $script:OutputFile" -ForegroundColor Green
}

# =============================================================================
# MAIN
# =============================================================================
Write-Host ""
Write-Host "  gen-cheatsheet.ps1" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray

Write-Host "  Collecting source files..." -ForegroundColor Yellow -NoNewline
$sources  = _Collect-Sources
Write-Host " $($sources.Count) files" -ForegroundColor Green

$prompt   = _Build-Prompt $sources
$charCount = $prompt.Length

Write-Host "  Prompt size: $charCount chars" -ForegroundColor DarkGray

if ($Dry) {
    Write-Host ""
    Write-Host "  ── DRY RUN (what would be sent to Claude) ──" -ForegroundColor Yellow
    Write-Host $prompt
    Write-Host "  ────────────────────────────────────────────" -ForegroundColor Yellow
    exit
}

$apiKey   = _Get-AnthropicKey
$markdown = _Call-Claude $prompt $apiKey

_Write-Cheatsheet $markdown

Write-Host ""
Write-Host "  Cheatsheet regenerated!" -ForegroundColor Cyan
Write-Host "  Query it anytime with: .\gen-cheatsheet.ps1 -Query <term>" -ForegroundColor DarkGray
Write-Host ""
